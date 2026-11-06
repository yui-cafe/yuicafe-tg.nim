import std/[httpclient, json, os]

import yuicafe/[config, types]

type
  ## Client for Telegram Bot API requests.
  ##
  ## Create an instance with `newBotClient` and release its HTTP resources with
  ## `close` when the client is no longer needed.
  BotClient* = ref object
    config*: BotConfig
    http: HttpClient

proc newBotClient*(config: BotConfig): BotClient =
  ## Creates a client using `config`.
  ##
  ## The client owns its underlying HTTP connection and must be closed by the
  ## caller.
  let headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Accept": "application/json"
  })
  BotClient(
    config: config,
    http: newHttpClient(
      userAgent = "yuicafe/0.1",
      maxRedirects = 0,
      timeout = config.requestTimeoutMs,
      headers = headers
    )
  )

proc close*(client: BotClient) =
  ## Releases the HTTP resources owned by `client`.
  if not client.isNil and not client.http.isNil:
    client.http.close()

proc endpoint(client: BotClient; apiMethod: string): string =
  client.config.apiBaseUrl & "/bot" & client.config.token & "/" & apiMethod

proc apiError(apiMethod, message: string; statusCode = 0; errorCode = 0;
    retryAfterSeconds = 0): ref TelegramError =
  result = newException(TelegramError, message)
  result.apiMethod = apiMethod
  result.statusCode = statusCode
  result.errorCode = errorCode
  result.retryAfterSeconds = retryAfterSeconds

proc decodeError(apiMethod: string; statusCode: int;
    response: JsonNode): ref TelegramError =
  let description =
    if response.kind == JObject and response.hasKey("description"):
      response["description"].getStr("Telegram API request failed")
    else:
      "Telegram API request failed"
  var retryAfterSeconds = 0
  if response.kind == JObject and response.hasKey("parameters"):
    let parameters = response["parameters"]
    if parameters.kind == JObject and parameters.hasKey("retry_after"):
      retryAfterSeconds = parameters["retry_after"].getInt()
  apiError(apiMethod, description, statusCode,
    if response.kind == JObject and response.hasKey("error_code"):
      response["error_code"].getInt()
    else:
      statusCode,
    retryAfterSeconds)

proc isRetryable(error: ref TelegramError): bool =
  error.statusCode == 429 or error.errorCode == 429 or
    error.statusCode >= 500 or error.errorCode >= 500 or
    error.statusCode == 0

proc delayForAttempt(config: BotConfig; attempt: int;
    retryAfterSeconds: int): int =
  if retryAfterSeconds > 0:
    return min(retryAfterSeconds * 1_000, config.retryMaxDelayMs)

  var delay = config.retryBaseDelayMs
  for _ in 1 ..< attempt:
    delay = min(delay * 2, config.retryMaxDelayMs)
  delay

proc invoke(client: BotClient; apiMethod: string; params: JsonNode;
    retrySafe: bool): JsonNode =
  var attempt = 0
  while true:
    try:
      let response = client.http.request(
        client.endpoint(apiMethod),
        httpMethod = HttpPost,
        body = $params
      )
      let responseBody = response.body
      let payload = parseJson(responseBody)
      if response.code.int notin 200 .. 299 or
          payload.kind != JObject or not payload["ok"].getBool():
        raise decodeError(apiMethod, response.code.int, payload)
      if not payload.hasKey("result"):
        raise apiError(apiMethod, "Telegram API response did not contain result",
          response.code.int)
      return payload["result"]
    except TelegramError as error:
      if not retrySafe or not error.isRetryable or attempt >=
          client.config.maxRetries:
        raise
      inc attempt
      sleep(delayForAttempt(client.config, attempt, error.retryAfterSeconds))
    except CatchableError as error:
      if not retrySafe or attempt >= client.config.maxRetries:
        raise apiError(apiMethod, "network request failed: " & error.msg)
      inc attempt
      sleep(delayForAttempt(client.config, attempt, 0))

proc getMe*(client: BotClient): User =
  ## Returns the bot account associated with `client`.
  decodeUser(client.invoke("getMe", newJObject(), retrySafe = true))

proc getWebhookInfo*(client: BotClient): WebhookInfo =
  ## Returns the webhook configuration currently set for the bot.
  decodeWebhookInfo(client.invoke("getWebhookInfo", newJObject(),
      retrySafe = true))

proc deleteWebhook*(client: BotClient; dropPendingUpdates = false) =
  ## Removes the bot's webhook.
  ##
  ## Set `dropPendingUpdates` only when discarding undelivered updates is
  ## intentional.
  discard client.invoke("deleteWebhook", %*{
    "drop_pending_updates": dropPendingUpdates
  }, retrySafe = true)

proc setMyCommands*(client: BotClient; commands: openArray[BotCommand]) =
  ## Replaces Telegram's global command menu with `commands`.
  ##
  ## Command names and descriptions are validated before the request is sent.
  if commands.len > 100:
    raise newException(ValueError, "Telegram allows at most 100 bot commands")

  var encodedCommands = newJArray()
  for command in commands:
    if command.command.len == 0 or command.command.len > 32:
      raise newException(ValueError, "bot command names must be 1 to 32 characters")
    if command.description.len == 0 or command.description.len > 256:
      raise newException(ValueError,
        "bot command descriptions must be 1 to 256 characters")
    encodedCommands.add(%*{
      "command": command.command,
      "description": command.description
    })

  let result = client.invoke("setMyCommands", %*{
    "commands": encodedCommands
  }, retrySafe = true)
  if not result.getBool():
    raise apiError("setMyCommands", "Telegram did not confirm the command menu update")

proc getUpdates*(client: BotClient; offset = 0'i64; timeoutSeconds = 30;
    limit = 100; allowedUpdates: openArray[string] = []): seq[Update] =
  ## Retrieves pending updates, optionally waiting up to `timeoutSeconds`.
  ##
  ## The request timeout is temporarily extended to accommodate long polling.
  var params = %*{
    "timeout": timeoutSeconds,
    "limit": limit
  }
  if offset != 0:
    params["offset"] = %offset
  if allowedUpdates.len > 0:
    params["allowed_updates"] = %allowedUpdates

  let originalTimeout = client.http.timeout
  client.http.timeout = max(originalTimeout, (timeoutSeconds + 10) * 1_000)
  try:
    let payload = client.invoke("getUpdates", params, retrySafe = true)
    if payload.kind != JArray:
      raise apiError("getUpdates", "Telegram API returned a non-array result")
    for item in payload.items:
      result.add(decodeUpdate(item))
  finally:
    client.http.timeout = originalTimeout

proc sendMessage*(client: BotClient; chatId: int64; text: string): Message =
  ## Sends `text` to `chatId` and returns Telegram's resulting message.
  ##
  ## This operation is not retried because an ambiguous transport failure could
  ## otherwise create duplicate messages.
  if text.len == 0:
    raise newException(ValueError, "message text cannot be empty")
  let payload = client.invoke("sendMessage", %*{
    "chat_id": chatId,
    "text": text
  }, retrySafe = false)
  decodeMessage(payload)
