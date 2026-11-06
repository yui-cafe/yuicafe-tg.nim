import yuicafe/commands/router

proc registerHelpCommand*(router: CommandRouter) =
  router.register(defineCommand(
    "help",
    "show available commands",
    proc(context: CommandContext) =
    discard context.reply(router.helpText())
  ))
