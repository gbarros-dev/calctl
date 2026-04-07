import Foundation

enum CLIError: Error {
    case usage(String)
    case invalidDate(String)
    case invalidValue(String)
    case missingValue(String)
    case permissionDenied(AuthorizationState)
    case calendarNotFound(String)
    case ambiguousCalendar(requested: String, matches: [String])
    case eventNotFound(String)
    case readOnlyCalendar(String)
    case recurringScopeRequired(String)
    case unsupported(String)
}

extension CLIError {
    var code: String {
        switch self {
        case .usage:
            return "usage"
        case .invalidDate:
            return "invalid_date_time"
        case .invalidValue:
            return "invalid_value"
        case .missingValue:
            return "missing_value"
        case .permissionDenied:
            return "permission_denied"
        case .calendarNotFound:
            return "calendar_not_found"
        case .ambiguousCalendar:
            return "ambiguous_calendar"
        case .eventNotFound:
            return "event_not_found"
        case .readOnlyCalendar:
            return "read_only_calendar"
        case .recurringScopeRequired:
            return "recurring_scope_required"
        case .unsupported:
            return "unsupported_operation"
        }
    }

    var message: String {
        switch self {
        case .usage(let message),
             .invalidDate(let message),
             .invalidValue(let message),
             .missingValue(let message),
             .calendarNotFound(let message),
             .eventNotFound(let message),
             .readOnlyCalendar(let message),
             .recurringScopeRequired(let message),
             .unsupported(let message):
            return message
        case .ambiguousCalendar(let requested, _):
            return "Calendar '\(requested)' matched more than one calendar. Use --calendar-id to target one exactly."
        case .permissionDenied(let state):
            switch state {
            case .notDetermined:
                return "Calendar access has not been granted yet. Run 'calctl doctor --request-access' first."
            case .denied, .restricted:
                return "Calendar access is unavailable. Grant Calendar access in System Settings."
            case .writeOnly:
                return "Calendar access is write-only; read commands need full access."
            case .fullAccess, .unsupported:
                return "Calendar access is unavailable."
            }
        }
    }

    var details: [String]? {
        switch self {
        case .ambiguousCalendar(_, let matches):
            return matches
        case .permissionDenied(let state):
            return ["authorization=\(state.rawValue)"]
        case .calendarNotFound(let message),
             .eventNotFound(let message),
             .readOnlyCalendar(let message),
             .recurringScopeRequired(let message),
             .invalidDate(let message),
             .invalidValue(let message),
             .missingValue(let message),
             .usage(let message),
             .unsupported(let message):
            return [message]
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage, .missingValue, .recurringScopeRequired:
            return 64
        case .invalidDate, .invalidValue:
            return 65
        case .calendarNotFound, .eventNotFound, .ambiguousCalendar:
            return 66
        case .readOnlyCalendar:
            return 73
        case .permissionDenied:
            return 77
        case .unsupported:
            return 69
        }
    }
}
