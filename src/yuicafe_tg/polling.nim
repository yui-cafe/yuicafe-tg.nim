import std/[atomics, logging, os]

import yuicafe_tg/[client, config, types]

type
  ## Receives one decoded update during long polling.
  ##
  ## A handler must be idempotent because a failed process or handler can cause
  ## Telegram to deliver the update again.
  UpdateHandler* = proc(client: BotClient; update: Update)

var stopRequested: Atomic[bool]

proc requestStop*() =
  ## Requests that the active `pollForever` call stops after its current work.
  stopRequested.store(true)

proc handleInterrupt() {.noconv.} =
  stopRequested.store(true)

proc nextDelay(current, maximum: int): int =
  min(current * 2, maximum)

proc pollForever*(client: BotClient; handler: UpdateHandler;
    config: PollingConfig) =
  ## Processes updates at-least-once. An update is acknowledged only after its
  ## handler completes, so a process crash or handler error can be retried.
  ##
  ## The function returns after `requestStop` or an interrupt signal requests a
  ## graceful stop.
  setControlCHook(handleInterrupt)
  var offset = 0'i64
  var failureDelay = config.failureDelayMs

  while not stopRequested.load():
    try:
      let updates = client.getUpdates(
        offset = offset,
        timeoutSeconds = config.timeoutSeconds,
        limit = config.limit,
        allowedUpdates = config.allowedUpdates
      )
      failureDelay = config.failureDelayMs

      for update in updates:
        if stopRequested.load():
          break
        handler(client, update)
        offset = update.id + 1
    except CatchableError as error:
      error "polling failure: " & error.msg
      sleep(failureDelay)
      failureDelay = nextDelay(failureDelay, config.failureMaxDelayMs)

  info "poller stopped"
