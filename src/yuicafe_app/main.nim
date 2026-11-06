## Startup composition for the bundled Yui Cafe bot.
import std/logging

import yuicafe_app/[commands/defaults, commands/router, config,
  services/warning_service]
import yuicafe_tg/[client, polling, types]

proc run*() =
  ## Starts the bundled application and closes owned resources on shutdown.
  addHandler(newConsoleLogger())
  var botClient: BotClient
  var warningService: WarningService

  try:
    let appConfig = loadConfig()
    botClient = newBotClient(appConfig.bot)
    warningService = newWarningService(appConfig.database)
    let bot = botClient.getMe()
    info "authenticated as @" & bot.username
    let router = newCommandRouter(bot.username, appConfig.ownerIds)
    router.registerDefaultCommands(warningService)
    let menuCommands = router.menuCommands()
    botClient.setMyCommands(menuCommands)
    info "synchronized " & $menuCommands.len & " commands with Telegram"

    let webhook = botClient.getWebhookInfo()
    if webhook.url.len > 0:
      if not appConfig.deleteWebhook:
        raise newException(ValueError,
          "an outgoing webhook is active; set TELEGRAM_DELETE_WEBHOOK=true " &
          "to remove it before long polling")
      botClient.deleteWebhook()
      info "removed existing webhook"

    proc handleUpdate(client: BotClient; update: Update) =
      let outcome = router.dispatch(client, update)
      case outcome.kind
      of dkPermissionDenied:
        discard client.sendMessage(update.message.chat.id,
          "You are not allowed to use this command.")
      of dkCooldownActive:
        discard client.sendMessage(update.message.chat.id,
          "Try again in " & $outcome.retryAfterSeconds & " seconds.")
      else:
        discard

    pollForever(botClient, handleUpdate, appConfig.polling)
  except CatchableError as error:
    error "fatal startup error: " & error.msg
    quit(1)
  finally:
    warningService.close()
    botClient.close()
