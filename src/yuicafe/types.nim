import std/json

type
  ## Describes a failed Telegram API request or transport operation.
  TelegramError* = object of CatchableError
    ## A Bot API response or transport failure. It never includes the bot token.
    apiMethod*: string
    statusCode*: int
    errorCode*: int
    retryAfterSeconds*: int

  ## A Telegram user returned by the Bot API.
  User* = object
    id*: int64
    isBot*: bool
    firstName*: string
    username*: string

  ## An entry in Telegram's command menu.
  BotCommand* = object
    command*: string
    description*: string

  ## A Telegram chat associated with a message.
  Chat* = object
    id*: int64
    kind*: string
    username*: string

  ## The supported fields of a Telegram message.
  Message* = object
    id*: int
    sender*: User
    hasFrom*: bool
    chat*: Chat
    text*: string
    hasText*: bool

  ## The supported fields of a Telegram update.
  ##
  ## `raw` preserves the entire decoded payload, including update kinds that do
  ## not yet have dedicated value fields.
  Update* = object
    id*: int64
    message*: Message
    hasMessage*: bool
    raw*: JsonNode

  ## The Bot API webhook state relevant to long-polling startup.
  WebhookInfo* = object
    url*: string
    pendingUpdateCount*: int

proc field(node: JsonNode; name: string): JsonNode =
  if not node.isNil and node.kind == JObject and node.hasKey(name):
    node[name]
  else:
    nil

proc decodeUser*(node: JsonNode): User =
  ## Decodes a Bot API user object from `node`.
  result.id = int64(field(node, "id").getBiggestInt())
  result.isBot = field(node, "is_bot").getBool()
  result.firstName = field(node, "first_name").getStr()
  result.username = field(node, "username").getStr()

proc decodeChat*(node: JsonNode): Chat =
  ## Decodes a Bot API chat object from `node`.
  result.id = int64(field(node, "id").getBiggestInt())
  result.kind = field(node, "type").getStr()
  result.username = field(node, "username").getStr()

proc decodeMessage*(node: JsonNode): Message =
  ## Decodes the supported fields of a Bot API message object from `node`.
  result.id = field(node, "message_id").getInt()
  let sender = field(node, "from")
  result.hasFrom = not sender.isNil and sender.kind == JObject
  if result.hasFrom:
    result.sender = decodeUser(sender)
  result.chat = decodeChat(field(node, "chat"))
  let text = field(node, "text")
  result.hasText = not text.isNil and text.kind == JString
  result.text = text.getStr()

proc decodeUpdate*(node: JsonNode): Update =
  ## Decodes the supported fields of a Bot API update object from `node`.
  result.id = int64(field(node, "update_id").getBiggestInt())
  result.raw = node
  let message = field(node, "message")
  result.hasMessage = not message.isNil and message.kind == JObject
  if result.hasMessage:
    result.message = decodeMessage(message)

proc decodeWebhookInfo*(node: JsonNode): WebhookInfo =
  ## Decodes a Bot API webhook-info object from `node`.
  result.url = field(node, "url").getStr()
  result.pendingUpdateCount = field(node, "pending_update_count").getInt()
