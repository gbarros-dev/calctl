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
calctl agenda [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME] [--json]
calctl search QUERY [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME] [--json]
calctl add --calendar NAME --title TITLE --start VALUE --end VALUE [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day] [--json]
calctl update --id EVENT_ID [--calendar NAME] [--title TITLE] [--start VALUE] [--end VALUE] [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day|--timed] [--json]
calctl delete --id EVENT_ID [--json]
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
- Calendar matching is currently by exact calendar title.

## Not Yet Implemented

- recurrence-safe mutation scope such as `--this-event` and `--entire-series`
- free/busy output
- shell completions
- Homebrew packaging
- broader integration testing across calendar providers
