import yuicafe/commands/router

proc registerStatusCommand*(router: CommandRouter) =
  router.register(defineCommand(
    "status",
    "show bot status (owners only)",
    proc(context: CommandContext) =
    discard context.reply("yuicafe-tg is online."),
    cooldownSeconds = 5,
    permission = cpOwner
  ))
