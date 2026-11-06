# Contributing to yuicafe-tg

`yuicafe-tg` is a Nim Telegram Bot API library and bot utility. Keep changes
small, explicit, and safe for a long-running process that receives updates at
least once.

## Requirements

Use Nim 2.2.12 or later and Nimble. The project enables TLS through its Nimble
configuration, so use Nimble commands rather than ad hoc compiler invocations
unless the command includes `-d:ssl`.

## Development workflow

1.  Read the affected module and its tests before changing behavior.
1.  Add or update a focused test in `tests/test_<subject>.nim`.
1.  Format modified Nim sources with `nimpretty`.
1.  Run the checks before opening a change:

    ```sh
    nimble test
    nimble build
    ```

Tests must be deterministic and must not call the live Telegram API. Use
decoded JSON fixtures and in-memory command handlers instead.

## Nim code rules

*   Use `lower_snake_case.nim` filenames. Keep one clear responsibility per
    module.
*   Put each command handler in `src/yuicafe/commands/<command>.nim`. Keep
    parsing, dispatch, and shared policy in `commands/router.nim`.
*   Group standard-library imports before yuicafe-tg imports. Remove unused
    imports.
*   Export only intentional public API with `*`. Keep parsing and transport
    helpers private unless callers need to test or compose them.
*   Treat the symbols re-exported by `import yuicafe` as the public library
    surface. Preserve their behavior across compatible releases and add a
    `tests/test_public_api.nim` case when expanding that surface.
*   Prefer `object` values for decoded Telegram payloads. Use `ref object` only
    for shared mutable state or identity, such as `BotClient` and
    `CommandRouter`.
*   Validate environment configuration and command definitions at startup or
    registration time. Raise a specific, actionable error instead of accepting
    invalid state.
*   Keep handlers synchronous. If that changes, make shared router state,
    especially cooldowns, safe for concurrent access.
*   Do not add dependencies for functionality available in the Nim standard
    library without a clear operational benefit.

## Bot safety rules

*   Never log or commit bot tokens. Read them from `TELEGRAM_BOT_TOKEN`.
*   Do not retry non-idempotent Bot API writes such as `sendMessage` after an
    ambiguous transport failure.
*   Command handlers must be idempotent or persist their own idempotency state:
    the poller deliberately provides at-least-once delivery.
*   Advance an update offset only after successful handling. Do not swallow a
    handler exception merely to keep polling.
*   Put authorization in command permissions or the command `check` hook.
    Owner-only commands require IDs configured in `TELEGRAM_OWNER_IDS`.
*   Keep cooldowns per sender unless a command explicitly requires a different
    scope. Record a cooldown only after a handler succeeds.

## Command conventions

*   Use lower-case command names with digits and underscores only.
*   Give each public command a concise description so `/help` remains useful.
*   Use aliases only for stable, unambiguous names.
*   Require a bot mention in group-specific behavior when the command could
    otherwise conflict with another bot.
*   Test parsing, authorization, and cooldown behavior whenever a command rule
    changes.

## Documentation

Update `README.md` when a user-facing command, environment variable, or
deployment behavior changes. Follow the
[Google Markdown style guide](https://google.github.io/styleguide/docguide/style.html):
use one H1 heading, ATX headings, fenced code blocks with language tags, and
prose wrapped near 80 columns. Use `[TOC]` only where the renderer supports it.
