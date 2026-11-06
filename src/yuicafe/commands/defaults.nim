import yuicafe/commands/[help, me, router, start, status]

proc registerDefaultCommands*(router: CommandRouter) =
  router.registerStartCommand()
  router.registerHelpCommand()
  router.registerMeCommand()
  router.registerStatusCommand()
