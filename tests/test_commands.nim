# Command parser and router behavior.
import std/[json, options, unittest]

import yuicafe/types
import yuicafe/commands/[me, router]

suite "Telegram response decoders":
  test "decode a text message update":
    let update = decodeUpdate(parseJson("""
      {
        "update_id": 42,
        "message": {
        "message_id": 7,
        "text": "/start",
        "from": {"id": 19, "is_bot": false, "first_name": "Yui"},
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
    check update.message.chat.id == 900719925474'i64

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

  test "format sender IDs for the me command":
    check senderIdResponse(Message(hasFrom: true, sender: User(id: 19))) == "19"
    check senderIdResponse(Message()) == "This message does not have a sender ID."

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
