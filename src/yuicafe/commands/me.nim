import yuicafe/[commands/router, types]

proc senderIdResponse*(message: Message): string =
  if message.hasFrom:
    $message.sender.id
  else:
    "This message does not have a sender ID."

proc registerMeCommand*(router: CommandRouter) =
  router.register(defineCommand(
    "me",
    "show your Telegram user ID",
    proc(context: CommandContext) =
    discard context.reply(senderIdResponse(context.update.message))
  ))
