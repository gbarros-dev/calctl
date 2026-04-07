import Foundation

struct CLI {
    let arguments: [String]
    private let backend: CalendarBackend

    init(arguments: [String], backend: CalendarBackend = EventKitBackend()) {
        self.arguments = arguments
        self.backend = backend
    }

    func run() async {
        let mode = outputMode(from: arguments)

        do {
            guard let command = arguments.first else {
                throw CLIError.usage(Self.helpText)
            }

            switch command {
            case "doctor":
                try await runDoctor(mode: mode)
            case "calendars":
                try runCalendars(mode: mode)
            case "agenda":
                try runAgenda(mode: mode)
            case "search":
                try runSearch(mode: mode)
            case "add":
                try runAdd(mode: mode)
            case "update":
                try runUpdate(mode: mode)
            case "delete":
                try runDelete(mode: mode)
            case "--help", "-h", "help":
                print(Self.helpText)
            default:
                throw CLIError.usage("Unknown command '\(command)'.\n\n\(Self.helpText)")
            }
        } catch let error as CLIError {
            Output.printError(error, mode: mode)
            Foundation.exit(error.exitCode)
        } catch {
            let wrapped = CLIError.unsupported(error.localizedDescription)
            Output.printError(wrapped, mode: mode)
            Foundation.exit(wrapped.exitCode)
        }
    }

    private func runDoctor(mode: OutputMode) async throws {
        let parser = ArgumentParser(arguments: Array(arguments.dropFirst()))
        let report = parser.contains("--request-access")
            ? await backend.requestAccessIfNeeded()
            : backend.doctorReport()

        switch mode {
        case .json:
            try Output.printJSON(report)
        case .plain:
            print("Backend: \(report.backend)")
            print("Authorization: \(report.authorization.rawValue)")
            if let calendarCount = report.calendarCount {
                print("Visible calendars: \(calendarCount)")
            }
            if let writable = report.writableCalendarCount {
                print("Writable calendars: \(writable)")
            }
            if let readOnly = report.readOnlyCalendarCount {
                print("Read-only calendars: \(readOnly)")
            }
            if let calendars = report.calendars, !calendars.isEmpty {
                print("Calendars:")
                for calendar in calendars {
                    let modifier = calendar.allowsContentModifications ? "" : " [read-only]"
                    print("  \(calendar.title) [\(calendar.id)]\(modifier)")
                }
            }
        case .quiet:
            break
        }
    }

    private func runCalendars(mode: OutputMode) throws {
        let calendars = try backend.calendars()
        switch mode {
        case .json:
            try Output.printJSON(CalendarResponse(calendars: calendars))
        case .plain:
            for calendar in calendars {
                let modifier = calendar.allowsContentModifications ? "" : " [read-only]"
                print("\(calendar.title) [\(calendar.id)]\(modifier)")
            }
        case .quiet:
            break
        }
    }

    private func runAgenda(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let range = try DateRangeResolver.resolve(arguments: tail)
        let parser = ArgumentParser(arguments: tail)
        let query = EventQuery(
            range: range,
            calendar: try calendarSelector(parser: parser),
            detailOptions: EventDetailOptions(parser: parser),
            limit: try limitValue(parser: parser)
        )
        let events = try backend.agenda(query: query)
        let rangeRecord = DateRangeRecord(start: iso8601(range.start), end: iso8601(range.end), label: range.label)

        switch mode {
        case .json:
            try Output.printJSON(AgendaResponse(range: rangeRecord, events: events))
        case .plain:
            renderAgendaPlain(events: events)
        case .quiet:
            break
        }
    }

    private func runSearch(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let parser = ArgumentParser(arguments: tail)
        let queryTerms = parser.positionalArguments()
        guard !queryTerms.isEmpty else {
            throw CLIError.usage("search requires a query string.")
        }

        let queryText = queryTerms.joined(separator: " ")
        let hasRange = tail.contains("--today") || tail.contains("--tomorrow") || tail.contains("--week") || tail.contains("--from")
        let range = hasRange ? try DateRangeResolver.resolve(arguments: tail) : nil
        let events = try backend.search(query: SearchQuery(
            text: queryText,
            range: range,
            calendar: try calendarSelector(parser: parser),
            detailOptions: EventDetailOptions(parser: parser),
            limit: try limitValue(parser: parser)
        ))

        switch mode {
        case .json:
            let response = SearchResponse(
                query: queryText,
                range: range.map { DateRangeRecord(start: iso8601($0.start), end: iso8601($0.end), label: $0.label) },
                events: events
            )
            try Output.printJSON(response)
        case .plain:
            renderAgendaPlain(events: events)
        case .quiet:
            break
        }
    }

    private func runAdd(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let parser = ArgumentParser(arguments: tail)
        let calendar = try requiredCalendarSelector(parser: parser)

        guard let title = try parser.value(for: "--title") else {
            throw CLIError.missingValue("Missing value for --title")
        }
        guard let startValue = try parser.value(for: "--start") else {
            throw CLIError.missingValue("Missing value for --start")
        }

        let isAllDay = parser.contains("--all-day")
        let dateParser = DateParser(timeZone: .current)
        let start = try dateParser.parseFlexible(startValue, flag: "--start")
        let end = try resolveAddEnd(parser: parser, start: start, isAllDay: isAllDay)
        let url = try parsedURL(parser: parser, flag: "--url")
        let input = CreateEventInput(
            calendar: calendar,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: try parser.value(for: "--location"),
            notes: try parser.value(for: "--notes"),
            url: url,
            detailOptions: EventDetailOptions(parser: parser)
        )

        if parser.contains("--dry-run") {
            let event = try backend.previewCreateEvent(input: input)
            try printMutationPreview(event: event, mode: mode, action: "add", verb: "Would create")
            return
        }

        let event = try backend.createEvent(input: input)
        try printMutationResult(event: event, mode: mode, verb: "Created")
    }

    private func runUpdate(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let parser = ArgumentParser(arguments: tail)

        guard let id = try parser.value(for: "--id") else {
            throw CLIError.missingValue("Missing value for --id")
        }

        let dateParser = DateParser(timeZone: .current)
        let startValue = try parser.value(for: "--start")
        let endValue = try parser.value(for: "--end")
        let start = try startValue.map { try dateParser.parseFlexible($0, flag: "--start") }
        let end = try endValue.map { try dateParser.parseFlexible($0, flag: "--end") }
        let isAllDay = parser.contains("--all-day") ? true : (parser.contains("--timed") ? false : nil)
        let url = try parsedOptionalUpdateURL(parser: parser)
        let input = UpdateEventInput(
            id: id,
            calendar: try optionalCalendarSelector(parser: parser),
            title: try parser.value(for: "--title"),
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: try parsedOptionalUpdateString(parser: parser, valueFlag: "--location", clearFlag: "--clear-location"),
            notes: try parsedOptionalUpdateString(parser: parser, valueFlag: "--notes", clearFlag: "--clear-notes"),
            url: url,
            recurrenceScope: try recurrenceScope(parser: parser),
            detailOptions: EventDetailOptions(parser: parser)
        )

        if parser.contains("--dry-run") {
            let event = try backend.previewUpdateEvent(input: input)
            try printMutationPreview(event: event, mode: mode, action: "update", verb: "Would update")
            return
        }

        let event = try backend.updateEvent(input: input)
        try printMutationResult(event: event, mode: mode, verb: "Updated")
    }

    private func runDelete(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let parser = ArgumentParser(arguments: tail)
        guard let id = try parser.value(for: "--id") else {
            throw CLIError.missingValue("Missing value for --id")
        }

        let input = DeleteEventInput(
            id: id,
            recurrenceScope: try recurrenceScope(parser: parser),
            detailOptions: EventDetailOptions(parser: parser)
        )

        if parser.contains("--dry-run") {
            let event = try backend.previewDeleteEvent(input: input)
            try printMutationPreview(event: event, mode: mode, action: "delete", verb: "Would delete")
            return
        }

        try backend.deleteEvent(input: input)

        switch mode {
        case .json:
            try Output.printJSON(["deleted": id])
        case .plain:
            print("Deleted \(id)")
        case .quiet:
            break
        }
    }

    private func renderAgendaPlain(events: [EventRecord]) {
        if events.isEmpty {
            print("No events found.")
            return
        }

        for event in events {
            print("\(event.calendar)")
            let summary = event.allDay
                ? "  all-day  \(event.title)"
                : "  \(humanDate(event.start))-\(humanTime(event.end))  \(event.title)"
            print(summary)
        }
    }

    private func printMutationResult(event: EventRecord, mode: OutputMode, verb: String) throws {
        switch mode {
        case .json:
            try Output.printJSON(MutationResponse(event: event))
        case .plain:
            print("\(verb) \(event.id)")
            print("\(event.calendar): \(event.title)")
        case .quiet:
            break
        }
    }

    private func printMutationPreview(event: EventRecord, mode: OutputMode, action: String, verb: String) throws {
        switch mode {
        case .json:
            try Output.printJSON(MutationPreviewResponse(dryRun: true, action: action, event: event))
        case .plain:
            print("\(verb) \(event.id)")
            print("\(event.calendar): \(event.title)")
        case .quiet:
            break
        }
    }

    private func resolveAddEnd(parser: ArgumentParser, start: Date, isAllDay: Bool) throws -> Date {
        let dateParser = DateParser(timeZone: .current)
        if let endValue = try parser.value(for: "--end") {
            let end = try dateParser.parseFlexible(endValue, flag: "--end")
            guard start < end else {
                throw CLIError.invalidDate("Event start must be earlier than end.")
            }
            return end
        }

        let calendar = Calendar(identifier: .gregorian)
        if isAllDay {
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                throw CLIError.invalidDate("Unable to compute all-day event end.")
            }
            return end
        }

        throw CLIError.missingValue("Missing value for --end")
    }

    private func optionalCalendarSelector(parser: ArgumentParser) throws -> CalendarSelector? {
        let selector = try calendarSelector(parser: parser)
        return selector.isEmpty ? nil : selector
    }

    private func requiredCalendarSelector(parser: ArgumentParser) throws -> CalendarSelector {
        let selector = try calendarSelector(parser: parser)
        guard !selector.isEmpty else {
            throw CLIError.usage("Specify either --calendar or --calendar-id.")
        }
        return selector
    }

    private func calendarSelector(parser: ArgumentParser) throws -> CalendarSelector {
        CalendarSelector(
            name: try parser.value(for: "--calendar"),
            id: try parser.value(for: "--calendar-id")
        )
    }

    private func recurrenceScope(parser: ArgumentParser) throws -> RecurrenceScope? {
        let requestedScopes: [RecurrenceScope] = [
            parser.contains("--this-event") ? .thisEvent : nil,
            parser.contains("--this-and-future") ? .thisAndFuture : nil,
            parser.contains("--entire-series") ? .entireSeries : nil,
        ].compactMap { $0 }

        guard requestedScopes.count <= 1 else {
            throw CLIError.invalidValue("Choose only one recurrence scope flag.")
        }
        return requestedScopes.first
    }

    private func limitValue(parser: ArgumentParser) throws -> Int? {
        guard let limit = try parser.intValue(for: "--limit") else {
            return nil
        }
        guard limit > 0 else {
            throw CLIError.invalidValue("--limit must be greater than 0.")
        }
        return limit
    }

    private func parsedOptionalUpdateString(parser: ArgumentParser, valueFlag: String, clearFlag: String) throws -> String?? {
        if parser.contains(clearFlag) {
            guard try parser.value(for: valueFlag) == nil else {
                throw CLIError.invalidValue("Use either \(valueFlag) or \(clearFlag), not both.")
            }
            return .some(nil)
        }

        if let value = try parser.value(for: valueFlag) {
            return .some(value)
        }

        return nil
    }

    private func parsedURL(parser: ArgumentParser, flag: String) throws -> URL? {
        guard let rawValue = try parser.value(for: flag) else {
            return nil
        }
        guard let url = URL(string: rawValue) else {
            throw CLIError.invalidValue("Invalid URL for \(flag): \(rawValue)")
        }
        return url
    }

    private func parsedOptionalUpdateURL(parser: ArgumentParser) throws -> URL?? {
        if parser.contains("--clear-url") {
            guard try parser.value(for: "--url") == nil else {
                throw CLIError.invalidValue("Use either --url or --clear-url, not both.")
            }
            return .some(nil)
        }

        if let url = try parsedURL(parser: parser, flag: "--url") {
            return .some(url)
        }

        return nil
    }

    private func outputMode(from arguments: [String]) -> OutputMode {
        if arguments.contains("--json") {
            return .json
        }
        if arguments.contains("--quiet") {
            return .quiet
        }
        return .plain
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func humanDate(_ rawValue: String) -> String {
        guard let date = parseISO8601(rawValue) else {
            return rawValue
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func humanTime(_ rawValue: String) -> String {
        guard let date = parseISO8601(rawValue) else {
            return rawValue
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func parseISO8601(_ value: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            formatter.timeZone = .current
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    static let helpText = """
    calctl

    Usage:
      calctl doctor [--request-access] [--json]
      calctl calendars [--json]
      calctl agenda [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME|--calendar-id ID] [--limit N] [--details|--include-location|--include-notes|--include-url] [--json]
      calctl search QUERY [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME|--calendar-id ID] [--limit N] [--details|--include-location|--include-notes|--include-url] [--json]
      calctl add (--calendar NAME|--calendar-id ID) --title TITLE --start VALUE --end VALUE [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
      calctl update --id EVENT_ID [--calendar NAME|--calendar-id ID] [--title TITLE] [--start VALUE] [--end VALUE] [--location VALUE|--clear-location] [--notes VALUE|--clear-notes] [--url VALUE|--clear-url] [--all-day|--timed] [--this-event|--this-and-future|--entire-series] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
      calctl delete --id EVENT_ID [--this-event|--this-and-future|--entire-series] [--dry-run] [--details|--include-location|--include-notes|--include-url] [--json]
    """
}
