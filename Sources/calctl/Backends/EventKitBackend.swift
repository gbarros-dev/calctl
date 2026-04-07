import EventKit
import Foundation

struct EventQuery {
    let range: ResolvedDateRange
    let calendar: CalendarSelector
    let detailOptions: EventDetailOptions
    let limit: Int?
}

struct SearchQuery {
    let text: String
    let range: ResolvedDateRange?
    let calendar: CalendarSelector
    let detailOptions: EventDetailOptions
    let limit: Int?
}

struct CreateEventInput {
    let calendar: CalendarSelector
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
    let detailOptions: EventDetailOptions
}

struct UpdateEventInput {
    let id: String
    let calendar: CalendarSelector?
    let title: String?
    let start: Date?
    let end: Date?
    let isAllDay: Bool?
    let location: String??
    let notes: String??
    let url: URL??
    let recurrenceScope: RecurrenceScope?
    let detailOptions: EventDetailOptions
}

struct DeleteEventInput {
    let id: String
    let recurrenceScope: RecurrenceScope?
    let detailOptions: EventDetailOptions
}

final class EventKitBackend: CalendarBackend {
    private let store = EKEventStore()
    private let isoFormatter: ISO8601DateFormatter

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        self.isoFormatter = formatter
    }

    func doctorReport() -> DoctorReport {
        let state = authorizationState()
        let calendars = readableCalendarsIfAuthorized(for: state) ?? []
        let records = calendars.map(calendarRecord(from:))
        let writableCount = records.filter(\.allowsContentModifications).count
        let readOnlyCount = records.count - writableCount

        return DoctorReport(
            backend: "eventkit",
            authorization: state,
            calendarCount: state == .fullAccess ? records.count : nil,
            writableCalendarCount: state == .fullAccess ? writableCount : nil,
            readOnlyCalendarCount: state == .fullAccess ? readOnlyCount : nil,
            calendars: state == .fullAccess ? records : nil
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

        let calendars = try selectedCalendars(matching: query.calendar)
        let predicate = store.predicateForEvents(withStart: query.range.start, end: query.range.end, calendars: calendars)
        return limitedSortedEvents(predicate: predicate, limit: query.limit)
            .map { eventRecord(from: $0, detailOptions: query.detailOptions) }
    }

    func search(query: SearchQuery) throws -> [EventRecord] {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let calendars = try selectedCalendars(matching: query.calendar)
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
        }.sorted(by: compareEvents)

        let limited = query.limit.map { Array(events.prefix($0)) } ?? events
        return limited.map { eventRecord(from: $0, detailOptions: query.detailOptions) }
    }

    func createEvent(input: CreateEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let calendar = try writableCalendar(matching: input.calendar)
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
        return eventRecord(from: event, detailOptions: input.detailOptions)
    }

    func previewCreateEvent(input: CreateEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let calendar = try writableCalendar(matching: input.calendar)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = input.title
        event.startDate = input.start
        event.endDate = input.end
        event.isAllDay = input.isAllDay
        event.location = input.location
        event.notes = input.notes
        event.url = input.url

        return eventRecord(from: event, detailOptions: input.detailOptions)
    }

    func updateEvent(input: UpdateEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let plan = try mutationPlan(forEventID: input.id, recurrenceScope: input.recurrenceScope)
        try applyUpdates(input, to: plan.event, referenceEvent: plan.referenceEvent)
        try store.save(plan.event, span: plan.span)
        return eventRecord(from: plan.event, detailOptions: input.detailOptions)
    }

    func previewUpdateEvent(input: UpdateEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let plan = try mutationPlan(forEventID: input.id, recurrenceScope: input.recurrenceScope)
        try applyUpdates(input, to: plan.event, referenceEvent: plan.referenceEvent)
        return eventRecord(from: plan.event, detailOptions: input.detailOptions)
    }

    func deleteEvent(input: DeleteEventInput) throws {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let plan = try mutationPlan(forEventID: input.id, recurrenceScope: input.recurrenceScope)
        try store.remove(plan.event, span: plan.span)
    }

    func previewDeleteEvent(input: DeleteEventInput) throws -> EventRecord {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw CLIError.permissionDenied(state)
        }

        let plan = try mutationPlan(forEventID: input.id, recurrenceScope: input.recurrenceScope)
        return eventRecord(from: plan.event, detailOptions: input.detailOptions)
    }

    private func authorizationState() -> AuthorizationState {
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

    private func selectedCalendars(matching selector: CalendarSelector) throws -> [EKCalendar]? {
        let calendars = readableCalendarsIfAuthorized(for: .fullAccess) ?? []
        guard !selector.isEmpty else {
            return calendars
        }

        let matches = calendars.filter { calendar in
            let nameMatches = selector.name.map { calendar.title == $0 } ?? true
            let idMatches = selector.id.map { calendar.calendarIdentifier == $0 } ?? true
            return nameMatches && idMatches
        }

        if let requestedID = selector.id, selector.name == nil {
            guard !matches.isEmpty else {
                throw CLIError.calendarNotFound("Calendar id '\(requestedID)' was not found.")
            }
            return matches
        }

        if let requestedName = selector.name, selector.id == nil {
            guard !matches.isEmpty else {
                throw CLIError.calendarNotFound("Calendar '\(requestedName)' was not found.")
            }
            guard matches.count == 1 else {
                throw CLIError.ambiguousCalendar(
                    requested: requestedName,
                    matches: matches.map(calendarSummary)
                )
            }
            return matches
        }

        guard !matches.isEmpty else {
            throw CLIError.calendarNotFound(calendarSelectorDescription(selector))
        }
        return matches
    }

    private func writableCalendar(matching selector: CalendarSelector) throws -> EKCalendar {
        let calendars = try selectedCalendars(matching: selector) ?? []
        guard let calendar = calendars.first else {
            throw CLIError.calendarNotFound(calendarSelectorDescription(selector))
        }
        guard calendar.allowsContentModifications else {
            throw CLIError.readOnlyCalendar("Calendar '\(calendar.title)' is read-only.")
        }
        return calendar
    }

    private func mutationPlan(forEventID id: String, recurrenceScope: RecurrenceScope?) throws -> MutationPlan {
        let event = try editableEvent(id: id)
        let isRecurring = event.hasRecurrenceRules || event.occurrenceDate != nil

        if isRecurring, recurrenceScope == nil {
            throw CLIError.recurringScopeRequired(
                "Event '\(id)' is recurring. Pass one of --this-event, --this-and-future, or --entire-series."
            )
        }

        guard let recurrenceScope else {
            return MutationPlan(event: event, referenceEvent: event, span: .thisEvent)
        }

        switch recurrenceScope {
        case .thisEvent:
            return MutationPlan(event: event, referenceEvent: event, span: .thisEvent)
        case .thisAndFuture:
            return MutationPlan(event: event, referenceEvent: event, span: .futureEvents)
        case .entireSeries:
            let seriesEvent = try seriesAnchor(for: event)
            return MutationPlan(event: seriesEvent, referenceEvent: event, span: .futureEvents)
        }
    }

    private func editableEvent(id: String) throws -> EKEvent {
        guard let event = store.event(withIdentifier: id) else {
            throw CLIError.eventNotFound("Event '\(id)' was not found.")
        }
        guard event.calendar.allowsContentModifications else {
            throw CLIError.readOnlyCalendar("Event '\(id)' belongs to a read-only calendar.")
        }
        return event
    }

    private func seriesAnchor(for event: EKEvent) throws -> EKEvent {
        if event.hasRecurrenceRules, !event.isDetached {
            return event
        }

        let items = store.calendarItems(withExternalIdentifier: event.calendarItemExternalIdentifier)
        let candidates = items
            .compactMap { $0 as? EKEvent }
            .filter { candidate in
                candidate.calendar.calendarIdentifier == event.calendar.calendarIdentifier &&
                candidate.hasRecurrenceRules &&
                !candidate.isDetached
            }
            .sorted(by: compareEvents)

        if let candidate = candidates.first {
            guard candidate.calendar.allowsContentModifications else {
                throw CLIError.readOnlyCalendar("Event '\(resolvedEventIdentifier(for: event))' belongs to a read-only calendar.")
            }
            return candidate
        }

        return event
    }

    private func applyUpdates(_ input: UpdateEventInput, to event: EKEvent, referenceEvent: EKEvent) throws {
        if let selector = input.calendar {
            event.calendar = try writableCalendar(matching: selector)
        }
        if let title = input.title {
            event.title = title
        }
        if let start = input.start {
            event.startDate = shiftedDate(for: start, event: event, referenceEvent: referenceEvent, isStart: true)
        }
        if let end = input.end {
            event.endDate = shiftedDate(for: end, event: event, referenceEvent: referenceEvent, isStart: false)
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
    }

    private func shiftedDate(for inputDate: Date, event: EKEvent, referenceEvent: EKEvent, isStart: Bool) -> Date {
        guard event !== referenceEvent else {
            return inputDate
        }

        let referenceBase = (isStart ? referenceEvent.startDate : referenceEvent.endDate)!
        let targetBase = (isStart ? event.startDate : event.endDate)!
        let delta = inputDate.timeIntervalSince(referenceBase)
        return targetBase.addingTimeInterval(delta)
    }

    private func limitedSortedEvents(predicate: NSPredicate, limit: Int?) -> [EKEvent] {
        let events = store.events(matching: predicate).sorted(by: compareEvents)
        return limit.map { Array(events.prefix($0)) } ?? events
    }

    private func compareEvents(_ lhs: EKEvent, _ rhs: EKEvent) -> Bool {
        if lhs.startDate == rhs.startDate {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.startDate < rhs.startDate
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

    private func eventRecord(from event: EKEvent, detailOptions: EventDetailOptions) -> EventRecord {
        EventRecord(
            id: resolvedEventIdentifier(for: event),
            calendarID: event.calendar.calendarIdentifier,
            calendar: event.calendar.title,
            title: event.title.isEmpty ? "(untitled)" : event.title,
            start: isoFormatter.string(from: event.startDate),
            end: isoFormatter.string(from: event.endDate),
            allDay: event.isAllDay,
            location: detailOptions.includeLocation ? event.location : nil,
            notes: detailOptions.includeNotes ? event.notes : nil,
            url: detailOptions.includeURL ? event.url?.absoluteString : nil,
            readOnly: !event.calendar.allowsContentModifications
        )
    }

    private func calendarSummary(_ calendar: EKCalendar) -> String {
        let source = calendar.source.title
        if !source.isEmpty {
            return "\(calendar.title) [\(calendar.calendarIdentifier)] (\(source))"
        }
        return "\(calendar.title) [\(calendar.calendarIdentifier)]"
    }

    private func resolvedEventIdentifier(for event: EKEvent) -> String {
        if let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty {
            return eventIdentifier
        }
        let calendarItemIdentifier = event.calendarItemIdentifier
        if !calendarItemIdentifier.isEmpty {
            return calendarItemIdentifier
        }
        return "preview"
    }

    private func calendarSelectorDescription(_ selector: CalendarSelector) -> String {
        if let name = selector.name, let id = selector.id {
            return "Calendar '\(name)' with id '\(id)' was not found."
        }
        if let name = selector.name {
            return "Calendar '\(name)' was not found."
        }
        if let id = selector.id {
            return "Calendar id '\(id)' was not found."
        }
        return "Calendar was not found."
    }
}

private struct MutationPlan {
    let event: EKEvent
    let referenceEvent: EKEvent
    let span: EKSpan
}
