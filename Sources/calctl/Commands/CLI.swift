import Foundation

struct CLI {
    let arguments: [String]
    private let backend = EventKitBackend()

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
                print("\(calendar.title)\(modifier)")
            }
        case .quiet:
            break
        }
    }

    private func runAgenda(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let range = try DateRangeResolver.resolve(arguments: tail)
        let parser = ArgumentParser(arguments: tail)
        let calendarName = try parser.value(for: "--calendar")
        let events = try backend.agenda(query: EventQuery(range: range, calendarName: calendarName))
        let rangeRecord = DateRangeRecord(
            start: iso8601(range.start),
            end: iso8601(range.end),
            label: range.label
        )

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
        let calendarName = try parser.value(for: "--calendar")
        let events = try backend.search(query: SearchQuery(text: queryText, range: range, calendarName: calendarName))

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

        guard let calendar = try parser.value(for: "--calendar") else {
            throw CLIError.missingValue("Missing value for --calendar")
        }
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
        let url = try parser.value(for: "--url").flatMap(URL.init(string:))

        let event = try backend.createEvent(input: CreateEventInput(
            calendarName: calendar,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: try parser.value(for: "--location"),
            notes: try parser.value(for: "--notes"),
            url: url
        ))

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
        let url = try parser.value(for: "--url").flatMap(URL.init(string:))

        let event = try backend.updateEvent(input: UpdateEventInput(
            id: id,
            calendarName: try parser.value(for: "--calendar"),
            title: try parser.value(for: "--title"),
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: try parser.value(for: "--location"),
            notes: try parser.value(for: "--notes"),
            url: url
        ))

        try printMutationResult(event: event, mode: mode, verb: "Updated")
    }

    private func runDelete(mode: OutputMode) throws {
        let tail = Array(arguments.dropFirst())
        let parser = ArgumentParser(arguments: tail)
        guard let id = try parser.value(for: "--id") else {
            throw CLIError.missingValue("Missing value for --id")
        }

        try backend.deleteEvent(id: id)

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
      calctl agenda [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME] [--json]
      calctl search QUERY [--today|--tomorrow|--week|--from YYYY-MM-DD --to YYYY-MM-DD] [--calendar NAME] [--json]
      calctl add --calendar NAME --title TITLE --start VALUE --end VALUE [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day] [--json]
      calctl update --id EVENT_ID [--calendar NAME] [--title TITLE] [--start VALUE] [--end VALUE] [--location VALUE] [--notes VALUE] [--url VALUE] [--all-day|--timed] [--json]
      calctl delete --id EVENT_ID [--json]
    """
}
