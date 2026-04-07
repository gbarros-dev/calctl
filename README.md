# calctl

`calctl` is a native macOS Calendar CLI built on EventKit.

It is designed for shell automation, assistants, and people who want predictable Calendar access without scripting Calendar.app directly.

Current status: early public prototype.

## Goals

- native macOS backend
- JSON-first output for automation
- human-readable output by default
- predictable command surface
- explicit permission handling

## Current Commands

```bash
calctl doctor [--request-access] [--json]
calctl calendars [--json]
calctl agenda [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME|--calendar-id ID] [--limit N] [--details|--include-location|--include-notes|--include-url] [--json]
calctl search QUERY [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME|--calendar-id ID] [--limit N] [--details|--include-location|--include-notes|--include-url] [--json]
calctl add (--calendar NAME|--calendar-id ID) --title TITLE --start VALUE --end VALUE [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
calctl update --id EVENT_ID [--calendar NAME|--calendar-id ID] [--title TITLE] [--start VALUE] [--end VALUE] [--location VALUE|--clear-location] [--notes VALUE|--clear-notes] [--url VALUE|--clear-url] [--all-day|--timed] [--this-event|--this-and-future|--entire-series] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
calctl delete --id EVENT_ID [--this-event|--this-and-future|--entire-series] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
```

## Quick Start

Build and run locally:

```bash
swift build
swift run calctl doctor --request-access --json
swift run calctl calendars --json
swift run calctl agenda --today --json
swift run calctl search dentist --from 2026-04-01 --to 2026-05-01 --json
```

## Output

`--json` is the stable automation path. Default output is intended to stay readable for humans.

Event JSON is intentionally slim by default. Use `--details` to include `location`, `notes`, and `url`, or opt into individual fields with `--include-location`, `--include-notes`, and `--include-url`.

Example:

```bash
swift run calctl agenda --today --json
```

```json
{
  "range": {
    "start": "2026-04-06T00:00:00+02:00",
    "end": "2026-04-07T00:00:00+02:00",
    "label": "today"
  },
  "events": []
}
```

## Notes

- Read commands require full Calendar access in macOS privacy settings.
- Mutation commands currently also require full access because `update` and `delete` resolve existing events by ID.
- `doctor --request-access` can trigger the EventKit permission prompt when authorization is still undetermined.
- EventKit can lag briefly after `add`, `update`, or `delete`, so an immediate follow-up read/search may reflect stale state for a moment.
- Calendar matching supports either exact title via `--calendar` or exact identifier via `--calendar-id`.
- `agenda` and `search` support `--limit` to cap returned events after sorting by start time.
- `add`, `update`, and `delete` support `--dry-run` to preview the affected event without saving changes.
- `update` supports `--clear-location`, `--clear-notes`, and `--clear-url`.
- When `update` or `delete` targets a recurring event, you must pass one of `--this-event`, `--this-and-future`, or `--entire-series`.

## Not Yet Implemented

- free/busy output
- shell completions
- Homebrew packaging
- broader integration testing across calendar providers
