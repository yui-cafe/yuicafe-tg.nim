import std/[os, strutils]

type
  ## Settings used for Telegram Bot API requests.
  BotConfig* = object
    token*: string
    apiBaseUrl*: string
    requestTimeoutMs*: int
    maxRetries*: int
    retryBaseDelayMs*: int
    retryMaxDelayMs*: int

  ## Settings that control long polling and its failure backoff.
  PollingConfig* = object
    timeoutSeconds*: int
    limit*: int
    allowedUpdates*: seq[string]
    failureDelayMs*: int
    failureMaxDelayMs*: int

  ## Complete configuration for the bundled application or a custom runtime.
  AppConfig* = object
    bot*: BotConfig
    polling*: PollingConfig
    deleteWebhook*: bool
    ownerIds*: seq[int64]

proc envInt(name: string; default: int; min: int; max: int): int =
  let value = getEnv(name)
  if value.len == 0:
    return default
  try:
    result = parseInt(value)
  except ValueError:
    raise newException(ValueError, name & " must be an integer")
  if result < min or result > max:
    raise newException(ValueError,
      name & " must be between " & $min & " and " & $max)

proc envBool(name: string; default = false): bool =
  let value = getEnv(name)
  if value.len == 0:
    return default
  case value.toLowerAscii()
  of "1", "true", "yes":
    true
  of "0", "false", "no":
    false
  else:
    raise newException(ValueError, name & " must be true or false")

proc envList(name: string): seq[string] =
  let value = getEnv(name)
  if value.len == 0:
    return @[]
  for item in value.split(','):
    let trimmed = item.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc envInt64List(name: string): seq[int64] =
  for value in envList(name):
    try:
      result.add(int64(parseBiggestInt(value)))
    except ValueError:
      raise newException(ValueError, name & " must be a comma-separated list of integer IDs")

proc loadConfig*(): AppConfig =
  ## Reads and validates application configuration from environment variables.
  ##
  ## `TELEGRAM_BOT_TOKEN` is required. See `README.md` for every supported
  ## variable and its default value.
  result.bot.token = getEnv("TELEGRAM_BOT_TOKEN").strip()
  if result.bot.token.len == 0:
    raise newException(ValueError, "TELEGRAM_BOT_TOKEN is required")

  result.bot.apiBaseUrl = getEnv("TELEGRAM_API_BASE_URL",
    "https://api.telegram.org").strip(chars = {'/'})
  if not result.bot.apiBaseUrl.startsWith("https://") and
      not result.bot.apiBaseUrl.startsWith("http://"):
    raise newException(ValueError,
      "TELEGRAM_API_BASE_URL must start with http:// or https://")

  result.polling.timeoutSeconds = envInt("TELEGRAM_POLL_TIMEOUT_SECONDS", 30, 1, 50)
  result.polling.limit = envInt("TELEGRAM_POLL_LIMIT", 100, 1, 100)
  result.bot.requestTimeoutMs = envInt("TELEGRAM_REQUEST_TIMEOUT_MS",
    (result.polling.timeoutSeconds + 10) * 1000, 1_000, 120_000)
  result.bot.maxRetries = envInt("TELEGRAM_MAX_RETRIES", 3, 0, 10)
  result.bot.retryBaseDelayMs = envInt("TELEGRAM_RETRY_BASE_DELAY_MS", 500, 50, 60_000)
  result.bot.retryMaxDelayMs = envInt("TELEGRAM_RETRY_MAX_DELAY_MS", 30_000,
      100, 300_000)
  result.polling.failureDelayMs = envInt("TELEGRAM_FAILURE_DELAY_MS", 1_000,
      100, 60_000)
  result.polling.failureMaxDelayMs = envInt("TELEGRAM_FAILURE_MAX_DELAY_MS",
    30_000, 100, 300_000)
  result.polling.allowedUpdates = envList("TELEGRAM_ALLOWED_UPDATES")
  result.deleteWebhook = envBool("TELEGRAM_DELETE_WEBHOOK")
  result.ownerIds = envInt64List("TELEGRAM_OWNER_IDS")

  if result.bot.retryBaseDelayMs > result.bot.retryMaxDelayMs:
    raise newException(ValueError,
      "TELEGRAM_RETRY_BASE_DELAY_MS cannot exceed TELEGRAM_RETRY_MAX_DELAY_MS")
  if result.polling.failureDelayMs > result.polling.failureMaxDelayMs:
    raise newException(ValueError,
      "TELEGRAM_FAILURE_DELAY_MS cannot exceed TELEGRAM_FAILURE_MAX_DELAY_MS")
