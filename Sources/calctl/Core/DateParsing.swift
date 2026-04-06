import Foundation

struct ResolvedDateRange {
    let start: Date
    let end: Date
    let label: String
}

enum DateRangeResolver {
    static func resolve(arguments: [String], now: Date = Date(), timeZone: TimeZone = .current) throws -> ResolvedDateRange {
        let parser = ArgumentParser(arguments: arguments)

        if arguments.contains("--today") {
            return try dayRange(offsetDays: 0, label: "today", now: now, timeZone: timeZone)
        }

        if arguments.contains("--tomorrow") {
            return try dayRange(offsetDays: 1, label: "tomorrow", now: now, timeZone: timeZone)
        }

        if arguments.contains("--week") {
            return try weekRange(now: now, timeZone: timeZone)
        }

        if let from = try parser.value(for: "--from"), let to = try parser.value(for: "--to") {
            let dateParser = DateParser(timeZone: timeZone)
            let start = try dateParser.parseDateOnly(from, flag: "--from")
            let endDate = try dateParser.parseDateOnly(to, flag: "--to")

            guard let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: endDate) else {
                throw CLIError.invalidDate("Unable to compute end date for --to \(to)")
            }

            guard start < end else {
                throw CLIError.invalidDate("--from must be earlier than or equal to --to")
            }

            return ResolvedDateRange(start: start, end: end, label: "\(from)...\(to)")
        }

        return try dayRange(offsetDays: 0, label: "today", now: now, timeZone: timeZone)
    }

    private static func dayRange(offsetDays: Int, label: String, now: Date, timeZone: TimeZone) throws -> ResolvedDateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let day = calendar.date(byAdding: .day, value: offsetDays, to: now) ?? now
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw CLIError.invalidDate("Unable to compute \(label) range")
        }

        return ResolvedDateRange(start: start, end: end, label: label)
    }

    private static func weekRange(now: Date, timeZone: TimeZone) throws -> ResolvedDateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            throw CLIError.invalidDate("Unable to compute week range")
        }

        return ResolvedDateRange(start: start, end: end, label: "week")
    }
}

struct DateParser {
    let timeZone: TimeZone
    private let calendar = Calendar(identifier: .gregorian)

    func parseDateOnly(_ value: String, flag: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: value) else {
            throw CLIError.invalidDate("Invalid value for \(flag): \(value). Expected YYYY-MM-DD.")
        }

        return date
    }

    func parseFlexible(_ value: String, flag: String, now: Date = Date()) throws -> Date {
        switch value.lowercased() {
        case "today":
            return startOfDay(relativeTo: now, offsetDays: 0)
        case "tomorrow":
            return startOfDay(relativeTo: now, offsetDays: 1)
        default:
            break
        }

        if let date = parseISO8601(value) {
            return date
        }

        let localDateTime = DateFormatter()
        localDateTime.calendar = calendar
        localDateTime.locale = Locale(identifier: "en_US_POSIX")
        localDateTime.timeZone = timeZone
        localDateTime.dateFormat = "yyyy-MM-dd HH:mm"
        if let date = localDateTime.date(from: value) {
            return date
        }

        return try parseDateOnly(value, flag: flag)
    }

    private func parseISO8601(_ value: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            formatter.timeZone = timeZone
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func startOfDay(relativeTo now: Date, offsetDays: Int) -> Date {
        var mutableCalendar = calendar
        mutableCalendar.timeZone = timeZone
        let base = mutableCalendar.date(byAdding: .day, value: offsetDays, to: now) ?? now
        return mutableCalendar.startOfDay(for: base)
    }
}
