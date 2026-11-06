## Legacy public facade and executable entry point for the bundled Yui Cafe bot.
##
## New library consumers should import `yuicafe_tg`. This module preserves the
## public API that was historically available through `import yuicafe`.
import yuicafe_app/commands/router
import yuicafe_tg

export router, yuicafe_tg

when isMainModule:
  import yuicafe_app/main

  run()
