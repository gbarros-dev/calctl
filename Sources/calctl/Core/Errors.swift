import Foundation

enum CLIError: Error {
    case usage(String)
    case invalidDate(String)
    case missingValue(String)
    case permissionDenied(AuthorizationState)
    case calendarNotFound(String)
    case eventNotFound(String)
    case readOnlyCalendar(String)
    case unsupported(String)
}

extension CLIError {
    var code: String {
        switch self {
        case .usage:
            return "usage"
        case .invalidDate:
            return "invalid_date_time"
        case .missingValue:
            return "missing_value"
        case .permissionDenied:
            return "permission_denied"
        case .calendarNotFound:
            return "calendar_not_found"
        case .eventNotFound:
            return "event_not_found"
        case .readOnlyCalendar:
            return "read_only_calendar"
        case .unsupported:
            return "unsupported_operation"
        }
    }

    var message: String {
        switch self {
        case .usage(let message),
             .invalidDate(let message),
             .missingValue(let message),
             .calendarNotFound(let message),
             .eventNotFound(let message),
             .readOnlyCalendar(let message),
             .unsupported(let message):
            return message
        case .permissionDenied(let state):
            switch state {
            case .notDetermined:
                return "Calendar access has not been granted yet. Open Calendar once or add a permission-request flow before querying events."
            case .denied, .restricted:
                return "Calendar access is unavailable. Grant Calendar access in System Settings."
            case .writeOnly:
                return "Calendar access is write-only; read commands need full access."
            case .fullAccess, .unsupported:
                return "Calendar access is unavailable."
            }
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage, .missingValue:
            return 64
        case .invalidDate:
            return 65
        case .calendarNotFound, .eventNotFound:
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
