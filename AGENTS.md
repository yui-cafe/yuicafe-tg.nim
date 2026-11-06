# Repository Guidelines

yuicafe-tg is a Nim Telegram Bot API library and bot utility. The package
exports its public API from `src/yuicafe.nim` and includes a long-polling
runtime.
Preserve the library/runtime boundary when making changes.

## Project Structure

*   `src/yuicafe.nim`: executable entrypoint for the bundled application.
*   `src/yuicafe_tg.nim`: public facade for the reusable Telegram library.
*   `src/yuicafe_tg/`: client, Telegram configuration values, polling, and
    Telegram types.
*   `src/yuicafe_app/`: application configuration and startup composition.
*   `src/yuicafe_app/commands/`: command router plus one module per command.
*   `src/yuicafe_app/services/`: application persistence and other services.
*   `src/yuicafe_app/models/`: application data models.
*   `tests/test_<subject>.nim`: focused Nim unit tests.
*   `.env.example`: deployment configuration reference. Never commit `.env`.

Put a new command in `src/yuicafe_app/commands/<command>.nim` and register it
in `commands/defaults.nim`. Keep parser, permission, and cooldown logic in
`commands/router.nim`. Put database access in a service, not a command handler.

## Build and Test

Use Nim 2.2.12 or later and Nimble:

```sh
nimpretty src/yuicafe.nim src/yuicafe_tg.nim src/yuicafe_tg/*.nim \
  src/yuicafe_app/*.nim src/yuicafe_app/commands/*.nim \
  src/yuicafe_app/models/*.nim src/yuicafe_app/services/*.nim tests/*.nim
nimble test
nimble build
export TELEGRAM_BOT_TOKEN='...'
nimble run
```

`nimble test` discovers and runs the test binaries. `nimble build` compiles the
runtime with TLS enabled by the package configuration. Do not use a real bot
token while testing.

## Nim Style

Use `lower_snake_case.nim` paths, two-space indentation, and `nimpretty` for
modified Nim files. Put standard-library imports before yuicafe-tg imports.
Export only intentional library API with `*`; add a case to
`tests/test_public_api.nim` when changing symbols available through
`import yuicafe_tg`.

Prefer value `object` types for decoded API data. Use `ref object` only for
shared mutable state such as `BotClient` or `CommandRouter`. Keep handlers
synchronous unless shared state is made concurrency-safe.

## Testing and Safety

Tests must be deterministic and offline. Use JSON fixtures and in-memory
handlers, not Telegram network calls. Test command parsing, permissions, and
cooldowns when changing command behavior.

Never log or commit `TELEGRAM_BOT_TOKEN`. Handlers must be idempotent because
polling is at-least-once. Do not retry ambiguous write operations such as
`sendMessage`; preserve the existing client retry policy.

## Commits and Pull Requests

No Git history is available in this workspace to infer conventions. Use concise
imperative Conventional Commit messages, for example `feat: add profile
command` or `fix: reject empty command descriptions`. Keep pull requests
focused, explain behavior and configuration changes, link relevant issues, and
include test results. Add screenshots only for user-visible visual changes.

## Documentation

Follow the
[Google Markdown style guide](https://google.github.io/styleguide/docguide/style.html):
use one H1 heading, ATX headings, fenced code blocks with language tags, and
prose wrapped near 80 columns. Use `[TOC]` only where the documentation
renderer supports it; this repository does not declare that support.
