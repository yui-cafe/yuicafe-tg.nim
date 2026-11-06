## Configuration value types for Telegram client and polling behavior.
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
