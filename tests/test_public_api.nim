import std/unittest

import yuicafe as legacy_yuicafe
import yuicafe_tg

suite "Telegram library facade":
  test "preserve the legacy yuicafe facade":
    let config = legacy_yuicafe.BotConfig(
      token: "test-token",
      apiBaseUrl: "https://api.telegram.org",
      requestTimeoutMs: 1_000,
      maxRetries: 0,
      retryBaseDelayMs: 50,
      retryMaxDelayMs: 50
    )
    let client = legacy_yuicafe.newBotClient(config)
    defer:
      client.close()
    let router = legacy_yuicafe.newCommandRouter()

    check not client.isNil
    check not router.isNil

  test "expose the client and configuration types":
    let config = BotConfig(
      token: "test-token",
      apiBaseUrl: "https://api.telegram.org",
      requestTimeoutMs: 1_000,
      maxRetries: 0,
      retryBaseDelayMs: 50,
      retryMaxDelayMs: 50
    )
    let client = newBotClient(config)
    defer:
      client.close()

    check not client.isNil
    check client.config.token == "test-token"

  test "expose polling and decoded update types":
    let config = PollingConfig(
      timeoutSeconds: 30,
      limit: 100,
      failureDelayMs: 100,
      failureMaxDelayMs: 100
    )
    let update = Update(id: 42)

    check config.timeoutSeconds == 30
    check update.id == 42

  test "expose chat membership types":
    let administrator = ChatMember(status: "administrator")

    check administrator.isAdministrator

  test "expose moderation client methods":
    check compiles((block:
      proc get_member(client: BotClient): ChatMember =
        client.getChatMember(1, 1)
    ))
    check compiles((block:
      proc ban_member(client: BotClient) =
        client.banChatMember(1, 1)
    ))
    check compiles((block:
      proc temporarily_ban_member(client: BotClient) =
        client.banChatMember(1, 1, untilDate = 1_800)
    ))

  test "classify retryable Telegram errors":
    let permanentError = newException(TelegramError, "forbidden")
    permanentError.statusCode = 403
    check not permanentError.isRetryable

    let transientError = newException(TelegramError, "rate limited")
    transientError.statusCode = 429
    check transientError.isRetryable
