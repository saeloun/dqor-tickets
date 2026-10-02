import XCTest
import Security
@testable import DQORStaff

private let fixtureToken = String(repeating: "A", count: 43)
private let fixtureOrigin = URL(string: "https://staff.example.test")!
private let fixtureNow = ISO8601DateFormatter().date(from: "2026-10-02T21:00:00Z")!
private let fixtureExpiry = "2026-10-03T04:00:00Z"
private func scopeFixture() -> [String: Any] {
    ["event": "dqor-2026", "event_dates": ["2026-10-08"], "capabilities": ["tickets:read", "checkins:write"], "expires_at": fixtureExpiry, "max_batch_size": 50]
}
private func sessionFixture() -> [String: Any] { scopeFixture().merging(["access_token": fixtureToken, "token_type": "Bearer"]) { _, new in new } }
private func ticketFixture(_ id: Int = 1, eligible: Bool = true) -> [String: Any] {
    ["id": id, "attendee_name": "Synthetic Attendee", "attendee_email": "attendee@example.test", "eligible": eligible, "checked_in_at": NSNull()]
}
private func savedFixture(origin: String = fixtureOrigin.absoluteString, expires: Date = fixtureNow.addingTimeInterval(3600)) -> NativeCredential {
    NativeCredential(token: fixtureToken, expiresAt: expires, origin: origin)
}
private struct Reply: @unchecked Sendable {
    let status: Int
    let body: [String: Any]
    var url: URL? = nil
    var fail = false
}
private actor MockNativeTransport: NativeHTTPTransport {
    var requests: [URLRequest] = []
    var replies: [Reply]
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> NativeHTTPResponse {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = replies.removeFirst()
        if reply.fail { throw URLError(.timedOut) }
        return NativeHTTPResponse(status: reply.status, url: reply.url ?? request.url!, data: try JSONSerialization.data(withJSONObject: reply.body))
    }
}
private final class MemoryTokenStore: NativeTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: NativeCredential?
    let failSave: Bool
    init(_ value: NativeCredential? = nil, failSave: Bool = false) { self.value = value; self.failSave = failSave }
    func load() throws -> NativeCredential? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ value: NativeCredential) throws { lock.lock(); defer { lock.unlock() }; if failSave { throw NativeAPIError.secureStorage }; self.value = value }
    func clear() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}

@MainActor
final class NativeAPITests: XCTestCase {
    private let day = EventDay(id: "2026-10-08", event: "DQOR 2026", day: "2026-10-08")
    private func api(_ transport: any NativeHTTPTransport, storage: any NativeTokenStore = MemoryTokenStore(), config: NativeConfiguration? = nil) -> NativeStaffAPI {
        NativeStaffAPI(configuration: config ?? NativeConfiguration(origin: fixtureOrigin, enabled: true), transport: transport, storage: storage, now: { fixtureNow })
    }
    private func assertNativeError(_ expected: NativeAPIError, _ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected sanitized failure", file: file, line: line) }
        catch { XCTAssertEqual(error as? NativeAPIError, expected, file: file, line: line) }
    }
    func testDisabledConfigurationNeverSendsCredentials() async {
        let transport = MockNativeTransport([])
        let api = api(transport, config: .disabled)
        await assertNativeError(.disabled) { _ = try await api.authenticate(email: "sample@example.test", password: "synthetic-password") }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testUnsafeOriginsAreRejectedWithoutTransport() async {
        for text in ["http://staff.example.test", "https://user:pass@staff.example.test", "https://staff.example.test/path", "https://staff.example.test?q=secret", "https://staff.example.test#fragment"] {
            let transport = MockNativeTransport([]); let api = api(transport, config: NativeConfiguration(origin: URL(string: text), enabled: true))
            await assertNativeError(.invalidConfiguration) { _ = try await api.signIn() }
            let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        }
    }
    func testAuthenticationPersistsOnlyScopedTokenAndUsesJSONBody() async throws {
        let transport = MockNativeTransport([Reply(status: 201, body: sessionFixture())]); let storage = MemoryTokenStore(); let api = api(transport, storage: storage)
        let session = try await api.authenticate(email: "sample@example.test", password: "synthetic-password")
        XCTAssertEqual(session.capabilities, [.searchAttendees, .scanTickets, .checkIn])
        let requests = await transport.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/api/staff/session"); XCTAssertNil(request.url?.query)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertFalse(request.httpShouldHandleCookies)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        XCTAssertEqual(body["password"], "synthetic-password")
        let credential = try XCTUnwrap(storage.load()); XCTAssertEqual(credential.token, fixtureToken)
        let encoded = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
        XCTAssertFalse(encoded.contains("synthetic-password")); XCTAssertFalse(encoded.contains("sample@example.test"))
        XCTAssertFalse(String(describing: credential).contains(fixtureToken))
    }
    func testMalformedAuthenticationNeverPersistsSession() async {
        var bad = sessionFixture(); bad["event"] = "other-event"
        let storage = MemoryTokenStore(); let api = api(MockNativeTransport([Reply(status: 201, body: bad)]), storage: storage)
        await assertNativeError(.invalidResponse) { _ = try await api.authenticate(email: "x", password: "x") }
        XCTAssertNil(try storage.load())
    }
    func testStorageFailureAttemptsRevocationAndDoesNotAuthenticate() async {
        let transport = MockNativeTransport([Reply(status: 201, body: sessionFixture()), Reply(status: 204, body: [:])])
        let api = api(transport, storage: MemoryTokenStore(failSave: true))
        await assertNativeError(.secureStorage) { _ = try await api.authenticate(email: "x", password: "x") }
        let requests = await transport.requests; XCTAssertEqual(requests.map(\.httpMethod), ["POST", "DELETE"])
        do { _ = try await api.eventDays(); XCTFail("No authenticated state") } catch { XCTAssertEqual(error as? StaffError, .signedOut) }
    }
    func testRestoreRequiresServerScopeAndDoesNotRepeatTokenInResponse() async throws {
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: scopeFixture())]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
        let session = try await api.signIn(); let days = try await api.eventDays()
        XCTAssertTrue(session.capabilities.contains(.checkIn)); XCTAssertEqual(days.map(\.id), ["2026-10-08"])
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.httpMethod, "GET"); XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer \(fixtureToken)")
        XCTAssertNil(requests.first?.httpBody)
    }
    func testExpiredOrWrongOriginCredentialsAreErasedWithoutNetwork() async {
        for saved in [savedFixture(expires: fixtureNow), savedFixture(origin: "https://different.example.test")] {
            let storage = MemoryTokenStore(saved); let transport = MockNativeTransport([]); let api = api(transport, storage: storage)
            do { _ = try await api.signIn(); XCTFail("Must reauthenticate") } catch { XCTAssertEqual(error as? StaffError, .signedOut) }
            XCTAssertNil(try storage.load()); let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        }
    }
    func test401And403ClearTokenAndCapabilities() async throws {
        for status in [401, 403] {
            let storage = MemoryTokenStore(savedFixture()); let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: status, body: [:])]); let api = api(transport, storage: storage)
            _ = try await api.signIn()
            do { _ = try await api.search("name", day: day); XCTFail("Revoked session") }
            catch { XCTAssertEqual(error as? StaffError, status == 401 ? .signedOut : .forbidden) }
            XCTAssertNil(try storage.load())
            do { _ = try await api.search("name", day: day); XCTFail("No local scope remains") } catch { XCTAssertEqual(error as? StaffError, .signedOut) }
        }
    }
    func testResolveIsNonmutatingAndPreservesEligibility() async throws {
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["state": "resolved", "date": day.id, "ticket": ticketFixture(eligible: false)])]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
        _ = try await api.signIn(); let attendee = try await api.resolveQR("synthetic-qr-secret", day: day)
        XCTAssertEqual(attendee.eligible, false)
        let requests = await transport.requests; let request = requests.last!
        XCTAssertEqual(request.url?.path, "/api/staff/checkins/resolve"); XCTAssertNil(request.url?.query)
        XCTAssertFalse(request.url!.absoluteString.contains("synthetic-qr-secret"))
        XCTAssertFalse(requests.contains { $0.url?.path == "/checkin" || $0.url?.path.hasSuffix("/confirm") == true })
    }
    func testSearchMoreResultsAndCanonicalDateAreValidated() async throws {
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "more_results": true, "tickets": [ticketFixture()]]), Reply(status: 200, body: ["date": "2026-10-09", "more_results": false, "tickets": []])]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
        _ = try await api.signIn(); let page = try await api.search("name & other", day: day)
        XCTAssertTrue(page.moreResults); XCTAssertEqual(page.attendees.first?.id, "1")
        await assertNativeError(.invalidResponse) { _ = try await api.search("other", day: day) }
    }
    func testMixedConfirmationResultsMapByStableIDWithoutMessageParsing() async throws {
        let results: [[String: Any]] = [
            ["ticket_id": "2", "code": "duplicate", "state": "warning", "attendee": "Sample", "message": "Localized prose"],
            ["ticket_id": 1, "code": "success", "state": "success", "attendee": "Sample", "checked_in_at": "2026-10-08T09:00:00.123Z"],
            ["ticket_id": "3", "code": "unconfirmed", "state": "error", "message": "Checked in"],
            ["ticket_id": "4", "code": "not_found", "state": "error", "attendee": "Sample", "message": "Localized prose"],
            ["ticket_id": "5", "code": "wrong_date", "state": "error", "message": "Localized prose"],
            ["ticket_id": "6", "code": "canceled", "state": "error", "message": "Localized prose"]]
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "results": results])]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
        _ = try await api.signIn()
        let attendees = (1...6).map { Attendee(id: String($0), name: "Synthetic", email: "sample@example.test") }
        let response = try await api.checkIn(attendees, day: day, requestID: UUID())
        XCTAssertEqual(response.map(\.outcome), [.checkedIn, .duplicate, .unconfirmed, .invalid, .ineligible, .canceled])
        let requests = await transport.requests; let request = requests.last!
        XCTAssertEqual(request.url?.path, "/api/staff/checkins/confirm")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["confirmed"] as? Bool, true); XCTAssertEqual(body["ticket_ids"] as? [String], ["1", "2", "3", "4", "5", "6"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
    }
    func testIncompleteUnknownAndTimestampFreeSuccessFailClosed() async throws {
        let malformed: [[[String: Any]]] = [[], [["ticket_id": "1", "code": "success", "state": "success", "attendee": "Sample"]], [["ticket_id": "1", "code": "success", "state": "unknown"]], [["ticket_id": "999", "code": "duplicate", "state": "warning", "attendee": "Sample"]]]
        for results in malformed {
            let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "results": results])]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
            _ = try await api.signIn()
            await assertNativeError(.invalidResponse) { _ = try await api.checkIn([Attendee(id: "1", name: "Sample", email: "sample@example.test")], day: day, requestID: UUID()) }
        }
    }

    func testMissingUnknownNullAndNonStringCodesFailClosed() async throws {
        let badCodes: [Any?] = [nil, "future_code", NSNull(), 42, "SUCCESS", ""]
        for code in badCodes {
            var result: [String: Any] = ["ticket_id": "1", "state": "success", "attendee": "Sample", "checked_in_at": "2026-10-08T09:00:00Z", "message": "Checked in"]
            if let code { result["code"] = code }
            let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "results": [result]])])
            let api = api(transport, storage: MemoryTokenStore(savedFixture()))
            _ = try await api.signIn()
            await assertNativeError(.invalidResponse) { _ = try await api.checkIn([Attendee(id: "1", name: "Sample", email: "sample@example.test")], day: day, requestID: UUID()) }
        }
    }
    func testEveryMismatchedCodeStatePairFailsClosed() async throws {
        let expectedStates = ["success": "success", "duplicate": "warning", "not_found": "error", "unconfirmed": "error", "wrong_date": "error", "canceled": "error"]
        for (code, expected) in expectedStates {
            for state in ["success", "warning", "error", "future_state"] where state != expected {
                let result: [String: Any] = ["ticket_id": "1", "code": code, "state": state, "attendee": "Sample", "checked_in_at": "2026-10-08T09:00:00Z", "message": "Checked in"]
                let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "results": [result]])])
                let api = api(transport, storage: MemoryTokenStore(savedFixture()))
                _ = try await api.signIn()
                await assertNativeError(.invalidResponse) { _ = try await api.checkIn([Attendee(id: "1", name: "Sample", email: "sample@example.test")], day: day, requestID: UUID()) }
            }
        }
    }
    func testUnverifiedCodeInMixedBatchPublishesNoSuccess() async {
        let results: [[String: Any]] = [
            ["ticket_id": "1", "code": "success", "state": "success", "attendee": "Sample", "checked_in_at": "2026-10-08T09:00:00Z"],
            ["ticket_id": "2", "code": "future_code", "state": "success", "attendee": "Sample", "checked_in_at": "2026-10-08T09:00:00Z"]]
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "results": results])])
        let store = StaffStore(api: api(transport, storage: MemoryTokenStore(savedFixture())))
        await store.signIn(); store.choose(day)
        for id in ["1", "2"] { store.toggle(Attendee(id: id, name: "Sample", email: "sample@example.test")) }
        await store.confirm()
        XCTAssertTrue(store.results.isEmpty); XCTAssertEqual(store.selection.count, 2)
        XCTAssertTrue(store.message?.contains("not confirmed") == true)
        XCTAssertTrue(store.message?.contains("administrator") == true)
    }
    func testResponseOriginAndRedirectStatusAreRejected() async throws {
        for reply in [Reply(status: 200, body: scopeFixture(), url: URL(string: "https://other.example.test/api/staff/session")), Reply(status: 302, body: [:])] {
            let api = api(MockNativeTransport([reply]), storage: MemoryTokenStore(savedFixture()))
            await assertNativeError(.invalidResponse) { _ = try await api.signIn() }
        }
    }
    func testNetworkFailureDoesNotAutomaticallyRetryOrReturnSuccess() async throws {
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: [:], fail: true)]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
        _ = try await api.signIn()
        do { _ = try await api.checkIn([Attendee(id: "1", name: "Sample", email: "sample@example.test")], day: day, requestID: UUID()); XCTFail("Unknown attendance outcome") }
        catch { XCTAssertEqual(error as? StaffError, .offline); XCTAssertTrue(error.localizedDescription.contains("not confirmed")) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testLogoutClearsLocalTokenEvenWhenRevocationFails() async throws {
        for fails in [false, true] {
            let storage = MemoryTokenStore(savedFixture()); let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 204, body: [:], fail: fails)]); let api = api(transport, storage: storage)
            _ = try await api.signIn()
            if fails { await assertNativeError(.revocationUnconfirmed) { try await api.signOut() } }
            else { try await api.signOut() }
            XCTAssertNil(try storage.load())
            do { _ = try await api.signIn(); XCTFail("Token removed") } catch { XCTAssertEqual(error as? StaffError, .signedOut) }
        }
    }
    func testDisabledLogoutStillErasesLocalCredentials() async {
        let storage = MemoryTokenStore(savedFixture()); let transport = MockNativeTransport([]); let api = api(transport, storage: storage, config: .disabled)
        await assertNativeError(.revocationUnconfirmed) { try await api.signOut() }
        XCTAssertNil(try storage.load()); let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }

    func testActiveSessionMustBeSignedOutBeforeReauthentication() async {
        let storage = MemoryTokenStore(savedFixture()); let transport = MockNativeTransport([]); let api = api(transport, storage: storage)
        await assertNativeError(.sessionAlreadyActive) { _ = try await api.authenticate(email: "new@example.test", password: "synthetic") }
        XCTAssertNotNil(try storage.load()); let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testServerReportedExpiryRemovesSavedSession() async {
        var expired = scopeFixture(); expired["expires_at"] = "2026-10-02T20:00:00Z"
        let storage = MemoryTokenStore(savedFixture()); let api = api(MockNativeTransport([Reply(status: 200, body: expired)]), storage: storage)
        do { _ = try await api.signIn(); XCTFail("Expired") } catch { XCTAssertEqual(error as? StaffError, .signedOut) }
        XCTAssertNil(try storage.load())
    }
    func testURLSessionPolicyDisablesAmbientCredentialsCookiesAndCaching() {
        let policy = EphemeralNativeTransport.secureConfiguration()
        XCTAssertNil(policy.httpCookieStorage); XCTAssertNil(policy.urlCredentialStorage); XCTAssertNil(policy.urlCache)
        XCTAssertFalse(policy.httpShouldSetCookies); XCTAssertFalse(policy.waitsForConnectivity)
        XCTAssertEqual(policy.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(policy.timeoutIntervalForResource, 30)
    }
    func testExpiryDuringSessionClearsTokenWithoutAnotherRequest() async throws {
        let clock = FixtureClock(fixtureNow)
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture())])
        let storage = MemoryTokenStore(savedFixture())
        let api = NativeStaffAPI(configuration: NativeConfiguration(origin: fixtureOrigin, enabled: true), transport: transport, storage: storage, now: { clock.read() })
        _ = try await api.signIn(); clock.advance(9 * 3600)
        do { _ = try await api.search("sample", day: day); XCTFail("Expired") } catch { XCTAssertEqual(error as? StaffError, .signedOut) }
        XCTAssertNil(try storage.load()); let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testServerCapabilitiesAndDatesCannotBeOverriddenByClient() async throws {
        var scope = scopeFixture(); scope["capabilities"] = ["tickets:read", "unknown:capability"]
        let transport = MockNativeTransport([Reply(status: 200, body: scope)]); let api = api(transport, storage: MemoryTokenStore(savedFixture()))
        let session = try await api.signIn(); XCTAssertFalse(session.capabilities.contains(.checkIn))
        do { _ = try await api.checkIn([Attendee(id: "1", name: "Sample", email: "sample@example.test")], day: day, requestID: UUID()); XCTFail("No write capability") }
        catch { XCTAssertEqual(error as? StaffError, .forbidden) }
        do { _ = try await api.search("sample", day: EventDay(id: "2026-10-09", event: "DQOR 2026", day: "Day 2")); XCTFail("No day scope") }
        catch { XCTAssertEqual(error as? StaffError, .forbidden) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testLogoutRejectsLateReadResponse() async throws {
        let transport = GatedNativeTransport(initial: [Reply(status: 200, body: scopeFixture())])
        let storage = MemoryTokenStore(savedFixture()); let api = api(transport, storage: storage)
        _ = try await api.signIn()
        let pending = Task { try await api.resolveQR("synthetic", day: day) }
        await transport.waitUntilBlocked()
        try await api.signOut()
        try await transport.complete(Reply(status: 200, body: ["state": "resolved", "date": day.id, "ticket": ticketFixture()]))
        do { _ = try await pending.value; XCTFail("Late response must be rejected") } catch { XCTAssertEqual(error as? NativeAPIError, .sessionChanged) }
        XCTAssertNil(try storage.load())
    }
    func testLogoutDuringLoginCannotClaimRevocationOrResurrectToken() async throws {
        let transport = GatedNativeTransport(initial: []); let storage = MemoryTokenStore(); let api = api(transport, storage: storage)
        let pending = Task { try await api.authenticate(email: "synthetic@example.test", password: "synthetic-password") }
        await transport.waitUntilBlocked()
        await assertNativeError(.revocationUnconfirmed) { try await api.signOut() }
        try await transport.complete(Reply(status: 201, body: sessionFixture()))
        do { _ = try await pending.value; XCTFail("Late login cannot persist") } catch { XCTAssertEqual(error as? NativeAPIError, .sessionChanged) }
        XCTAssertNil(try storage.load())
    }
    func testStoreClearsAttendeeStateWhenServerRevokesSession() async {
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: scopeFixture()), Reply(status: 401, body: [:])])
        let store = StaffStore(api: api(transport, storage: MemoryTokenStore(savedFixture())))
        await store.signIn(); store.choose(day); store.toggle(Attendee(id: "1", name: "Sample", email: "sample@example.test"))
        await store.search("sample")
        XCTAssertNil(store.session); XCTAssertNil(store.day); XCTAssertTrue(store.selection.isEmpty); XCTAssertTrue(store.matches.isEmpty)
        XCTAssertTrue(store.message?.contains("Sign in again") == true)
    }
    func testStoreShowsBoundedSearchNoticeWithoutImplicitSelection() async {
        let transport = MockNativeTransport([Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: scopeFixture()), Reply(status: 200, body: ["date": day.id, "more_results": true, "tickets": [ticketFixture()]])])
        let store = StaffStore(api: api(transport, storage: MemoryTokenStore(savedFixture())))
        await store.signIn(); store.choose(day); await store.search("sample")
        XCTAssertEqual(store.matches.count, 1); XCTAssertTrue(store.selection.isEmpty)
        XCTAssertTrue(store.message?.contains("Refine the search") == true)
    }

}

private final class KeychainSpy: KeychainClient, @unchecked Sendable {
    var stored: Data?
    var added: [String: Any] = [:]
    var deleted = false
    var locked = false
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) { locked ? (errSecInteractionNotAllowed, nil) : (stored == nil ? errSecItemNotFound : errSecSuccess, stored) }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus { errSecItemNotFound }
    func add(_ attributes: [String: Any]) -> OSStatus { added = attributes; stored = attributes[kSecValueData as String] as? Data; return errSecSuccess }
    func delete(_ query: [String: Any]) -> OSStatus { deleted = true; stored = nil; return errSecSuccess }
}
final class NativeKeychainTests: XCTestCase {
    func testProtectionPolicyAndRoundTripUseInjectedKeychainOnly() throws {
        let spy = KeychainSpy(); let store = KeychainNativeTokenStore(service: "test-native-only", client: spy)
        try store.save(savedFixture())
        XCTAssertEqual(spy.added[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(spy.added[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertNil(spy.added[kSecAttrAccessGroup as String])
        XCTAssertEqual(try store.load()?.token, fixtureToken)
        try store.clear(); XCTAssertNil(try store.load()); XCTAssertTrue(spy.deleted)
    }
    func testLockedAndCorruptStorageFailClosed() throws {
        let spy = KeychainSpy(); let store = KeychainNativeTokenStore(service: "test-native-only", client: spy)
        spy.locked = true
        XCTAssertThrowsError(try store.load())
        spy.locked = false; spy.stored = Data("corrupt fixture".utf8)
        XCTAssertThrowsError(try store.load()); XCTAssertTrue(spy.deleted)
    }
}

private final class FixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value = value.addingTimeInterval(seconds) }
}
private actor GatedNativeTransport: NativeHTTPTransport {
    private var initial: [Reply]
    private var didBlock = false
    private var blockedRequest: URLRequest?
    private var responseContinuation: CheckedContinuation<NativeHTTPResponse, Error>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    init(initial: [Reply]) { self.initial = initial }
    func send(_ request: URLRequest) async throws -> NativeHTTPResponse {
        if !initial.isEmpty {
            let reply = initial.removeFirst()
            return NativeHTTPResponse(status: reply.status, url: request.url!, data: try JSONSerialization.data(withJSONObject: reply.body))
        }
        if !didBlock {
            didBlock = true; blockedRequest = request
            startContinuation?.resume(); startContinuation = nil
            return try await withCheckedThrowingContinuation { responseContinuation = $0 }
        }
        return NativeHTTPResponse(status: 204, url: request.url!, data: Data())
    }
    func waitUntilBlocked() async {
        if didBlock { return }
        await withCheckedContinuation { startContinuation = $0 }
    }
    func complete(_ reply: Reply) throws {
        let data = try JSONSerialization.data(withJSONObject: reply.body)
        responseContinuation?.resume(returning: NativeHTTPResponse(status: reply.status, url: blockedRequest!.url!, data: data))
        responseContinuation = nil
    }
}
