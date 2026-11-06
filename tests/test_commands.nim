# Command parser and router behavior.
import std/[json, options, os, unittest]

import yuicafe_app/[commands/ban, commands/defaults, commands/me,
  commands/router, commands/warn, config]
import yuicafe_app/models/warning
import yuicafe_app/services/warning_service
import yuicafe_tg/types

suite "Telegram response decoders":
  test "decode a text message update":
    let update = decodeUpdate(parseJson("""
      {
        "update_id": 42,
        "message": {
        "message_id": 7,
        "text": "/start",
        "from": {"id": 19, "is_bot": false, "first_name": "Yui"},
        "reply_to_message": {
          "message_id": 6,
          "from": {"id": 20, "is_bot": false, "first_name": "Cafe"}
        },
        "chat": {"id": 900719925474, "type": "private", "username": "yui"}
        }
      }
    """))

    check update.id == 42
    check update.hasMessage
    check update.message.id == 7
    check update.message.hasText
    check update.message.text == "/start"
    check update.message.hasFrom
    check update.message.sender.id == 19
    check update.message.hasReplyToSender
    check update.message.replyToSender.id == 20
    check update.message.chat.id == 900719925474'i64

  test "decode chat administrator status":
    let administrator = decodeChatMember(parseJson("""
      {
        "status": "administrator",
        "user": {"id": 19, "is_bot": false, "first_name": "Yui"}
      }
    """))
    let owner = decodeChatMember(parseJson("""
      {
        "status": "creator",
        "user": {"id": 20, "is_bot": false, "first_name": "Cafe"}
      }
    """))
    let member = decodeChatMember(parseJson("""
      {
        "status": "member",
        "user": {"id": 21, "is_bot": false, "first_name": "Mio"}
      }
    """))

    check administrator.isAdministrator
    check owner.isAdministrator
    check not member.isAdministrator

  test "preserve unsupported update payload":
    let update = decodeUpdate(parseJson("""{"update_id": 3, "callback_query": {}}"""))
    check not update.hasMessage
    check update.raw.hasKey("callback_query")

suite "Command router":
  test "parse target bot and quoted arguments":
    let parsed = parseCommand("""/echo@YuiBot "two words" plain\ value""")
    check parsed.isSome
    check parsed.get.name == "echo"
    check parsed.get.targetBot == "yuibot"
    check parsed.get.arguments == @["two words", "plain value"]

  test "enforce owner permission and per-sender cooldown":
    var calls = 0
    let router = newCommandRouter("yuibot", [7'i64])
    router.register(defineCommand(
      "status",
      "owner command",
      (proc(context: CommandContext) =
        inc calls),
      cooldownSeconds = 10,
      permission = cpOwner
    ))

    let ownerUpdate = Update(
      hasMessage: true,
      message: Message(
        hasText: true,
        text: "/status@yuibot",
        hasFrom: true,
        sender: User(id: 7),
        chat: Chat(id: 77, kind: "private")
      )
    )
    let otherUpdate = Update(
      hasMessage: true,
      message: Message(
        hasText: true,
        text: "/status",
        hasFrom: true,
        sender: User(id: 8),
        chat: Chat(id: 88, kind: "private")
      )
    )

    check router.dispatch(nil, otherUpdate).kind == dkPermissionDenied
    check router.dispatch(nil, ownerUpdate).kind == dkExecuted
    check calls == 1
    check router.dispatch(nil, ownerUpdate).kind == dkCooldownActive
    check calls == 1

  test "require a Telegram chat administrator for moderation":
    let router = newCommandRouter()
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()
    router.registerBanCommand(service)
    let groupUpdate = Update(
      hasMessage: true,
      message: Message(
        hasText: true,
        text: "/ban",
        hasFrom: true,
        sender: User(id: 7),
        chat: Chat(id: -100, kind: "supergroup")
      )
    )

    check router.dispatch(nil, groupUpdate).kind == dkPermissionDenied

  test "format permanent ban failures without API details":
    check banFailureResponse() ==
      "I could not ban that member. Check my permissions and the member's role."

  test "parse permanent and temporary ban durations":
    check parseBanDuration([]).get == 0
    check parseBanDuration(["31s"]).get == 31
    check parseBanDuration(["2H"]).get == 7_200
    check parseBanDuration(["1w"]).get == 604_800
    check parseBanDuration(["366d"]).isSome
    check parseBanDuration(["30s"]).isNone
    check parseBanDuration(["29s"]).isNone
    check parseBanDuration(["367d"]).isNone
    check parseBanDuration(["0m"]).isNone
    check parseBanDuration(["60"]).isNone
    check parseBanDuration(["1h", "extra"]).isNone
    check supportsTemporaryBans("supergroup")
    check not supportsTemporaryBans("group")
    check temporaryBanUnavailableResponse() ==
      "Temporary bans are available only in supergroups."

  test "format sender IDs for the me command":
    check senderIdResponse(Message(hasFrom: true, sender: User(id: 19))) == "19"
    check senderIdResponse(Message()) == "This message does not have a sender ID."

  test "persist reply warnings once per update":
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()
    let message = Message(
      hasReplyToSender: true,
      replyToSender: User(id: 19, username: "yui")
    )
    let warning = parseReplyWarning(message, ["keep", "it", "friendly"])
    let otherWarning = Warning(
      target: WarningTarget(userId: 20, username: "mio"),
      reason: "follow the rules"
    )
    check warning.isSome
    check warning.get.target.userId == 19
    check warning.get.target.username == "yui"
    check warning.get.reason == "keep it friendly"
    check service.record(42, warning.get)
    check not service.record(42, warning.get)
    check service.record(43, otherWarning)
    check service.warningsFor(WarningTarget(userId: 19)) ==
      @["keep it friendly"]
    check warningsResponse(
      WarningTarget(userId: 19, username: "yui"),
      service.warningsFor(WarningTarget(userId: 19))) ==
        "Warnings for @yui:\n1. keep it friendly"
    check parseReplyWarning(Message(), ["@yuicafe", "reason"]).isNone
    expect ValueError:
      discard service.record(44, Warning(
        target: WarningTarget(username: "yuicafe"),
        reason: "not allowed"
      ))

  test "load persisted warnings after reopening the database":
    let databasePath = getTempDir() / "yuicafe-warnings-test.sqlite3"
    if fileExists(databasePath):
      removeFile(databasePath)
    defer:
      if fileExists(databasePath):
        removeFile(databasePath)

    let warning = Warning(
      target: WarningTarget(userId: 19, username: "yui"),
      reason: "keep it friendly"
    )
    let database = DatabaseConfig(path: databasePath)
    let initialService = newWarningService(database)
    check initialService.record(44, warning)
    initialService.close()

    let reopenedService = newWarningService(database)
    defer:
      reopenedService.close()
    check reopenedService.warningsFor(
      WarningTarget(userId: 19, username: "yui")) == @["keep it friendly"]

  test "record warnings from replied-to messages":
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()
    let message = Message(
      hasReplyToSender: true,
      replyToSender: User(id: 19, username: "yui")
    )
    let warning = parseReplyWarning(message, ["be", "kind"])
    check warning.isSome
    check warning.get.target.userId == 19
    check warning.get.target.username == "yui"
    check service.record(43, warning.get)
    check service.warningsFor(WarningTarget(userId: 19)) == @["be kind"]

  test "deduplicate successful bans by update ID":
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()

    check not service.banRecorded(43)
    check service.recordBan(43)
    check service.banRecorded(43)
    check not service.recordBan(43)
    expect ValueError:
      discard service.recordBan(0)

  test "isolate warnings for members without usernames":
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()
    let firstWarning = Warning(
      target: WarningTarget(userId: 19),
      reason: "be kind"
    )
    let secondWarning = Warning(
      target: WarningTarget(userId: 20),
      reason: "follow the rules"
    )

    check service.record(44, firstWarning)
    check service.record(45, secondWarning)
    check service.warningsFor(WarningTarget(userId: 19)) == @["be kind"]

  test "limit warnings to chat administrators":
    let router = newCommandRouter("yuibot")
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()
    router.registerWarnCommand(service)
    let privateUpdate = Update(
      hasMessage: true,
      message: Message(
        hasText: true,
        text: "/warn @yuicafe test",
        hasFrom: true,
        sender: User(id: 7),
        chat: Chat(id: 7, kind: "private")
      )
    )
    let groupUpdate = Update(
      hasMessage: true,
      message: Message(
        hasText: true,
        text: "/warn @yuicafe test",
        hasFrom: true,
        sender: User(id: 8),
        chat: Chat(id: -100, kind: "supergroup")
      )
    )

    check router.dispatch(nil, privateUpdate).kind == dkPermissionDenied
    check router.dispatch(nil, groupUpdate).kind == dkPermissionDenied

  test "publish the warns command in the default menu":
    let router = newCommandRouter()
    let service = newWarningService(DatabaseConfig(path: ":memory:"))
    defer:
      service.close()
    router.registerDefaultCommands(service)

    let commands = router.menuCommands()
    var hasWarns = false
    for command in commands:
      if command.command == "warns":
        hasWarns = true
    check hasWarns

  test "publish only public commands in the default menu":
    let router = newCommandRouter()
    router.register(defineCommand(
      "about",
      "show bot information",
      proc(context: CommandContext) =
      discard,
      permission = cpAnyone
    ))
    router.register(defineCommand(
      "status",
      "show bot status",
      proc(context: CommandContext) =
      discard,
      permission = cpOwner
    ))

    let commands = router.menuCommands()
    check commands.len == 1
    check commands[0].command == "about"
    check commands[0].description == "show bot information"
