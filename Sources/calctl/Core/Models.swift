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

struct DoctorReport: Codable {
    let backend: String
    let authorization: AuthorizationState
    let calendarCount: Int?
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
}
