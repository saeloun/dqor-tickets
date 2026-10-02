import Foundation

/// Built for mocked integration tests. DQORStaffApp still constructs DemoStaffAPI exclusively.
actor NativeStaffAPI: StaffAPI {
    private let configuration: NativeConfiguration
    private let transport: any NativeHTTPTransport
    private let storage: any NativeTokenStore
    private let now: @Sendable () -> Date
    private var credential: NativeCredential?
    private var scope: ScopeDTO?
    private var activeOperation: UUID?
    private var generation = UUID()
    init(configuration: NativeConfiguration = .disabled, transport: any NativeHTTPTransport,
         storage: any NativeTokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration; self.transport = transport; self.storage = storage; self.now = now
    }

    /// Future login UI may supply credentials for this call only; the API never retains a password.
    func authenticate(email: String, password: String) async throws -> StaffSession {
        let operation = try begin(); defer { finish(operation) }
        let origin = try configuration.validatedOrigin()
        let existing = try credential ?? storage.load()
        if let existing, existing.expiresAt > now() { throw NativeAPIError.sessionAlreadyActive }
        try clearLocal()
        let version = generation
        let response = try await request(path: "/api/staff/session", method: "POST", body: ["email": email, "password": password], version: version, expectedStatus: 201)
        guard response.status == 201 else { throw NativeAPIError.invalidResponse }
        let payload: SessionDTO = try decode(response.data)
        let scope = try validate(payload.scope)
        guard payload.tokenType == "Bearer", payload.accessToken.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw NativeAPIError.invalidResponse }
        let value = NativeCredential(token: payload.accessToken, expiresAt: try parseDate(scope.expiresAt), origin: origin.absoluteString)
        do { try storage.save(value) }
        catch {
            credential = nil; self.scope = nil
            _ = try? await request(path: "/api/staff/session", method: "DELETE", token: value.token, version: version, allowUnauthorized: true, expectedStatus: 204)
            throw NativeAPIError.secureStorage
        }
        credential = value; self.scope = scope
        return mappedSession(scope)
    }

    /// Restore only after server validation; persisted bytes alone never grant capabilities.
    func signIn() async throws -> StaffSession {
        let operation = try begin(); defer { finish(operation) }
        let origin = try configuration.validatedOrigin()
        guard let saved = try storage.load() else { throw StaffError.signedOut }
        guard saved.origin == origin.absoluteString, saved.expiresAt > now(),
              saved.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            try clearLocal(); throw StaffError.signedOut
        }
        credential = saved; scope = nil
        do {
            let response = try await request(path: "/api/staff/session", method: "GET", token: saved.token, version: generation)
            let payload: ScopeDTO = try decode(response.data)
            let fresh = try validate(payload)
            let value = NativeCredential(token: saved.token, expiresAt: try parseDate(fresh.expiresAt), origin: saved.origin)
            try storage.save(value); credential = value; scope = fresh
            return mappedSession(fresh)
        } catch {
            // An old operation must not erase a session established after logout/re-authentication.
            if activeOperation == operation { credential = nil; scope = nil }
            throw error
        }
    }

    func signOut() async throws {
        let hadPendingOperation = activeOperation != nil
        let operation = UUID(); activeOperation = operation; generation = UUID()
        defer { finish(operation) }
        var failedStorage = false
        var saved = credential
        if saved == nil { do { saved = try storage.load() } catch { failedStorage = true } }
        credential = nil; scope = nil
        do { try storage.clear() } catch { failedStorage = true }
        var revoked = saved == nil && !failedStorage && !hadPendingOperation
        if let saved, let origin = try? configuration.validatedOrigin(), saved.origin == origin.absoluteString {
            do {
                let response = try await request(path: "/api/staff/session", method: "DELETE", token: saved.token, version: generation, allowUnauthorized: true, expectedStatus: 204)
                revoked = response.status == 204 || response.status == 401
            } catch { revoked = false }
        }
        if failedStorage { throw NativeAPIError.secureStorage }
        guard revoked else { throw NativeAPIError.revocationUnconfirmed }
    }

    func eventDays() async throws -> [EventDay] {
        let operation = try begin(); defer { finish(operation) }
        let saved = try authorized()
        let response = try await request(path: "/api/staff/session", method: "GET", token: saved.token, version: generation)
        let payload: ScopeDTO = try decode(response.data)
        let fresh = try validate(payload)
        scope = fresh
        return fresh.eventDates.map { EventDay(id: $0, event: configuration.eventName, day: $0, theme: configuration.theme, maxBatchSize: fresh.maxBatchSize) }
    }

    func search(_ query: String, day: EventDay) async throws -> AttendeeSearchPage {
        let operation = try begin(); defer { finish(operation) }
        let saved = try authorized(capability: "tickets:read", day: day)
        let response = try await request(path: "/api/staff/checkins", method: "GET", query: [.init(name: "date", value: day.id), .init(name: "q", value: query)], token: saved.token, version: generation)
        let payload: SearchDTO = try decode(response.data)
        guard payload.date == day.id, payload.tickets.count <= 20, Set(payload.tickets.map(\.id.value)).count == payload.tickets.count else { throw NativeAPIError.invalidResponse }
        return AttendeeSearchPage(attendees: try payload.tickets.map(mappedTicket), moreResults: payload.moreResults)
    }

    func resolveQR(_ payload: String, day: EventDay) async throws -> Attendee {
        let operation = try begin(); defer { finish(operation) }
        guard !payload.isEmpty, payload.utf8.count <= 4096 else { throw StaffError.invalidTicket }
        let saved = try authorized(capability: "tickets:read", day: day)
        let response = try await request(path: "/api/staff/checkins/resolve", method: "POST", body: ["secret": payload, "date": day.id], token: saved.token, version: generation)
        let resolved: ResolveDTO = try decode(response.data)
        guard resolved.state == "resolved", resolved.date == day.id else { throw NativeAPIError.invalidResponse }
        return try mappedTicket(resolved.ticket)
    }

    func checkIn(_ attendees: [Attendee], day: EventDay, requestID: UUID) async throws -> [CheckInResult] {
        let operation = try begin(); defer { finish(operation) }
        let saved = try authorized(capability: "checkins:write", day: day)
        guard !attendees.isEmpty, attendees.count <= min(scope?.maxBatchSize ?? 0, day.maxBatchSize),
              Set(attendees.map(\.id)).count == attendees.count,
              attendees.allSatisfy({ TicketID.valid($0.id) }) else { throw NativeAPIError.rejected }
        // Rails uses ticket/day duplicate semantics. Do not invent an idempotency header or retry automatically.
        let response = try await request(path: "/api/staff/checkins/confirm", method: "POST", body: ["ticket_ids": attendees.map(\.id), "date": day.id, "confirmed": true], token: saved.token, version: generation)
        let payload: ConfirmationDTO = try decode(response.data)
        guard payload.date == day.id, payload.results.count == attendees.count,
              Set(payload.results.map(\.ticketID.value)) == Set(attendees.map(\.id)) else { throw NativeAPIError.invalidResponse }
        let results = Dictionary(uniqueKeysWithValues: payload.results.map { ($0.ticketID.value, $0) })
        return try attendees.map { attendee in
            guard let result = results[attendee.id] else { throw NativeAPIError.invalidResponse }
            let outcome: CheckInOutcome
            switch (result.code, result.state) {
            case ("success", "success"):
                guard let timestamp = result.checkedInAt, result.attendee?.isEmpty == false else { throw NativeAPIError.invalidResponse }
                _ = try parseDate(timestamp); outcome = .checkedIn
            case ("duplicate", "warning"):
                guard result.attendee?.isEmpty == false else { throw NativeAPIError.invalidResponse }
                outcome = .duplicate
            case ("not_found", "error"): outcome = .invalid
            case ("unconfirmed", "error"): outcome = .unconfirmed
            case ("wrong_date", "error"): outcome = .ineligible
            case ("canceled", "error"): outcome = .canceled
            default: throw NativeAPIError.invalidResponse
            }
            return CheckInResult(attendee: attendee, outcome: outcome)
        }
    }

    private func begin() throws -> UUID {
        _ = try configuration.validatedOrigin()
        guard activeOperation == nil else { throw NativeAPIError.requestInProgress }
        let value = UUID(); activeOperation = value; return value
    }
    private func finish(_ operation: UUID) { if activeOperation == operation { activeOperation = nil } }
    private func clearLocal() throws { generation = UUID(); credential = nil; scope = nil; try storage.clear() }
    private func authorized(capability: String? = nil, day: EventDay? = nil) throws -> NativeCredential {
        guard let credential, let scope else { throw StaffError.signedOut }
        guard credential.expiresAt > now(), (try parseDate(scope.expiresAt)) > now() else { try clearLocal(); throw StaffError.signedOut }
        if let capability, !scope.capabilities.contains(capability) { throw StaffError.forbidden }
        if let day, (!scope.eventDates.contains(day.id) || day.event != configuration.eventName) { throw StaffError.forbidden }
        return credential
    }
    private func request(path: String, method: String, query: [URLQueryItem] = [], body: [String: Any]? = nil,
                         token: String? = nil, version: UUID, allowUnauthorized: Bool = false, expectedStatus: Int = 200) async throws -> NativeHTTPResponse {
        let origin = try configuration.validatedOrigin()
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        components.path = path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw NativeAPIError.invalidConfiguration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let response: NativeHTTPResponse
        do { response = try await transport.send(request) }
        catch { guard generation == version else { throw NativeAPIError.sessionChanged }; throw StaffError.offline }
        guard generation == version else { throw NativeAPIError.sessionChanged }
        guard response.url == url, response.data.count <= 1_048_576 else { throw NativeAPIError.invalidResponse }
        if response.status == 401 {
            if allowUnauthorized { return response }
            try clearLocal(); throw StaffError.signedOut
        }
        if response.status == 403 { try clearLocal(); throw StaffError.forbidden }
        if response.status == 404 { throw path.hasSuffix("/resolve") ? StaffError.invalidTicket : NativeAPIError.unavailable }
        if response.status == 422 { throw NativeAPIError.rejected }
        if response.status == 429 { throw NativeAPIError.rateLimited }
        if response.status >= 500 { throw NativeAPIError.unavailable }
        guard response.status == expectedStatus else { throw NativeAPIError.invalidResponse }
        return response
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return try decoder.decode(T.self, from: data) }
        catch { throw NativeAPIError.invalidResponse }
    }
    private func validate(_ scope: ScopeDTO) throws -> ScopeDTO {
        guard scope.event == configuration.eventID, !scope.eventDates.isEmpty,
              Set(scope.eventDates).count == scope.eventDates.count,
              scope.eventDates.allSatisfy(validDay), (1...50).contains(scope.maxBatchSize) else { throw NativeAPIError.invalidResponse }
        guard try parseDate(scope.expiresAt) > now() else { try clearLocal(); throw StaffError.signedOut }
        return scope
    }
    private func mappedSession(_ scope: ScopeDTO) -> StaffSession {
        var capabilities: Set<StaffCapability> = []
        if scope.capabilities.contains("tickets:read") { capabilities.formUnion([.searchAttendees, .scanTickets]) }
        if scope.capabilities.contains("checkins:write") { capabilities.insert(.checkIn) }
        return StaffSession(displayName: "Staff", capabilities: capabilities)
    }
    private func mappedTicket(_ dto: TicketDTO) throws -> Attendee {
        if let timestamp = dto.checkedInAt { _ = try parseDate(timestamp) }
        return Attendee(id: dto.id.value, name: dto.attendeeName?.isEmpty == false ? dto.attendeeName! : "Ticket #\(dto.id.value)", email: dto.attendeeEmail ?? "", eligible: dto.eligible, checkedInAt: dto.checkedInAt)
    }
    private func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw NativeAPIError.invalidResponse }
        return date
    }
    private func validDay(_ value: String) -> Bool {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

private struct ScopeDTO: Decodable {
    let event: String; let eventDates: [String]; let capabilities: [String]; let expiresAt: String; let maxBatchSize: Int
}
private struct SessionDTO: Decodable {
    let accessToken: String; let tokenType: String; let scope: ScopeDTO
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        scope = try ScopeDTO(from: decoder)
    }
    enum CodingKeys: String, CodingKey { case accessToken, tokenType }
}
private struct TicketID: Decodable {
    let value: String
    static func valid(_ value: String) -> Bool { value.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil && Int64(value) != nil }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value: String
        if let string = try? container.decode(String.self) { value = string }
        else { value = String(try container.decode(Int64.self)) }
        guard Self.valid(value) else { throw NativeAPIError.invalidResponse }; self.value = value
    }
}
private struct TicketDTO: Decodable {
    let id: TicketID; let attendeeName: String?; let attendeeEmail: String?; let eligible: Bool; let checkedInAt: String?
}
private struct SearchDTO: Decodable { let date: String; let moreResults: Bool; let tickets: [TicketDTO] }
private struct ResolveDTO: Decodable { let state: String; let date: String; let ticket: TicketDTO }
private struct ResultDTO: Decodable {
    let ticketId: TicketID; let code: String; let state: String; let attendee: String?; let checkedInAt: String?
    var ticketID: TicketID { ticketId }
}
private struct ConfirmationDTO: Decodable { let date: String; let results: [ResultDTO] }
