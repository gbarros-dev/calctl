import Foundation

protocol CalendarBackend {
    func doctorReport() -> DoctorReport
    func requestAccessIfNeeded() async -> DoctorReport
    func calendars() throws -> [CalendarRecord]
    func agenda(query: EventQuery) throws -> [EventRecord]
    func search(query: SearchQuery) throws -> [EventRecord]
    func createEvent(input: CreateEventInput) throws -> EventRecord
    func previewCreateEvent(input: CreateEventInput) throws -> EventRecord
    func updateEvent(input: UpdateEventInput) throws -> EventRecord
    func previewUpdateEvent(input: UpdateEventInput) throws -> EventRecord
    func deleteEvent(input: DeleteEventInput) throws
    func previewDeleteEvent(input: DeleteEventInput) throws -> EventRecord
}
