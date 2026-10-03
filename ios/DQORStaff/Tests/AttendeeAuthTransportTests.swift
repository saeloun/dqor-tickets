import XCTest
@testable import DQORStaff

final class AttendeeWireState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var body = Data()
    private var headers = ["Content-Type": "application/json", "Cache-Control": "private, no-store"]
    private var replyURL: URL?
    private var requests: [URLRequest] = []
    func set(status: Int = 200, body: Data = Data(), headers: [String: String] = ["Content-Type": "application/json", "Cache-Control": "private, no-store"], url: URL? = nil) {
        lock.lock(); defer { lock.unlock() }; self.status = status; self.body = body; self.headers = headers; replyURL = url; requests = []
    }
    func reply(_ request: URLRequest) -> (Int, Data, [String: String], URL) {
        lock.lock(); defer { lock.unlock() }; requests.append(request)
        return (status, body, headers, replyURL ?? request.url!)
    }
    func captured() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}
final class AttendeeWireProtocol: URLProtocol, @unchecked Sendable {
    static let state = AttendeeWireState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, headers, url) = Self.state.reply(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class AttendeeAuthTransportTests: XCTestCase {
    private var api: NativeAttendeeAPI { NativeAttendeeAPI(transport: AttendeeHTTPSessionTransport(fixtureProtocol: AttendeeWireProtocol.self)) }
    private var lease: AttendeeLease { .init(token: "na1_" + String(repeating: "B", count: 43), expiresAt: Date().addingTimeInterval(1200)) }
    private var exchange: AttendeeCodeExchange { .init(code: "nac1_" + String(repeating: "A", count: 43), verifier: String(repeating: "C", count: 43)) }
    private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private var expiry: String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(1200)) }
    private var observed: String { ISO8601DateFormatter().string(from: Date()) }
    private func tokenPayload(_ modifications: [String: Any] = [:]) throws -> Data {
        try json(["access_token": lease.token, "token_type": "Bearer", "expires_at": expiry, "event": "dqor-2026", "capabilities": ["account:read", "passes:read"]].merging(modifications) { _, new in new })
    }
    private func body(_ request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable { let size = stream.read(&buffer, maxLength: buffer.count); if size <= 0 { break }; result.append(contentsOf: buffer.prefix(size)) }
        return result
    }
    override func tearDown() { AttendeeWireProtocol.state.set(); super.tearDown() }
    func testProductionGateStopsBothAdapterAndTransportWithoutRequest() async throws {
        AttendeeWireProtocol.state.set(body: try tokenPayload())
        do { _ = try await NativeAttendeeAPI().exchange(exchange); XCTFail("Native production gate must remain closed") } catch { XCTAssertTrue(error as? AttendeeAuthError == .unavailable) }
        XCTAssertTrue(AttendeeWireProtocol.state.captured().isEmpty)
        let request = URLRequest(url: URL(string: "https://deccanqueenonrails.com/api/native/attendee/v1/account")!)
        do { _ = try await AttendeeHTTPSessionTransport().send(request); XCTFail("Raw transport must fail closed") } catch { XCTAssertTrue(error as? AttendeeAuthError == .unavailable) }
    }
    func testEphemeralConfigurationHasNoPrivatePersistenceOrCredentials() {
        let config = AttendeeHTTPSessionTransport.configuration()
        XCTAssertNil(config.httpCookieStorage); XCTAssertFalse(config.httpShouldSetCookies); XCTAssertNil(config.urlCredentialStorage); XCTAssertNil(config.urlCache); XCTAssertNil(config.httpAdditionalHeaders)
        XCTAssertEqual(config.timeoutIntervalForRequest, 20); XCTAssertEqual(config.timeoutIntervalForResource, 30)
    }
    func testExactExchangeJSONHasNoBearerCookieQueryOrExtraFields() async throws {
        AttendeeWireProtocol.state.set(body: try tokenPayload()); _ = try await api.exchange(exchange)
        let request = try XCTUnwrap(AttendeeWireProtocol.state.captured().first)
        XCTAssertEqual(request.url?.absoluteString, "https://deccanqueenonrails.com/api/native/attendee/v1/token"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(request.url?.query); XCTAssertFalse(request.httpShouldHandleCookies)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(body(request))) as? [String: String])
        XCTAssertEqual(Set(payload.keys), Set(["code", "code_verifier", "client_id", "redirect_uri"]))
        XCTAssertTrue(payload["code"] == exchange.code && payload["code_verifier"] == exchange.verifier)
        XCTAssertEqual(payload["client_id"], "dqor-ios"); XCTAssertEqual(payload["redirect_uri"], "https://deccanqueenonrails.com/native/attendee/ios/callback")
    }
    func testTokenRequiresExactFieldsFormatBearerEventAndCapabilities() async throws {
        let cases: [[String: Any]] = [["access_token": "na1_"], ["access_token": "na1_" + String(repeating: "B", count: 42) + "\n"], ["token_type": "bearer"], ["event": "different"], ["capabilities": ["account:read", "passes:read", "checkin:write"]], ["capabilities": ["account:read", "account:read"]], ["expires_at": "not-a-date"], ["schema_version": 1], ["refresh_token": "unwanted"]]
        for patch in cases {
            AttendeeWireProtocol.state.set(body: try tokenPayload(patch))
            do { _ = try await api.exchange(exchange); XCTFail("Unexpected token response must be rejected") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
        }
    }
    func testCredentialAndCodeRedactionAndShapes() {
        XCTAssertEqual(lease.description, "AttendeeLease(redacted)"); XCTAssertEqual(exchange.debugDescription, "AttendeeCodeExchange(redacted)")
        XCTAssertTrue(NativeAttendeeAPI.opaque(lease.token, prefix: "na1_")); XCTAssertFalse(NativeAttendeeAPI.opaque("na1_", prefix: "na1_")); XCTAssertFalse(NativeAttendeeAPI.opaque("na1_" + String(repeating: "B", count: 42) + "\0", prefix: "na1_"))
    }
    func testCanonicalBearerReadAndNullableAccountDTO() async throws {
        AttendeeWireProtocol.state.set(body: try json(["schema_version": 1, "event": "dqor-2026", "checked_at": observed, "account": ["id": "1", "name": NSNull(), "email": "synthetic@example.test"]]))
        let result = try await api.account(lease); XCTAssertNil(result.account.name); XCTAssertEqual(result.account.id, "1")
        let request = try XCTUnwrap(AttendeeWireProtocol.state.captured().first)
        XCTAssertEqual(request.url?.path, "/api/native/attendee/v1/account"); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + lease.token); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(request.url?.query)
    }
    func testCanonicalPassCursorAndNullableDateDTO() async throws {
        let pass: [String: Any] = ["id": "21", "type": ["id": "1", "name": "Synthetic pass"], "status": "confirmed", "admission": ["starts_on": NSNull(), "ends_on": NSNull()], "entry": [["date": "2026-10-08", "eligible": true, "checked_in_at": NSNull()]]]
        AttendeeWireProtocol.state.set(body: try json(["schema_version": 1, "event": "dqor-2026", "checked_at": observed, "passes": [pass], "more_results": false, "next_cursor": NSNull()]))
        let page = try await api.passes(lease, cursor: "20"); XCTAssertNil(page.passes.first?.admission.startsOn); XCTAssertNil(page.passes.first?.entry.first?.checkedInAt)
        let request = try XCTUnwrap(AttendeeWireProtocol.state.captured().first)
        XCTAssertEqual(request.url?.path, "/api/native/attendee/v1/passes"); XCTAssertEqual(request.url?.query, "cursor=20")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + lease.token)
    }
    func testInvalidCursorAndCredentialStopBeforeTransport() async throws {
        for cursor in ["0", "01", "-1", "1&evil=1", "9223372036854775808"] {
            AttendeeWireProtocol.state.set()
            do { _ = try await api.passes(lease, cursor: cursor); XCTFail("Noncanonical cursor must fail locally") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
            XCTAssertTrue(AttendeeWireProtocol.state.captured().isEmpty)
        }
        AttendeeWireProtocol.state.set()
        do { _ = try await api.account(.init(token: "staff_invalid", expiresAt: lease.expiresAt)); XCTFail("Staff credential cannot reach attendee transport") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
        XCTAssertTrue(AttendeeWireProtocol.state.captured().isEmpty)
    }
    func testSessionResponsePreservesCheckedAtAndNoTokenEcho() async throws {
        AttendeeWireProtocol.state.set(body: try json(["schema_version": 1, "event": "dqor-2026", "client_id": "dqor-ios", "capabilities": NativeAttendeeAPI.capabilities, "expires_at": expiry, "checked_at": observed]))
        let session = try await api.session(lease); XCTAssertEqual(session.clientID, "dqor-ios"); XCTAssertEqual(session.checkedAt, observed)
        XCTAssertEqual(AttendeeWireProtocol.state.captured().first?.url?.path, "/api/native/attendee/v1/session")
    }
    func testDelete204AndRepeatedDelete401() async throws {
        AttendeeWireProtocol.state.set(status: 204, headers: [:]); try await api.revoke(lease)
        XCTAssertEqual(AttendeeWireProtocol.state.captured().first?.httpMethod, "DELETE")
        AttendeeWireProtocol.state.set(status: 401, body: try json(["schema_version": 1, "error": ["code": "unauthenticated"]]))
        do { try await api.revoke(lease); XCTFail("Repeated revoked session must be denied") } catch { XCTAssertTrue((error as? AttendeeServiceFailure)?.code == .unauthenticated) }
    }
    func testKnownTypedErrorsAndRateLimitHeader() async throws {
        let cases: [(Int, AttendeeServiceFailure.Code)] = [(400,.invalidRequest),(401,.invalidGrant),(401,.unauthenticated),(403,.httpsRequired),(403,.invalidConsent),(404,.notFound),(409,.invalidAttempt),(422,.invalidCursor),(429,.rateLimited),(503,.configurationUnavailable),(503,.temporarilyUnavailable)]
        for (status, code) in cases {
            AttendeeWireProtocol.state.set(status: status, body: try json(["schema_version": 1, "error": ["code": code.rawValue]]), headers: ["Content-Type": "application/json", "Retry-After": "180"])
            do { if code == .invalidGrant { _ = try await api.exchange(exchange) } else { _ = try await api.account(lease) }; XCTFail("Service error must not become account data") } catch { XCTAssertTrue((error as? AttendeeServiceFailure)?.code == code); if status == 429 { XCTAssertEqual((error as? AttendeeServiceFailure)?.retryAfter, 180) } }
        }
    }
    func testUnknownErrorWrongStatusHTMLCached304AndWrongOriginRejected() async throws {
        let body = try json(["schema_version": 1, "error": ["code": "unauthenticated"]])
        for status in [200,304,307,500] {
            AttendeeWireProtocol.state.set(status: status, body: body)
            do { _ = try await api.account(lease); XCTFail("Invalid private response cannot become data") } catch {}
        }
        AttendeeWireProtocol.state.set(body: Data("<html>Sign in</html>".utf8), headers: ["Content-Type": "text/html"])
        do { _ = try await api.account(lease); XCTFail("HTML must fail closed") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
        AttendeeWireProtocol.state.set(body: body, url: URL(string: "https://example.test/api/native/attendee/v1/account"))
        do { _ = try await api.account(lease); XCTFail("Wrong origin must fail closed") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
    }
    func testAdvertisedAndUnknownLengthBodiesAreBounded() async throws {
        for headers in [["Content-Type": "application/json", "Content-Length": "9999999"], ["Content-Type": "application/json"]] {
            AttendeeWireProtocol.state.set(body: Data(repeating: 65, count: AttendeeHTTPSessionTransport.bodyLimit + 1), headers: headers)
            do { _ = try await api.account(lease); XCTFail("Oversized body must be rejected") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
        }
    }
    func testISODateAcceptsFractionalSeconds() { XCTAssertNotNil(NativeAttendeeAPI.date("2026-10-03T16:00:00.123Z")); XCTAssertNotNil(NativeAttendeeAPI.date("2026-10-03T16:00:00+05:30")); XCTAssertNil(NativeAttendeeAPI.date("unknown")) }
    func testIndependentTransportRejectsRogueRequestsBeforeInterception() async throws {
        let transport = AttendeeHTTPSessionTransport(fixtureProtocol: AttendeeWireProtocol.self)
        let base = "https://deccanqueenonrails.com/api/native/attendee/v1/account"
        var valid = URLRequest(url: URL(string: base)!)
        valid.httpShouldHandleCookies = false
        valid.setValue("application/json", forHTTPHeaderField: "Accept")
        valid.setValue("Bearer " + lease.token, forHTTPHeaderField: "Authorization")
        var requests: [URLRequest] = []
        for url in [base.replacingOccurrences(of: "https:", with: "http:"), base.replacingOccurrences(of: "deccanqueenonrails.com", with: "example.test"), base.replacingOccurrences(of: "deccanqueenonrails.com", with: "%64eccanqueenonrails.com"), base.replacingOccurrences(of: "deccanqueenonrails.com", with: "DECCANQUEENONRAILS.COM"), base.replacingOccurrences(of: ".com/", with: ".com:443/"), base.replacingOccurrences(of: "https://", with: "https://user@"), base.replacingOccurrences(of: "/account", with: "/%61ccount"), base.replacingOccurrences(of: "/account", with: "/checkin"), base + "?cursor=1", base + "#fragment"] {
            var request = valid; request.url = URL(string: url)!; requests.append(request)
        }
        var request = valid; request.httpMethod = "POST"; requests.append(request)
        request = valid; request.httpBody = Data("{}".utf8); requests.append(request)
        request = valid; request.setValue("copied-cookie", forHTTPHeaderField: "Cookie"); requests.append(request)
        request = valid; request.setValue("staff_secret", forHTTPHeaderField: "Authorization"); requests.append(request)
        request = valid; request.httpShouldHandleCookies = true; requests.append(request)
        for request in requests {
            AttendeeWireProtocol.state.set()
            do { _ = try await transport.send(request); XCTFail("Noncanonical request must fail before transport") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
            XCTAssertTrue(AttendeeWireProtocol.state.captured().isEmpty)
        }
    }
    func testUnexpected401ReadCodeIsInvalidResponseAndSessionRejectsEcho() async throws {
        AttendeeWireProtocol.state.set(status: 401, body: try json(["schema_version": 1, "error": ["code": "invalid_grant"]]))
        do { _ = try await api.session(lease); XCTFail("Exchange-only error cannot retain a private session") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
        AttendeeWireProtocol.state.set(body: try json(["schema_version": 1, "event": "dqor-2026", "client_id": "dqor-ios", "capabilities": NativeAttendeeAPI.capabilities, "expires_at": expiry, "checked_at": observed, "access_token": "unwanted-echo"]))
        do { _ = try await api.session(lease); XCTFail("Session must not return credential or identity fields") } catch { XCTAssertTrue(error as? AttendeeAuthError == .invalidResponse) }
    }
    @MainActor
    func testUnexpected401AfterReadyClearsAccountPassesAndCredential() async throws {
        let clock = AttendeeTestClock(); let bridge = AttendeeTestBridge(clock: clock)
        let mixed = Attendee401ReadBridge(fixture: bridge, wire: api)
        let store = AttendeeSessionStore(api: mixed, browser: AttendeeTestBrowser(), synthetic: true, now: { clock.now() }, uptime: { clock.uptime() })
        store.signIn()
        for _ in 0..<1000 { if store.phase == .ready { break }; try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(store.phase, .ready); XCTAssertNotNil(store.account); XCTAssertFalse(store.passes.isEmpty)
        AttendeeWireProtocol.state.set(status: 401, body: try json(["schema_version": 1, "error": ["code": "invalid_grant"]]))
        store.refresh()
        for _ in 0..<1000 { if store.phase == .signedOut { break }; try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(store.phase, .signedOut); XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty); XCTAssertTrue(store.passObservations.isEmpty)
        XCTAssertEqual(store.message, AttendeeAuthError.invalidResponse.message)
        let calls = AttendeeWireProtocol.state.captured().count
        store.refresh(); store.loadMore()
        XCTAssertEqual(AttendeeWireProtocol.state.captured().count, calls)
    }

}

private struct Attendee401ReadBridge: AttendeeBridgeAPI {
    let fixture: AttendeeTestBridge
    let wire: NativeAttendeeAPI
    func exchange(_ exchange: AttendeeCodeExchange) async throws -> AttendeeLease { try await fixture.exchange(exchange) }
    func account(_ lease: AttendeeLease) async throws -> AttendeeAccountPage { try await fixture.account(lease) }
    func passes(_ lease: AttendeeLease, cursor: String?) async throws -> AttendeePassPage { try await fixture.passes(lease, cursor: cursor) }
    func session(_ lease: AttendeeLease) async throws -> AttendeeSessionPage { try await wire.session(lease) }
    func revoke(_ lease: AttendeeLease) async throws { try await fixture.revoke(lease) }
}
