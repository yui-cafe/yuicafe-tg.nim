## Command parsing, dispatch, permissions, and cooldowns.
import std/[options, sets, strutils, tables, times]

import yuicafe_tg/[client, types]

type
  ## Access policy applied before a command handler runs.
  CommandPermission* = enum
    ## Allows the command in every supported chat.
    cpAnyone,
    ## Allows the command only in one-to-one chats.
    cpPrivateChat,
    ## Allows the command only in group and supergroup chats.
    cpGroupChat,
    ## Allows the command only for a configured owner ID.
    cpOwner,
    ## Allows the command only for an administrator of a group or supergroup.
    cpChatAdmin

  ## A command token and its arguments parsed from a message.
  ParsedCommand* = object
    name*: string
    targetBot*: string
    arguments*: seq[string]
    rawArguments*: string

  ## Data passed to command checks and handlers.
  CommandContext* = object
    client*: BotClient
    update*: Update
    parsed*: ParsedCommand

  ## Additional authorization applied after the command permission check.
  CommandCheck* = proc(context: CommandContext): bool
  ## Function that implements a command.
  CommandHandler* = proc(context: CommandContext)

  ## A registered command and its dispatch policy.
  Command* = ref object
    name*: string
    aliases*: seq[string]
    description*: string
    cooldownSeconds*: int
    permission*: CommandPermission
    check*: CommandCheck
    handler*: CommandHandler

  ## The outcome of dispatching a message to the command router.
  DispatchKind* = enum
    ## The update did not contain a command for this router.
    dkIgnored,
    ## The command was valid but has not been registered.
    dkUnknownCommand,
    ## The sender did not meet the command's access policy.
    dkPermissionDenied,
    ## The sender must wait before invoking the command again.
    dkCooldownActive,
    ## The command handler completed successfully.
    dkExecuted

  ## Details of a command-dispatch attempt.
  DispatchResult* = object
    kind*: DispatchKind
    parsed*: ParsedCommand
    command*: Command
    retryAfterSeconds*: int

  CooldownKey = tuple[commandName: string, senderId: int64]

  ## Registry and dispatcher for message commands.
  CommandRouter* = ref object
    commands: Table[string, Command]
    registered: seq[Command]
    ownerIds: HashSet[int64]
    cooldowns: Table[CooldownKey, int64]
    botUsername*: string
    dispatchCount: uint

proc normaliseCommandName(value: string): string =
  result = value.strip().toLowerAscii()
  if result.len == 0:
    return ""
  for character in result:
    if character notin {'a' .. 'z', '0' .. '9', '_'}:
      return ""

proc parseArguments(raw: string): seq[string] =
  var current = ""
  var quote = '\0'
  var escaped = false
  var started = false

  for character in raw:
    if escaped:
      current.add(character)
      escaped = false
      started = true
    elif character == '\\':
      escaped = true
      started = true
    elif quote != '\0':
      if character == quote:
        quote = '\0'
      else:
        current.add(character)
      started = true
    elif character == '"' or character == '\'':
      quote = character
      started = true
    elif character.isSpaceAscii():
      if started:
        result.add(current)
        current.setLen(0)
        started = false
    else:
      current.add(character)
      started = true

  if escaped:
    current.add('\\')
  if started:
    result.add(current)

proc parseCommand*(text: string): Option[ParsedCommand] =
  ## Parses a slash command, optional bot mention, and shell-like arguments.
  ##
  ## Returns `none` when `text` is not a valid command token.
  let source = text.strip()
  if source.len < 2 or source[0] != '/':
    return none(ParsedCommand)

  var tokenEnd = 1
  while tokenEnd < source.len and not source[tokenEnd].isSpaceAscii():
    inc tokenEnd
  let token = source[1 ..< tokenEnd]
  let mentionStart = token.find('@')

  var name = token
  var targetBot = ""
  if mentionStart >= 0:
    name = token[0 ..< mentionStart]
    targetBot = token[mentionStart + 1 .. ^1].toLowerAscii()
    if targetBot.len == 0 or targetBot.find('@') >= 0:
      return none(ParsedCommand)

  name = normaliseCommandName(name)
  if name.len == 0:
    return none(ParsedCommand)

  let rawArguments =
    if tokenEnd < source.len: source[tokenEnd .. ^1].strip()
    else: ""
  some(ParsedCommand(
    name: name,
    targetBot: targetBot,
    arguments: parseArguments(rawArguments),
    rawArguments: rawArguments
  ))

proc defineCommand*(name, description: string; handler: CommandHandler;
    aliases: openArray[string] = []; cooldownSeconds = 0;
    permission = cpAnyone; check: CommandCheck = nil): Command =
  ## Creates a validated command definition.
  ##
  ## Command names and aliases use lowercase letters, digits, and underscores.
  ## `check`, when present, runs after the built-in `permission` check.
  if handler.isNil:
    raise newException(ValueError, "command handler is required")
  if cooldownSeconds < 0:
    raise newException(ValueError, "command cooldown cannot be negative")

  let normalisedName = normaliseCommandName(name)
  if normalisedName.len == 0:
    raise newException(ValueError,
      "command names may contain only lowercase letters, numbers, and underscores")

  result = Command(
    name: normalisedName,
    description: description,
    cooldownSeconds: cooldownSeconds,
    permission: permission,
    check: check,
    handler: handler
  )
  for alias in aliases:
    let normalisedAlias = normaliseCommandName(alias)
    if normalisedAlias.len == 0:
      raise newException(ValueError, "command alias is invalid")
    if normalisedAlias != result.name and normalisedAlias notin result.aliases:
      result.aliases.add(normalisedAlias)

proc newCommandRouter*(botUsername = "";
    ownerIds: openArray[int64] = []): CommandRouter =
  ## Creates a router for `botUsername` with the supplied owner IDs.
  ##
  ## A router without a bot username ignores every explicitly addressed command,
  ## such as `/help@my_bot`.
  new(result)
  result.botUsername = botUsername.strip(chars = {'@'}).toLowerAscii()
  result.commands = initTable[string, Command]()
  result.ownerIds = initHashSet[int64]()
  result.cooldowns = initTable[CooldownKey, int64]()
  for ownerId in ownerIds:
    result.ownerIds.incl(ownerId)

proc register*(router: CommandRouter; command: Command) =
  ## Registers `command` and all of its aliases.
  ##
  ## Raises `ValueError` when a command name or alias is already registered.
  if command.isNil:
    raise newException(ValueError, "cannot register a nil command")

  var keys = @[command.name]
  keys.add(command.aliases)
  for key in keys:
    if router.commands.hasKey(key):
      raise newException(ValueError, "command or alias already registered: " & key)

  for key in keys:
    router.commands[key] = command
  router.registered.add(command)

proc menuCommands*(router: CommandRouter): seq[BotCommand] =
  ## Commands suitable for Telegram's global default menu. Restricted commands
  ## need a scope-specific menu and are intentionally excluded.
  for command in router.registered:
    if command.permission == cpAnyone and command.description.len > 0:
      result.add(BotCommand(
        command: command.name,
        description: command.description
      ))

proc reply*(context: CommandContext; text: string): Message =
  ## Sends `text` to the chat that supplied the command.
  context.client.sendMessage(context.update.message.chat.id, text)

proc isChatAdministrator(context: CommandContext): bool =
  let message = context.update.message
  if not message.hasFrom or context.client.isNil or
      message.chat.kind notin ["group", "supergroup"]:
    return false
  try:
    return context.client.getChatMember(message.chat.id,
      message.sender.id).isAdministrator
  except TelegramError as error:
    if error.isRetryable:
      raise
    return false

proc isAllowed(router: CommandRouter; command: Command;
    context: CommandContext): bool =
  let message = context.update.message
  result =
    case command.permission
    of cpAnyone:
      true
    of cpPrivateChat:
      message.chat.kind == "private"
    of cpGroupChat:
      message.chat.kind == "group" or message.chat.kind == "supergroup"
    of cpOwner:
      message.hasFrom and message.sender.id in router.ownerIds
    of cpChatAdmin:
      context.isChatAdministrator

  if result and not command.check.isNil:
    result = command.check(context)

proc pruneCooldowns(router: CommandRouter; now: int64) =
  if router.dispatchCount mod 1_024 != 0:
    return
  var expired: seq[CooldownKey]
  for key, deadline in router.cooldowns.pairs:
    if deadline <= now:
      expired.add(key)
  for key in expired:
    router.cooldowns.del(key)

proc dispatch*(router: CommandRouter; client: BotClient;
    update: Update): DispatchResult =
  ## Dispatches a supported message update and returns its outcome.
  ##
  ## Cooldowns are per command and sender, and are recorded only after the
  ## handler returns successfully.
  if not update.hasMessage or not update.message.hasText:
    return DispatchResult(kind: dkIgnored)

  let parsedOption = parseCommand(update.message.text)
  if parsedOption.isNone:
    return DispatchResult(kind: dkIgnored)

  let parsed = parsedOption.get()
  if parsed.targetBot.len > 0 and
      (router.botUsername.len == 0 or parsed.targetBot != router.botUsername):
    return DispatchResult(kind: dkIgnored, parsed: parsed)
  if not router.commands.hasKey(parsed.name):
    return DispatchResult(kind: dkUnknownCommand, parsed: parsed)

  let command = router.commands[parsed.name]
  let context = CommandContext(client: client, update: update, parsed: parsed)
  if not router.isAllowed(command, context):
    return DispatchResult(kind: dkPermissionDenied, parsed: parsed,
        command: command)

  let now = int64(epochTime())
  inc router.dispatchCount
  router.pruneCooldowns(now)
  let senderId =
    if update.message.hasFrom: update.message.sender.id
    else: update.message.chat.id
  let cooldownKey = (command.name, senderId)
  if command.cooldownSeconds > 0 and router.cooldowns.hasKey(cooldownKey):
    let deadline = router.cooldowns[cooldownKey]
    if deadline > now:
      return DispatchResult(
        kind: dkCooldownActive,
        parsed: parsed,
        command: command,
        retryAfterSeconds: int(deadline - now)
      )

  command.handler(context)
  if command.cooldownSeconds > 0:
    router.cooldowns[cooldownKey] =
      int64(epochTime()) + int64(command.cooldownSeconds)
  DispatchResult(kind: dkExecuted, parsed: parsed, command: command)

proc helpText*(router: CommandRouter): string =
  ## Formats the registered commands and descriptions for a help response.
  var lines: seq[string]
  for command in router.registered:
    if command.description.len > 0:
      lines.add("/" & command.name & " - " & command.description)
  lines.join("\n")
