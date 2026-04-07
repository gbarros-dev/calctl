import Foundation

enum OutputMode: String {
    case plain
    case json
    case quiet
}

enum AuthorizationState: String, Codable {
    case fullAccess = "full_access"
    case writeOnly = "write_only"
    case denied
    case restricted
    case notDetermined = "not_determined"
    case unsupported
}

struct EventDetailOptions {
    let includeLocation: Bool
    let includeNotes: Bool
    let includeURL: Bool

    init(parser: ArgumentParser) {
        let details = parser.contains("--details")
        includeLocation = details || parser.contains("--include-location")
        includeNotes = details || parser.contains("--include-notes")
        includeURL = details || parser.contains("--include-url")
    }

    static let summary = EventDetailOptions(includeLocation: false, includeNotes: false, includeURL: false)

    init(includeLocation: Bool, includeNotes: Bool, includeURL: Bool) {
        self.includeLocation = includeLocation
        self.includeNotes = includeNotes
        self.includeURL = includeURL
    }
}

struct CalendarSelector {
    let name: String?
    let id: String?

    var isEmpty: Bool {
        name == nil && id == nil
    }
}

enum RecurrenceScope: String, Codable {
    case thisEvent = "this_event"
    case thisAndFuture = "this_and_future"
    case entireSeries = "entire_series"
}

struct CalendarRecord: Codable {
    let id: String
    let title: String
    let source: String?
    let allowsContentModifications: Bool
}

struct EventRecord: Codable {
    let id: String
    let calendarID: String
    let calendar: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let readOnly: Bool
}

struct SearchResponse: Codable {
    let query: String
    let range: DateRangeRecord?
    let events: [EventRecord]
}

struct MutationResponse: Codable {
    let event: EventRecord
}

struct MutationPreviewResponse: Codable {
    let dryRun: Bool
    let action: String
    let event: EventRecord
}

struct DoctorReport: Codable {
    let backend: String
    let authorization: AuthorizationState
    let calendarCount: Int?
    let writableCalendarCount: Int?
    let readOnlyCalendarCount: Int?
    let calendars: [CalendarRecord]?
}

struct CalendarResponse: Codable {
    let calendars: [CalendarRecord]
}

struct AgendaResponse: Codable {
    let range: DateRangeRecord
    let events: [EventRecord]
}

struct DateRangeRecord: Codable {
    let start: String
    let end: String
    let label: String
}

struct ErrorEnvelope: Codable {
    let error: ErrorRecord
}

struct ErrorRecord: Codable {
    let code: String
    let message: String
    let details: [String]?
}
