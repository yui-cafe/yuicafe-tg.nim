## Public API and executable entry point for yuicafe-tg.
##
## Import this module to access the supported client, configuration, polling,
## Telegram types, and command-router APIs. The command modules are part of the
## bundled executable and are not registered for library consumers.
import yuicafe/[client, config, polling, types]
import yuicafe/commands/router

export client, config, polling, router, types

when isMainModule:
  import std/logging
  import yuicafe/commands/defaults

  addHandler(newConsoleLogger())
  var botClient: BotClient

  try:
    let appConfig = loadConfig()
    botClient = newBotClient(appConfig.bot)
    let bot = botClient.getMe()
    info "authenticated as @" & bot.username
    let router = newCommandRouter(bot.username, appConfig.ownerIds)
    router.registerDefaultCommands()
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
    botClient.close()
