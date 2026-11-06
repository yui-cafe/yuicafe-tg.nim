## Registration for commands bundled with the Yui Cafe application.
import yuicafe_app/commands/[ban, help, me, router, start, status, warn]
import yuicafe_app/services/warning_service

proc registerDefaultCommands*(router: CommandRouter;
    warningService: WarningService) =
  router.registerStartCommand()
  router.registerHelpCommand()
  router.registerMeCommand()
  router.registerStatusCommand()
  router.registerWarnCommand(warningService)
  router.registerWarnsCommand(warningService)
  router.registerBanCommand(warningService)
