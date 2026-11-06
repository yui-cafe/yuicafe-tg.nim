# yuicafe-tg

`yuicafe-tg` has a reusable Telegram library and a Yui Cafe bot application.
The `yuicafe_tg` library provides a typed Bot API client, long polling, and
Telegram payload decoders. The bundled `yuicafe` application includes `/start`,
`/help`, `/me`, `/status`, `/warn`, `/warns`, and `/ban` commands.

`yuicafe-tg` is maintained by [Yui Cafe][yui-cafe].

## Features

*   Typed value objects for supported Telegram updates, messages, users, and
    chats.
*   JSON-over-HTTPS Bot API client with bounded retries for retry-safe calls.
*   At-least-once long polling with explicit webhook handling.
*   An application command router with bot mentions, aliases, quoted arguments,
    permissions, custom authorization, and per-sender cooldowns.
*   A small library facade: Telegram-library users import `yuicafe_tg`, not
    internal modules.

## Requirements

*   Nim 2.2.12 or later.
*   Nimble.
*   SQLite 3.
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

Import `yuicafe_tg` to use the supported library API. The application command
router and environment configuration intentionally remain in `yuicafe_app`.

```nim
import yuicafe_tg

proc main() =
  let bot_config = BotConfig(
    token: "read-from-your-secret-manager",
    apiBaseUrl: "https://api.telegram.org",
    requestTimeoutMs: 40_000,
    maxRetries: 3,
    retryBaseDelayMs: 500,
    retryMaxDelayMs: 30_000
  )
  let polling_config = PollingConfig(
    timeoutSeconds: 30,
    limit: 100,
    failureDelayMs: 1_000,
    failureMaxDelayMs: 30_000
  )
  let client = newBotClient(bot_config)
  defer:
    client.close()

  proc handle_update(client: BotClient; update: Update) =
    if update.hasMessage and update.message.hasText:
      discard client.sendMessage(update.message.chat.id, "Hello!")

  pollForever(client, handle_update, polling_config)

main()
```

`pollForever` returns after an interrupt signal or `requestStop()`. A poller
can deliver an update more than once, so handlers must make external side
effects idempotent.

`yuicafe_tg` is the recommended public facade. `yuicafe` remains available as a
legacy compatibility facade for existing consumers, including its historical
command-router exports. New application code should use modules below
`yuicafe_app/` directly; they are part of the bundled application rather than
the reusable Telegram library.

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
| `TELEGRAM_DATABASE_PATH` | `yuicafe.sqlite3` | SQLite file used for persistent warnings. |
| `TELEGRAM_OWNER_IDS` | Unset | Comma-separated user IDs for owner-only commands such as `/status`. |
| `TELEGRAM_DELETE_WEBHOOK` | `false` | Delete the active webhook before long polling. |

## Commands

For the bundled application, put a command module in
`src/yuicafe_app/commands/` and register it from
`src/yuicafe_app/commands/defaults.nim`. Keep database access in
`src/yuicafe_app/services/` and application data types in
`src/yuicafe_app/models/`. The application loads `TELEGRAM_DATABASE_PATH` into
`AppConfig.database.path`, which is passed to the warning service at startup.

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
`cpGroupChat`, `cpOwner`, and `cpChatAdmin`. Pass a `check` procedure to add
application-specific authorization.

Cooldowns are per command and sender. They are recorded only after a handler
returns successfully. The bundled runtime synchronizes public commands with
Telegram's global command menu at startup; restricted commands are excluded.

### Warnings

Chat administrators can reply to a member's group message with `/warn <reason>`.
They can also reply with `/ban` to permanently remove a member, or with
`/ban <duration>` in a supergroup for a temporary ban. Durations use a positive
integer with an `s`, `m`, `h`, `d`, or `w` suffix and must be from 31 seconds
through 366 days; for example, `/ban 1h`. Telegram always removes a banned
member's earlier messages in supergroups and channels. Members can use `/warns`
in the group or a private chat to view warnings addressed to their Telegram user
ID. Warning records are stored in the configured SQLite database and survive bot
restarts.

The bot must be a chat administrator with permission to restrict members for
`/ban` to succeed.

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
docker run --rm -e TELEGRAM_BOT_TOKEN \
  -v yuicafe-data:/var/lib/yuicafe yuicafe-tg
```

The image runs as an unprivileged user and stores its SQLite database in
`/var/lib/yuicafe`. The named volume in the example preserves warnings when the
container is replaced.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Run the
following checks locally:

```sh
nimpretty src/yuicafe.nim src/yuicafe_tg.nim src/yuicafe_tg/*.nim \
  src/yuicafe_app/*.nim src/yuicafe_app/commands/*.nim \
  src/yuicafe_app/models/*.nim src/yuicafe_app/services/*.nim tests/*.nim
nimble test
nimble build
```

## License

`yuicafe-tg` is licensed under the [MIT License](LICENSE). Copyright © 2026
[Yui Cafe][yui-cafe].

[yui-cafe]: https://github.com/yui-cafe
