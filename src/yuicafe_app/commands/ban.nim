## Ban command for Yui Cafe moderation.
import std/[options, strutils, times]

import yuicafe_app/[commands/router, services/warning_service]
import yuicafe_tg/[client, types]

const
  minimumTemporaryBanSeconds = 31'i64
  maximumTemporaryBanSeconds = 366'i64 * 24 * 60 * 60

proc banUsage*(): string =
  "Usage: reply with /ban or, in a supergroup, /ban <duration> (for example, /ban 1h)"

proc banFailureResponse*(): string =
  "I could not ban that member. Check my permissions and the member's role."

proc temporaryBanUnavailableResponse*(): string =
  "Temporary bans are available only in supergroups."

proc supportsTemporaryBans*(chatKind: string): bool =
  ## Returns whether Telegram applies a ban expiration in `chatKind`.
  chatKind == "supergroup"

proc parseBanDuration*(arguments: openArray[string]): Option[int64] =
  ## Parses an optional temporary-ban duration.
  ##
  ## Durations use a positive integer and `s`, `m`, `h`, `d`, or `w` suffix.
  ## Telegram treats durations under 30 seconds or over 366 days as permanent.
  ## An extra second avoids sending an expiry at the 30-second boundary.
  if arguments.len == 0:
    return some(0'i64)
  if arguments.len != 1:
    return none(int64)

  let value = arguments[0].toLowerAscii()
  if value.len < 2:
    return none(int64)

  var multiplier = 0'i64
  case value[^1]
  of 's':
    multiplier = 1
  of 'm':
    multiplier = 60
  of 'h':
    multiplier = 60 * 60
  of 'd':
    multiplier = 24 * 60 * 60
  of 'w':
    multiplier = 7 * 24 * 60 * 60
  else:
    return none(int64)

  try:
    let amount = int64(parseBiggestInt(value[0 .. ^2]))
    if amount <= 0 or amount > maximumTemporaryBanSeconds div multiplier:
      return none(int64)
    let seconds = amount * multiplier
    if seconds < minimumTemporaryBanSeconds:
      return none(int64)
    some(seconds)
  except ValueError:
    none(int64)

proc memberLabel(username: string; userId: int64): string =
  if username.len > 0:
    "@" & username
  else:
    "user " & $userId

proc registerBanCommand*(router: CommandRouter; service: WarningService) =
  ## Registers the chat-administrator-only `/ban` command.
  router.register(defineCommand(
    "ban",
    "ban a replied-to member (admins only)",
    proc(context: CommandContext) =
    let message = context.update.message
    let duration = parseBanDuration(context.parsed.arguments)
    if duration.isNone or not message.hasReplyToSender or
        message.replyToSender.id <= 0:
      discard context.reply(banUsage())
    elif duration.get > 0 and not supportsTemporaryBans(message.chat.kind):
      discard context.reply(temporaryBanUnavailableResponse())
    elif service.banRecorded(context.update.id):
      return
    else:
      let member = message.replyToSender
      let untilDate =
        if duration.get == 0: 0'i64
        else: int64(epochTime()) + duration.get
      try:
        context.client.banChatMember(message.chat.id, member.id,
          untilDate = untilDate)
      except TelegramError as error:
        if error.isRetryable:
          raise
        discard context.reply(banFailureResponse())
        return
      if not service.recordBan(context.update.id):
        return
      let response =
        if duration.get == 0:
          "Banned " & memberLabel(member.username, member.id) & "."
        else:
          "Banned " & memberLabel(member.username, member.id) & " for " &
            context.parsed.arguments[0].toLowerAscii() & "."
      discard context.reply(response),
    permission = cpChatAdmin
  ))
