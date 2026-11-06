## Warning commands for Yui Cafe moderation.
import std/[options, strutils]

import yuicafe_app/[commands/router, models/warning, services/warning_service]
import yuicafe_tg/types

proc normaliseUsername(value: string): string =
  result = value.strip(chars = {'@'}).toLowerAscii()
  if result.len == 0:
    return ""
  for character in result:
    if character notin {'a' .. 'z', '0' .. '9', '_'}:
      return ""

proc warningUsage*(): string =
  "Usage: reply to a member's message with /warn <reason>"

proc parseReplyWarning*(message: Message;
    arguments: openArray[string]): Option[Warning] =
  ## Parses a warning for the sender of a replied-to message.
  if not message.hasReplyToSender or arguments.len == 0:
    return none(Warning)

  let reason = arguments.join(" ").strip()
  if message.replyToSender.id <= 0 or reason.len == 0:
    return none(Warning)
  some(Warning(
    target: WarningTarget(
      userId: message.replyToSender.id,
      username: normaliseUsername(message.replyToSender.username)
    ),
    reason: reason
  ))

proc warningsResponse*(target: WarningTarget;
    warnings: openArray[string]): string =
  ## Formats a member's warnings for display in the chat.
  if warnings.len == 0:
    return "You have no warnings."

  let label =
    if target.username.len > 0: "@" & target.username
    else: "user " & $target.userId
  result = "Warnings for " & label & ":"
  for index, reason in warnings:
    result.add("\n" & $(index + 1) & ". " & reason)

proc registerWarnCommand*(router: CommandRouter; service: WarningService) =
  ## Registers the chat-administrator-only `/warn` command.
  router.register(defineCommand(
    "warn",
    "warn a replied-to member (admins only)",
    proc(context: CommandContext) =
    let warning = parseReplyWarning(
      context.update.message, context.parsed.arguments)
    if warning.isNone:
      discard context.reply(warningUsage())
    elif service.record(context.update.id, warning.get()):
      let issuedWarning = warning.get()
      let count = service.warningsFor(issuedWarning.target).len
      let label =
        if issuedWarning.target.username.len > 0:
          "@" & issuedWarning.target.username
        else:
          "user " & $issuedWarning.target.userId
      discard context.reply(
        "Warned " & label & " (" & $count & " warning" &
        (if count == 1: "" else: "s") & ")."),
    permission = cpChatAdmin
  ))

proc registerWarnsCommand*(router: CommandRouter; service: WarningService) =
  ## Registers the `/warns` command.
  router.register(defineCommand(
    "warns",
    "show your warnings",
    proc(context: CommandContext) =
    if context.parsed.arguments.len > 0:
      discard context.reply("Usage: /warns")
    elif not context.update.message.hasFrom:
      discard context.reply("This message does not have a sender.")
    else:
      let sender = context.update.message.sender
      let target = WarningTarget(
        userId: sender.id,
        username: normaliseUsername(sender.username)
      )
      discard context.reply(warningsResponse(target, service.warningsFor(
          target))),
    permission = cpAnyone
  ))
