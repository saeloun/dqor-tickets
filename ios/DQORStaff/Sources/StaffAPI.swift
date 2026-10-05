import Foundation

enum StaffCapability: String, Hashable, Sendable { case searchAttendees, scanTickets, checkIn }
enum DemoRole: String, CaseIterable, Sendable {
    case owner, admin, organizer, teamLead, volunteer, finance, av
    var capabilities: Set<StaffCapability> {
        switch self {
        case .owner, .admin, .organizer, .teamLead, .volunteer: [.searchAttendees, .scanTickets, .checkIn]
        case .finance, .av: []
        }
    }
}
struct StaffSession: Equatable, Sendable {
    let displayName: String
    let capabilities: Set<StaffCapability>
}
enum EventTheme: String, Sendable { case indigo, forest, ember }
struct EventDay: Identifiable, Hashable, Sendable {
    let id: String
    let event: String
    let day: String
    let theme: EventTheme
    let maxBatchSize: Int
    init(id: String, event: String, day: String, theme: EventTheme = .indigo, maxBatchSize: Int = 50) {
        self.id = id; self.event = event; self.day = day; self.theme = theme
        self.maxBatchSize = min(50, max(1, maxBatchSize))
    }
}
struct Attendee: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    let eligible: Bool?
    let checkedInAt: String?
    init(id: String, name: String, email: String, eligible: Bool? = nil, checkedInAt: String? = nil) {
        self.id = id; self.name = name; self.email = email; self.eligible = eligible; self.checkedInAt = checkedInAt
    }
}
struct AttendeeSearchPage: Sendable {
    let attendees: [Attendee]
    let moreResults: Bool
    init(attendees: [Attendee], moreResults: Bool = false) { self.attendees = attendees; self.moreResults = moreResults }
}
enum CheckInOutcome: String, Sendable {
    case checkedIn, duplicate, ineligible, invalid, unconfirmed, canceled
    var label: String {
        switch self {
        case .checkedIn: "Checked in"
        case .duplicate: "Already checked in"
        case .ineligible: "Not eligible for this day"
        case .invalid: "Ticket not found"
        case .unconfirmed: "Order not confirmed · do not admit"
        case .canceled: "Ticket canceled · do not admit"
        }
    }
}
struct CheckInResult: Identifiable, Sendable {
    let attendee: Attendee
    let outcome: CheckInOutcome
    var id: String { attendee.id }
}
enum StaffError: Error, LocalizedError, Equatable {
    case offline, invalidTicket, signedOut, forbidden
    var errorDescription: String? {
        switch self {
        case .offline: "Connection unavailable. Check-in was not confirmed. Check the attendee status before retrying."
        case .invalidTicket: "Ticket not recognized. Try attendee search or ask an administrator."
        case .signedOut: "Your session has ended. Sign in again."
        case .forbidden: "Your staff role does not have access to this action."
        }
    }
}
/// Production authentication and wire mapping must be supplied only after the Rails contract is verified.
protocol StaffAPI: Sendable {
    func signIn() async throws -> StaffSession
    func signOut() async throws
    func eventDays() async throws -> [EventDay]
    func search(_ query: String, day: EventDay) async throws -> AttendeeSearchPage
    func resolveQR(_ payload: String, day: EventDay) async throws -> Attendee
    func checkIn(_ attendees: [Attendee], day: EventDay, requestID: UUID) async throws -> [CheckInResult]
}

actor DemoStaffAPI: StaffAPI {
    static let days = [EventDay(id: "day-1", event: "DQOR Demo Conference", day: "Day 1 · October 2"),
                       EventDay(id: "day-2", event: "DQOR Demo Conference", day: "Day 2 · October 3"),
                       EventDay(id: "community-1", event: "Community Gathering · Demo", day: "Main event · October 10", theme: .forest),
                       EventDay(id: "workshop-1", event: "Design Workshop · Demo", day: "Workshop · October 12", theme: .ember)]
    static let attendees = [Attendee(id: "demo-001", name: "Alex Morgan", email: "alex@example.test"),
                            Attendee(id: "demo-002", name: "Sam Rivera", email: "sam@example.test"),
                            Attendee(id: "demo-003", name: "Taylor Chen", email: "taylor@example.test")]
    private var session = false
    private var checked: Set<String> = []
    private var responses: [UUID: [CheckInResult]] = [:]
    private let offline: Bool
    private let failCheckIn: Bool
    private let role: DemoRole
    private let roster: [Attendee]
    init(offline: Bool = false, failCheckIn: Bool = false, role: DemoRole = .volunteer, duplicateNames: Bool = false) {
        self.offline = offline; self.failCheckIn = failCheckIn; self.role = role
        roster = Self.attendees + (duplicateNames ? [Attendee(id: "demo-004", name: "Alex Morgan", email: "alex.second@example.test")] : [])
    }
    func signIn() async throws -> StaffSession { session = true; return StaffSession(displayName: "Demo \(role.rawValue)", capabilities: role.capabilities) }
    func signOut() async { session = false }
    private func authorize(_ capability: StaffCapability? = nil) throws {
        if !session { throw StaffError.signedOut }
        if let capability, !role.capabilities.contains(capability) { throw StaffError.forbidden }
    }
    func eventDays() async throws -> [EventDay] { try authorize(); return Self.days }
    func search(_ query: String, day: EventDay) async throws -> AttendeeSearchPage {
        try authorize(.searchAttendees)
        if offline { throw StaffError.offline }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return AttendeeSearchPage(attendees: roster.filter { query.isEmpty || "\($0.name) \($0.email) \($0.id)".localizedCaseInsensitiveContains(query) })
    }
    func resolveQR(_ payload: String, day: EventDay) async throws -> Attendee {
        try authorize(.scanTickets)
        if offline { throw StaffError.offline }
        guard let attendee = roster.first(where: { "dqor-demo:\($0.id)" == payload }) else { throw StaffError.invalidTicket }
        return attendee
    }
    func checkIn(_ attendees: [Attendee], day: EventDay, requestID: UUID) async throws -> [CheckInResult] {
        try authorize(.checkIn)
        if offline || failCheckIn { throw StaffError.offline }
        if let existing = responses[requestID] { return existing }
        let results = attendees.map { attendee in
            let key = "\(day.id)/\(attendee.id)"
            let outcome: CheckInOutcome
            if !roster.contains(attendee) { outcome = .invalid }
            else if attendee.id == "demo-003" && day.id == "day-1" { outcome = .ineligible }
            else if checked.contains(key) { outcome = .duplicate }
            else { checked.insert(key); outcome = .checkedIn }
            return CheckInResult(attendee: attendee, outcome: outcome)
        }
        responses[requestID] = results
        return results
    }
}

/// Keeps raw ticket payloads out of logs and persistence. Repeated camera frames are suppressed.
struct ScanGate {
    private var lastPayload: String?
    private var lastTime = Date.distantPast
    mutating func accept(_ payload: String, now: Date = Date()) -> Bool {
        guard !payload.isEmpty, payload.utf8.count <= 4096 else { return false }
        guard payload != lastPayload || now.timeIntervalSince(lastTime) >= 3 else { return false }
        lastPayload = payload; lastTime = now
        return true
    }
    mutating func reset() { lastPayload = nil; lastTime = .distantPast }
}
