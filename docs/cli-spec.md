# calctl CLI Spec

This is the first concrete cut of the interface from `calctl-plan.md`.

## Implemented now

- `calctl doctor`
- `calctl calendars`
- `calctl agenda`
- `calctl search`
- `calctl add`
- `calctl update`
- `calctl delete`

## Output modes

- `--json` returns stable machine-readable output
- default output is plain text
- `--quiet` suppresses normal stdout

## Agenda selectors

- `--today`
- `--tomorrow`
- `--week`
- `--from YYYY-MM-DD --to YYYY-MM-DD`

If no selector is passed, `agenda` defaults to `--today`.

## Current constraints

- EventKit is the only backend in this initial cut.
- Reads require full calendar access.
- Mutations also currently assume full access.
- `doctor --request-access` is the only command that actively asks macOS for Calendar permission.
- `--calendar` currently matches by exact calendar title.
- `search` defaults to a built-in search window of 30 days back through 365 days forward if no range flags are passed.
- `update` and `delete` currently operate on single event identifiers only.
- EventKit mutation visibility can lag briefly after save/remove operations.
- Recurring-event scope flags are not implemented yet.
