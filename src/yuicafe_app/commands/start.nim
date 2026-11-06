import yuicafe_app/commands/router

proc registerStartCommand*(router: CommandRouter) =
  router.register(defineCommand(
    "start",
    "introduce the bot",
    proc(context: CommandContext) =
    discard context.reply("yuicafe-tg is online. Send /help to see available commands.")
  ))
