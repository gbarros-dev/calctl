import EventKit
import Foundation

struct EventQuery {
    let range: ResolvedDateRange
    let calendarName: String?
}

struct SearchQuery {
    let text: String
    let range: ResolvedDateRange?
    let calendarName: String?
}

struct CreateEventInput {
    let calendarName: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
}

struct UpdateEventInput {
    let id: String
    let calendarName: String?
    let title: String?
    let start: Date?
    let end: Date?
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let url: URL?
}

final class EventKitBackend {
    private let store = EKEventStore()
    private let isoFormatter: ISO8601DateFormatter

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        self.isoFormatter = formatter
    }

    func authorizationState() -> AuthorizationState {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unsupported
        }
    }

    func doctorReport() -> DoctorReport {
        let state = authorizationState()
        let calendars = readableCalendarsIfAuthorized(for: state)?.map(calendarRecord(from:))
        return DoctorReport(
            backend: "eventkit",
            authorization: state,
            calendarCount: calendars?.count,
            calendars: calendars
        )
    }

    func requestAccessIfNeeded() async -> DoctorReport {
        let state = authorizationState()
        guard state == .notDetermined else {
            return doctorReport()
        }

        _ = await requestCalendarAccess()
        return doctorReport()
    }

    func calendars() throws -> [CalendarRecord] {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        return readableCalendarsIfAuthorized(for: state)?.map(calendarRecord(from:)) ?? []
    }

    func agenda(query: EventQuery) throws -> [EventRecord] {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let calendars = try selectedCalendars(named: query.calendarName)
        let predicate = store.predicateForEvents(withStart: query.range.start, end: query.range.end, calendars: calendars)
        let events = store.events(matching: predicate).sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.startDate < rhs.startDate
        }

        return events.map(eventRecord(from:))
    }

    func search(query: SearchQuery) throws -> [EventRecord] {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let calendars = try selectedCalendars(named: query.calendarName)
        let range = query.range ?? defaultSearchRange()
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
        let normalized = SearchMatcher.normalize(query.text)

        let events = store.events(matching: predicate).filter { event in
            SearchMatcher.matches(query: normalized, fields: [
                event.title,
                event.location,
                event.notes,
                event.url?.absoluteString,
            ])
        }.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.startDate < rhs.startDate
        }

        return events.map(eventRecord(from:))
    }

    func createEvent(input: CreateEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let calendar = try writableCalendar(named: input.calendarName)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = input.title
        event.startDate = input.start
        event.endDate = input.end
        event.isAllDay = input.isAllDay
        event.location = input.location
        event.notes = input.notes
        event.url = input.url

        try store.save(event, span: .thisEvent)
        return eventRecord(from: event)
    }

    func updateEvent(input: UpdateEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        guard let event = store.event(withIdentifier: input.id) else {
            throw CLIError.eventNotFound("Event '\(input.id)' was not found.")
        }
        guard event.calendar.allowsContentModifications else {
            throw CLIError.readOnlyCalendar("Event '\(input.id)' belongs to a read-only calendar.")
        }

        if let calendarName = input.calendarName {
            event.calendar = try writableCalendar(named: calendarName)
        }
        if let title = input.title {
            event.title = title
        }
        if let start = input.start {
            event.startDate = start
        }
        if let end = input.end {
            event.endDate = end
        }
        if let isAllDay = input.isAllDay {
            event.isAllDay = isAllDay
        }
        if let location = input.location {
            event.location = location
        }
        if let notes = input.notes {
            event.notes = notes
        }
        if let url = input.url {
            event.url = url
        }

        guard event.startDate < event.endDate else {
            throw CLIError.invalidDate("Event start must be earlier than end.")
        }

        try store.save(event, span: .thisEvent)
        return eventRecord(from: event)
    }

    func deleteEvent(id: String) throws {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        guard let event = store.event(withIdentifier: id) else {
            throw CLIError.eventNotFound("Event '\(id)' was not found.")
        }
        guard event.calendar.allowsContentModifications else {
            throw CLIError.readOnlyCalendar("Event '\(id)' belongs to a read-only calendar.")
        }

        try store.remove(event, span: .thisEvent)
    }

    private func selectedCalendars(named calendarName: String?) throws -> [EKCalendar]? {
        let calendars = readableCalendarsIfAuthorized(for: .fullAccess) ?? []
        guard let calendarName else {
            return calendars
        }

        let filtered = calendars.filter { $0.title == calendarName }
        guard !filtered.isEmpty else {
            throw CLIError.calendarNotFound("Calendar '\(calendarName)' was not found.")
        }
        return filtered
    }

    private func writableCalendar(named calendarName: String) throws -> EKCalendar {
        let calendars = try selectedCalendars(named: calendarName) ?? []
        guard let calendar = calendars.first else {
            throw CLIError.calendarNotFound("Calendar '\(calendarName)' was not found.")
        }
        guard calendar.allowsContentModifications else {
            throw CLIError.readOnlyCalendar("Calendar '\(calendarName)' is read-only.")
        }
        return calendar
    }

    private func defaultSearchRange(now: Date = Date()) -> ResolvedDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: 365, to: now) ?? now
        return ResolvedDateRange(start: start, end: end, label: "default-search-window")
    }

    private func readableCalendarsIfAuthorized(for state: AuthorizationState) -> [EKCalendar]? {
        guard state == .fullAccess else {
            return nil
        }
        return store.calendars(for: .event)
    }

    private func requestCalendarAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            } else {
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func calendarRecord(from calendar: EKCalendar) -> CalendarRecord {
        CalendarRecord(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            source: calendar.source.title,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private func eventRecord(from event: EKEvent) -> EventRecord {
        EventRecord(
            id: event.eventIdentifier,
            calendarID: event.calendar.calendarIdentifier,
            calendar: event.calendar.title,
            title: event.title.isEmpty ? "(untitled)" : event.title,
            start: isoFormatter.string(from: event.startDate),
            end: isoFormatter.string(from: event.endDate),
            allDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            readOnly: !event.calendar.allowsContentModifications
        )
    }
}
