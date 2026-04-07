---
name: apple-calendar
description: Work with Apple Calendar on macOS using the local `calctl` CLI from this repository. Use when the user wants to view calendars, inspect agenda/date ranges, search events, create events, update events, delete events, or check Calendar permissions/state on a Mac with Calendar.app data available through EventKit.
---

# Apple Calendar

Use `calctl` as the single interface for Apple Calendar work in this repo.

## Quick start

Resolve the repo root as the parent of `skills/` and run `calctl` from there.

Preferred invocation:

```bash
swift run --package-path <repo-root> calctl <command> ...
```

Examples:

```bash
swift run --package-path <repo-root> calctl doctor --json
swift run --package-path <repo-root> calctl calendars --json
swift run --package-path <repo-root> calctl agenda --today --json --limit 10
swift run --package-path <repo-root> calctl search dentist --from 2026-04-01 --to 2026-05-01 --json
```

If `calctl` is already installed in `PATH`, direct invocation is fine.

## Workflow

### 1. Check health first when unsure

Run:

```bash
swift run --package-path <repo-root> calctl doctor --json
```

Use this to confirm:
- Calendar authorization state
- backend health
- visible calendars
- writable vs read-only calendars

If authorization is not granted yet, request it with:

```bash
swift run --package-path <repo-root> calctl doctor --request-access --json
```

### 2. Discover calendars before mutating

Run:

```bash
swift run --package-path <repo-root> calctl calendars --json
```

Prefer `--calendar-id` over `--calendar` for reliable automation when a calendar has already been identified.

### 3. Prefer read operations first

For agenda/date-range work:

```bash
swift run --package-path <repo-root> calctl agenda --today --json --limit 20
swift run --package-path <repo-root> calctl agenda --week --json --limit 50
swift run --package-path <repo-root> calctl agenda --from 2026-04-06 --to 2026-04-13 --json
```

For search:

```bash
swift run --package-path <repo-root> calctl search kickoff --json --limit 20
swift run --package-path <repo-root> calctl search dentist --from 2026-04-01 --to 2026-05-01 --json
```

Use detail flags only when needed:

```bash
--details
--include-location
--include-notes
--include-url
```

Default JSON is intentionally slimmer for automation.

## Mutation rules

### Always use `--dry-run` first

Before `add`, `update`, or `delete`, preview the exact target/result.

Examples:

```bash
swift run --package-path <repo-root> calctl add --calendar-id <id> --title "Call" --start "2026-04-08 15:00" --end "2026-04-08 15:30" --dry-run --json

swift run --package-path <repo-root> calctl update --id <event-id> --title "Updated title" --dry-run --json

swift run --package-path <repo-root> calctl delete --id <event-id> --dry-run --json
```

Only run the real mutation after the preview looks correct.

### Create events

```bash
swift run --package-path <repo-root> calctl add \
  --calendar-id <calendar-id> \
  --title "Project review" \
  --start "2026-04-08 15:00" \
  --end "2026-04-08 16:00" \
  --location "Office" \
  --notes "Bring agenda" \
  --dry-run --json
```

All-day event:

```bash
swift run --package-path <repo-root> calctl add \
  --calendar-id <calendar-id> \
  --title "Holiday" \
  --start "2026-04-12" \
  --all-day \
  --dry-run --json
```

### Update events

```bash
swift run --package-path <repo-root> calctl update \
  --id <event-id> \
  --start "2026-04-08 16:00" \
  --end "2026-04-08 17:00" \
  --dry-run --json
```

Clear fields explicitly when needed:

```bash
--clear-location
--clear-notes
--clear-url
```

### Delete events

```bash
swift run --package-path <repo-root> calctl delete --id <event-id> --dry-run --json
```

## Recurring event safety

For recurring events, `update` and `delete` require an explicit scope:

```bash
--this-event
--this-and-future
--entire-series
```

If the event is recurring and no scope is provided, `calctl` should fail rather than guess.

Use `--dry-run` before any recurring-event mutation.

## Practical defaults

- Use `--json` for automation.
- Use `--limit` to avoid excessive output.
- Prefer `--calendar-id` after the calendar has been discovered.
- Use read commands before write commands when context is incomplete.
- For destructive actions like delete, confirm intent if the request is ambiguous.
- Do not expose optional fields like notes/URL unless needed.

## When to clarify

Clarify if the user means a reminder/task rather than a calendar event.

Examples:
- “remind me to…” may belong in Apple Reminders or a chat reminder, not Calendar
- vague destructive requests like “delete that meeting” need target confirmation if the event ID is not already known
- ambiguous calendar selection should be resolved with `calctl calendars --json`

## Minimal command set

```bash
calctl doctor [--request-access] [--json]
calctl calendars [--json]
calctl agenda [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME|--calendar-id ID] [--limit N] [--details|--include-location|--include-notes|--include-url] [--json]
calctl search QUERY [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME|--calendar-id ID] [--limit N] [--details|--include-location|--include-notes|--include-url] [--json]
calctl add --calendar NAME|--calendar-id ID --title TITLE --start VALUE [--end VALUE] [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
calctl update --id EVENT_ID [--calendar NAME|--calendar-id ID] [--title TITLE] [--start VALUE] [--end VALUE] [--location VALUE] [--notes VALUE] [--url VALUE] [--clear-location] [--clear-notes] [--clear-url] [--all-day|--timed] [--this-event|--this-and-future|--entire-series] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
calctl delete --id EVENT_ID [--this-event|--this-and-future|--entire-series] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
```
