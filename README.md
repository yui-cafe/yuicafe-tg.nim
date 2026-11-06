# yuicafe-tg

`yuicafe-tg` is a Nim library and utility for Telegram bots. It provides a
typed Bot API client, long polling, Telegram payload decoders, and an
extensible command router. The bundled `yuicafe` executable includes `/start`,
`/help`, `/me`, and `/status` commands.

`yuicafe-tg` is maintained by [Yui Cafe][yui-cafe].

## Features

*   Typed value objects for supported Telegram updates, messages, users, and
    chats.
*   JSON-over-HTTPS Bot API client with bounded retries for retry-safe calls.
*   At-least-once long polling with explicit webhook handling.
*   Command parsing with bot mentions, aliases, quoted arguments, permissions,
    custom authorization, and per-sender cooldowns.
*   A small public facade: applications import `yuicafe`, not internal modules.

## Requirements

*   Nim 2.2.12 or later.
*   Nimble.
*   A Telegram bot token stored in `TELEGRAM_BOT_TOKEN`.

The repository is named `yuicafe-tg.nim`. Nimble package names cannot contain
hyphens, so the package is `yuicafe_tg`; its executable remains `yuicafe`.

## Install

Install the package from GitHub:

```sh
nimble install https://github.com/yui-cafe/yuicafe-tg.nim
```

To run or contribute to a checkout:

```sh
git clone https://github.com/yui-cafe/yuicafe-tg.nim.git
cd yuicafe-tg.nim
nimble build
```

## Quick start

Import `yuicafe` to use the supported library API. The example below registers
a command, starts long polling, and closes the client when polling stops.

```nim
import yuicafe

proc main() =
  let app_config = loadConfig()
  let client = newBotClient(app_config.bot)
  defer:
    client.close()

  let bot = client.getMe()
  let router = newCommandRouter(bot.username, app_config.ownerIds)
  router.register(defineCommand(
    "hello",
    "send a greeting",
    proc(context: CommandContext) =
      discard context.reply("Hello!")
  ))

  proc handle_update(client: BotClient; update: Update) =
    discard router.dispatch(client, update)

  pollForever(client, handle_update, app_config.polling)

main()
```

`pollForever` returns after an interrupt signal or `requestStop()`. A poller
can deliver an update more than once, so handlers must make external side
effects idempotent.

The root module is the stable public facade. Import modules below
`yuicafe/commands/` only when extending the bundled command implementation.
Application command modules are not registered automatically.

## Run the bundled bot

The executable reads its token only from the environment. Never commit a real
token.

```sh
export TELEGRAM_BOT_TOKEN='123456789:replace-with-your-token'
nimble run
```

Use [.env.example](.env.example) as a reference when configuring a shell or
secret manager. The application does not load a `.env` file itself.

## Configuration

`TELEGRAM_BOT_TOKEN` is required. All other variables are optional.

| Variable | Default | Description |
| --- | --- | --- |
| `TELEGRAM_API_BASE_URL` | `https://api.telegram.org` | Bot API endpoint. |
| `TELEGRAM_POLL_TIMEOUT_SECONDS` | `30` | Long-poll wait time, from 1 to 50 seconds. |
| `TELEGRAM_POLL_LIMIT` | `100` | Maximum updates returned per request, from 1 to 100. |
| `TELEGRAM_ALLOWED_UPDATES` | Unset | Comma-separated update types. Unset preserves Telegram's server-side setting. |
| `TELEGRAM_REQUEST_TIMEOUT_MS` | Poll timeout plus 10 seconds | HTTP timeout, from 1,000 to 120,000 ms. |
| `TELEGRAM_MAX_RETRIES` | `3` | Retries for retry-safe calls, from 0 to 10. |
| `TELEGRAM_RETRY_BASE_DELAY_MS` | `500` | Initial API retry delay, from 50 to 60,000 ms. |
| `TELEGRAM_RETRY_MAX_DELAY_MS` | `30000` | Maximum API retry delay, from 100 to 300,000 ms. |
| `TELEGRAM_FAILURE_DELAY_MS` | `1000` | Initial poller failure delay, from 100 to 60,000 ms. |
| `TELEGRAM_FAILURE_MAX_DELAY_MS` | `30000` | Maximum poller failure delay, from 100 to 300,000 ms. |
| `TELEGRAM_OWNER_IDS` | Unset | Comma-separated user IDs for owner-only commands. |
| `TELEGRAM_DELETE_WEBHOOK` | `false` | Delete the active webhook before long polling. |

## Commands

For the bundled runtime, put a command module in `src/yuicafe/commands/` and
register it from `src/yuicafe/commands/defaults.nim`.

```nim
router.register(defineCommand(
  "status",
  "show bot status (owners only)",
  proc(context: CommandContext) =
    discard context.reply("yuicafe-tg is online."),
  cooldownSeconds = 5,
  permission = cpOwner
))
```

The parser accepts `/status`, `/status@YourBot`, aliases, quoted arguments,
and escaped spaces. Built-in permissions are `cpAnyone`, `cpPrivateChat`,
`cpGroupChat`, and `cpOwner`. Pass a `check` procedure to add
application-specific authorization.

Cooldowns are per command and sender. They are recorded only after a handler
returns successfully. The bundled runtime synchronizes public commands with
Telegram's global command menu at startup; restricted commands are excluded.

## Reliability and security

By default, the client uses JSON over HTTPS and honors Telegram's `retry_after`
hint. It does not retry `sendMessage`, because an ambiguous transport failure
could otherwise create duplicate messages.

Telegram does not deliver `getUpdates` while a webhook is active. The bundled
runtime treats an active webhook as a startup error. Set
`TELEGRAM_DELETE_WEBHOOK=true` only when intentionally moving to long polling;
pending updates are retained.

## Container image

```sh
docker build -t yuicafe-tg .
docker run --rm -e TELEGRAM_BOT_TOKEN yuicafe-tg
```

The image runs as an unprivileged user and contains only the compiled binary,
CA roots, and TLS runtime libraries.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Run the
following checks locally:

```sh
nimpretty src/yuicafe.nim src/yuicafe/*.nim \
  src/yuicafe/commands/*.nim tests/*.nim
nimble test
nimble build
```

## License

`yuicafe-tg` is licensed under the [MIT License](LICENSE). Copyright © 2026
[Yui Cafe][yui-cafe].

[yui-cafe]: https://github.com/yui-cafe
