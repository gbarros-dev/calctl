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
- Calendar selection accepts either `--calendar` for exact title matching or `--calendar-id` for exact identifier matching.
- `search` defaults to a built-in search window of 30 days back through 365 days forward if no range flags are passed.
- `agenda` and `search` accept `--limit N` to cap the sorted result set.
- Event JSON omits `location`, `notes`, and `url` unless `--details` or the corresponding `--include-*` flag is present.
- `add`, `update`, and `delete` accept `--dry-run` to preview the affected event.
- `update` supports `--clear-location`, `--clear-notes`, and `--clear-url`.
- `update` and `delete` require an explicit recurrence scope flag when the targeted event belongs to a recurring series.
- EventKit mutation visibility can lag briefly after save/remove operations.
