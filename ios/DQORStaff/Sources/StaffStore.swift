import Foundation
import Combine

@MainActor
final class StaffStore: ObservableObject {
    @Published private(set) var session: StaffSession?
    @Published private(set) var days: [EventDay] = []
    @Published private(set) var day: EventDay?
    @Published private(set) var matches: [Attendee] = []
    @Published private(set) var selection: [Attendee] = []
    @Published private(set) var results: [CheckInResult] = []
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var confirming = false
    private let api: any StaffAPI
    private var generation = UUID()
    private var scanGate = ScanGate()
    private var pendingRequestID: UUID?
    var batchLimit: Int { day?.maxBatchSize ?? 50 }
    func can(_ capability: StaffCapability) -> Bool { session?.capabilities.contains(capability) == true }
    init(api: any StaffAPI) { self.api = api }

    private func handle(_ error: Error) {
        if let staffError = error as? StaffError, staffError == .signedOut || staffError == .forbidden {
            generation = UUID(); session = nil; days = []; day = nil; matches = []; selection = []; results = []
            confirming = false; pendingRequestID = nil; scanGate.reset()
        }
        message = error.localizedDescription
    }

    func signIn() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let session = try await api.signIn()
            let days = try await api.eventDays()
            self.session = session; self.days = days
        } catch { handle(error) }
    }
    func signOut() async {
        guard !busy else { return }
        generation = UUID(); clearDay(); session = nil; days = []
        busy = true
        defer { busy = false }
        do { try await api.signOut() } catch { handle(error) }
    }
    func choose(_ day: EventDay) {
        guard !busy else { return }
        clearDay(); self.day = day
    }
    func clearDay() {
        guard !busy else { return }
        generation = UUID(); day = nil; matches = []; selection = []; results = []
        message = nil; confirming = false; scanGate.reset(); pendingRequestID = nil
    }
    func search(_ query: String) async {
        guard let day, !busy, can(.searchAttendees) else { return }
        busy = true; message = nil; let current = generation
        defer { busy = false }
        do {
            let page = try await api.search(query, day: day)
            if generation == current {
                matches = page.attendees
                if page.moreResults { message = NativeAPIError.moreResults.localizedDescription }
                else if matches.isEmpty { message = "No attendees found. Try another name, email, or ticket ID." }
            }
        }
        catch { if generation == current { matches = []; handle(error) } }
    }
    func toggle(_ attendee: Attendee) {
        guard !busy, can(.checkIn) else { return }
        pendingRequestID = nil
        if selection.contains(where: { $0.id == attendee.id }) { selection.removeAll { $0.id == attendee.id } }
        else if selection.count < batchLimit { selection.append(attendee) }
        else { message = "Review this batch before adding more attendees. Limit: \(batchLimit)." }
    }
    func scan(_ payload: String) async {
        guard let day, !busy, !confirming, can(.scanTickets), can(.checkIn), scanGate.accept(payload) else { return }
        busy = true; let current = generation
        defer { busy = false }
        do {
            let attendee = try await api.resolveQR(payload, day: day)
            guard generation == current else { return }
            if selection.contains(where: { $0.id == attendee.id }) { message = "This attendee is already in your batch." }
            else if selection.count >= batchLimit { message = "Review this batch before adding more attendees. Limit: \(batchLimit)." }
            else { pendingRequestID = nil; selection.append(attendee); message = "Added \(attendee.name) to the batch. Check-in is not yet confirmed." }
        } catch { if generation == current { handle(error) } }
    }
    func cancelBatch() { guard !busy else { return }; selection = []; confirming = false; scanGate.reset(); pendingRequestID = nil }
    func confirm() async {
        guard let day, !selection.isEmpty, !busy, can(.checkIn) else { return }
        confirming = false; busy = true; results = []; message = nil
        defer { busy = false }
        do {
            let requestID = pendingRequestID ?? UUID()
            pendingRequestID = requestID
            let response = try await api.checkIn(selection, day: day, requestID: requestID)
            // A partial or malformed server response must never be presented as a complete success.
            guard Set(response.map(\.id)) == Set(selection.map(\.id)), response.count == selection.count else {
                throw StaffError.offline
            }
            results = response; selection = []; scanGate.reset(); pendingRequestID = nil
        } catch { handle(error) }
    }
}
