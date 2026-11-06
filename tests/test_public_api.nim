import std/unittest

import yuicafe

suite "Public library facade":
  test "expose the command router":
    let router = newCommandRouter("yuicafe_bot", [42'i64])
    check not router.isNil
    check router.botUsername == "yuicafe_bot"

  test "support custom command registration":
    var calls = 0
    let router = newCommandRouter()
    router.register(defineCommand(
      "ping",
      "check availability",
      proc(context: CommandContext) =
      inc calls
    ))

    let update = Update(
      hasMessage: true,
      message: Message(
        hasText: true,
        text: "/ping",
        hasFrom: true,
        sender: User(id: 42),
        chat: Chat(id: 42, kind: "private")
      )
    )
    check router.dispatch(nil, update).kind == dkExecuted
    check calls == 1
