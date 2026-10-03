import XCTest
import CryptoKit
@testable import DQORStaff

final class AttendeeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 1_791_040_000)
    private var elapsed: TimeInterval = 100
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func uptime() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return elapsed }
    func advance(_ seconds: TimeInterval, wallSeconds: TimeInterval? = nil) { lock.lock(); defer { lock.unlock() }; elapsed += seconds; wall += wallSeconds ?? seconds }
}
@MainActor
final class AttendeeTestBrowser: AttendeeBrowserAuthorizing {
    var calls = 0
    var automatic = true
    private var continuation: CheckedContinuation<URL, Error>?
    private var transactionState: String?
    func authorize(_ url: URL) async throws -> URL {
        calls += 1
        transactionState = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value
        if automatic { return callback()! }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func callback() -> URL? {
        guard let transactionState else { return nil }
        var url = URLComponents(string: "https://deccanqueenonrails.com/native/attendee/ios/callback")!
        url.queryItems = [.init(name: "code", value: "nac1_" + String(repeating: "A", count: 43)), .init(name: "state", value: transactionState)]
        return url.url
    }
    func receiveExternal(_ url: URL) -> Bool {
        guard let previous = continuation else { return false }
        continuation = nil; previous.resume(returning: url)
        return true
    }
    func cancel() { let previous = continuation; continuation = nil; previous?.resume(throwing: AttendeeAuthError.canceled) }
    func complete() { if let callback = callback() { _ = receiveExternal(callback) } }
}
actor AttendeeTestBridge: AttendeeBridgeAPI {
    enum Operation: Hashable { case exchange, account, passes, session, revoke }
    private var counts: [Operation: Int] = [:]
    private var paused = Set<Operation>()
    private var gates: [Operation: CheckedContinuation<Void, Never>] = [:]
    var failure: AttendeeAuthError?
    var serviceFailure: AttendeeServiceFailure?
    var leaseDuration: TimeInterval = 1200
    var token = "na1_" + String(repeating: "B", count: 43)
    var identity = "1"
    var name: String? = nil
    var malformedPage = false
    var badSessionClient = false
    private let clock: AttendeeTestClock
    init(clock: AttendeeTestClock) { self.clock = clock }
    func setLeaseDuration(_ seconds: TimeInterval) { leaseDuration = seconds }
    func count(_ op: Operation) -> Int { counts[op] ?? 0 }
    func pause(_ op: Operation) { paused.insert(op) }
    func resume(_ op: Operation) { paused.remove(op); gates.removeValue(forKey: op)?.resume() }
    func configure(failure: AttendeeAuthError? = nil, token: String? = nil, identity: String? = nil, malformed: Bool = false, badClient: Bool = false, rateLimited: Bool = false) {
        self.failure = failure; if let token { self.token = token }; if let identity { self.identity = identity }
        malformedPage = malformed; badSessionClient = badClient
        serviceFailure = rateLimited ? AttendeeServiceFailure(code: .rateLimited, retryAfter: 180) : nil
    }
    private func step(_ op: Operation) async throws {
        counts[op, default: 0] += 1
        if paused.contains(op) { await withCheckedContinuation { gates[op] = $0 } }
        if let failure { throw failure }
        if let serviceFailure { throw serviceFailure }
    }
    private var observed: String { ISO8601DateFormatter().string(from: clock.now()) }
    func exchange(_ exchange: AttendeeCodeExchange) async throws -> AttendeeLease { try await step(.exchange); return AttendeeLease(token: token, expiresAt: clock.now().addingTimeInterval(leaseDuration)) }
    func account(_ lease: AttendeeLease) async throws -> AttendeeAccountPage {
        try await step(.account)
        return AttendeeAccountPage(schemaVersion: 1, event: "dqor-2026", checkedAt: observed, account: .init(id: identity, name: name, email: "synthetic@example.test"))
    }
    func passes(_ lease: AttendeeLease, cursor: String?) async throws -> AttendeePassPage {
        try await step(.passes)
        let ids = cursor == nil ? ["1", "2"] : ["3"]
        let rows = ids.map { AttendeePass(id: $0, type: .init(id: "1", name: "Synthetic pass"), status: "confirmed", admission: .init(startsOn: nil, endsOn: nil), entry: [.init(date: "2026-10-08", eligible: true, checkedInAt: nil)]) }
        return AttendeePassPage(schemaVersion: 1, event: "dqor-2026", checkedAt: observed, passes: rows, moreResults: cursor == nil, nextCursor: cursor == nil ? (malformedPage ? "100" : "2") : nil)
    }
    func session(_ lease: AttendeeLease) async throws -> AttendeeSessionPage {
        try await step(.session)
        return AttendeeSessionPage(schemaVersion: 1, event: "dqor-2026", clientID: badSessionClient ? "dqor-android" : "dqor-ios", capabilities: NativeAttendeeAPI.capabilities, expiresAt: ISO8601DateFormatter().string(from: lease.expiresAt), checkedAt: observed)
    }
    func revoke(_ lease: AttendeeLease) async throws { try await step(.revoke) }
}
final class AttendeeAuthTests: XCTestCase {
    @MainActor
    private func until(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<1000 { if predicate() { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Expected bounded synthetic state transition")
    }
    private func assertCount(_ bridge: AttendeeTestBridge, _ op: AttendeeTestBridge.Operation, _ count: Int) async {
        let actual = await bridge.count(op); XCTAssertEqual(actual, count)
    }
    private func untilCount(_ bridge: AttendeeTestBridge, _ op: AttendeeTestBridge.Operation, _ count: Int) async throws {
        for _ in 0..<1000 { if await bridge.count(op) >= count { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Expected synthetic operation")
    }
    @MainActor
    private func fixture(timeout: TimeInterval = 20, authTimeout: TimeInterval = 600) -> (AttendeeSessionStore, AttendeeTestBridge, AttendeeTestBrowser, AttendeeTestClock) {
        let clock = AttendeeTestClock(); let api = AttendeeTestBridge(clock: clock); let browser = AttendeeTestBrowser()
        let store = AttendeeSessionStore(api: api, browser: browser, synthetic: true, supportsHTTPSCallback: true, now: { clock.now() }, uptime: { clock.uptime() }, operationTimeout: timeout, authorizationTimeout: authTimeout)
        return (store, api, browser, clock)
    }
    func testCryptographicTransactionShapeChallengeAndRedaction() throws {
        var states = Set<String>(); var verifiers = Set<String>()
        for _ in 0..<32 {
            let value = try AttendeeLoginTransaction(uptime: 100)
            XCTAssertEqual(value.state.count, 43); XCTAssertEqual(value.verifier.count, 43); XCTAssertEqual(value.challenge.count, 43)
            states.insert(value.state); verifiers.insert(value.verifier)
            let query = URLComponents(url: value.authorizeURL, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(Set(query.map(\.name)), Set(["client_id", "redirect_uri", "state", "code_challenge", "code_challenge_method"]))
            XCTAssertTrue(query.first(where: { $0.name == "code_challenge" })?.value == value.challenge)
            XCTAssertFalse(value.description.contains(value.state)); XCTAssertFalse(value.description.contains(value.verifier))
        }
        XCTAssertEqual(states.count, 32); XCTAssertEqual(verifiers.count, 32); XCTAssertTrue(states.isDisjoint(with: verifiers))
        let known = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(AttendeeLoginTransaction.base64URL(Data(SHA256.hash(data: Data(known.utf8)))), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testStrictCallbackCanonicalOriginPathParametersCodeAndTimeout() throws {
        let value = try AttendeeLoginTransaction(uptime: 100)
        let code = "nac1_" + String(repeating: "A", count: 43)
        let valid = "https://deccanqueenonrails.com/native/attendee/ios/callback?code=\(code)&state=\(value.state)"
        XCTAssertTrue(try value.exchange(callback: URL(string: valid)!, uptime: 101).verifier == value.verifier)
        let invalid = [valid.replacingOccurrences(of: "https:", with: "http:"), valid.replacingOccurrences(of: "deccanqueenonrails.com", with: "DECCANQUEENONRAILS.COM"), valid.replacingOccurrences(of: "deccanqueenonrails.com", with: "%64eccanqueenonrails.com"), valid.replacingOccurrences(of: ".com/", with: ".com:443/"), valid.replacingOccurrences(of: "https://", with: "https://user@"), valid.replacingOccurrences(of: "/ios/", with: "/android/"), valid.replacingOccurrences(of: "/callback?", with: "/%63allback?"), valid + "#fragment", valid + "&state=extra", valid + "&code=extra", valid + "&extra=value", valid.replacingOccurrences(of: value.state, with: "wrong"), valid.replacingOccurrences(of: code, with: "nac1_%00" + String(repeating: "A", count: 42)), valid.replacingOccurrences(of: code, with: "nac1_"), valid + String(repeating: "A", count: 5000)]
        for url in invalid { XCTAssertThrowsError(try value.exchange(callback: URL(string: url)!, uptime: 101), "Noncanonical callback must be rejected") }
        XCTAssertThrowsError(try value.exchange(callback: URL(string: valid)!, uptime: 99))
        XCTAssertThrowsError(try value.exchange(callback: URL(string: valid)!, uptime: 700))
    }
    @MainActor
    func testClosedDefaultAndOlderPolicyCannotStartOrAcceptCallback() async throws {
        let disabled = AttendeeSessionStore(); disabled.signIn(); XCTAssertEqual(disabled.phase, .unavailable)
        let clock = AttendeeTestClock(); let api = AttendeeTestBridge(clock: clock); let browser = AttendeeTestBrowser()
        let older = AttendeeSessionStore(api: api, browser: browser, synthetic: true, supportsHTTPSCallback: false)
        older.signIn(); XCTAssertEqual(browser.calls, 0); XCTAssertEqual(older.phase, .unavailable)
        XCTAssertFalse(older.receiveExternalCallback(URL(string: "https://deccanqueenonrails.com/native/attendee/ios/callback")!))
        do { _ = try await SystemAttendeeBrowser().authorize(URL(string: "https://deccanqueenonrails.com/account/native/authorize")!); XCTFail("Live browser gate must remain closed") } catch { XCTAssertTrue(error as? AttendeeAuthError == .unavailable) }
    }
    @MainActor
    func testHappyReadOnlyNullableAccountAndPagination() async throws {
        let (store, api, _, _) = fixture(); store.signIn(); try await until { store.phase == .ready }
        XCTAssertNil(store.account?.name); XCTAssertEqual(store.passes.count, 2); XCTAssertNotNil(store.accountCheckedAt)
        XCTAssertNil(store.passes.first?.admission.startsOn); XCTAssertNil(store.passes.first?.entry.first?.checkedInAt)
        store.loadMore(); store.loadMore(); try await until { !store.loading }
        XCTAssertEqual(store.passes.map(\.id), ["1", "2", "3"]); XCTAssertFalse(store.moreResults)
        await assertCount(api, .passes, 2)
        XCTAssertEqual(Set(store.passObservations.keys), Set(["1", "2", "3"]))
    }
    @MainActor
    func testRepeatedTapAndExternalReturnConsumeOneContinuation() async throws {
        let (store, api, browser, _) = fixture(); browser.automatic = false
        store.signIn(); store.signIn(); try await until { browser.calls == 1 }
        let callback = browser.callback()!
        XCTAssertTrue(store.receiveExternalCallback(callback)); browser.cancel(); XCTAssertFalse(store.receiveExternalCallback(callback)); browser.complete()
        try await until { store.phase == .ready }; await assertCount(api, .exchange, 1)
        XCTAssertFalse(store.receiveExternalCallback(callback))
    }
    @MainActor
    func testCancelBrowserThenOldExternalReturnCannotExchange() async throws {
        let (store, api, browser, _) = fixture(); browser.automatic = false
        store.signIn(); try await until { browser.calls == 1 }; let previous = browser.callback()!
        store.cancelLogin(); XCTAssertFalse(store.receiveExternalCallback(previous)); browser.complete()
        try await Task.sleep(for: .milliseconds(10)); await assertCount(api, .exchange, 0); XCTAssertNil(store.account)
    }
    @MainActor
    func testLateExchangeAfterCancelCannotRestoreAccountAndRevokeKnownLease() async throws {
        let (store, api, _, _) = fixture(); await api.pause(.exchange)
        store.signIn(); try await untilCount(api, .exchange, 1); store.cancelLogin(); await api.resume(.exchange)
        try await untilCount(api, .revoke, 1); XCTAssertNil(store.account); XCTAssertEqual(store.phase, .signedOut); await assertCount(api, .account, 0)
    }
    @MainActor
    func testLateExchangeAfterLogoutCannotRestoreAccount() async throws {
        let (store, api, _, _) = fixture(); await api.pause(.exchange)
        store.signIn(); try await untilCount(api, .exchange, 1); store.logout(); await api.resume(.exchange)
        try await untilCount(api, .revoke, 1); XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty)
    }
    @MainActor
    func testLateAccountAfterLogoutCannotStartPassRead() async throws {
        let (store, api, _, _) = fixture(); await api.pause(.account)
        store.signIn(); try await untilCount(api, .account, 1); store.logout(); await api.resume(.account)
        try await Task.sleep(for: .milliseconds(10)); XCTAssertNil(store.account); await assertCount(api, .passes, 0)
    }
    @MainActor
    func testAccountAndPaginationResponsesAfterExpiryStayCleared() async throws {
        let (store, api, _, clock) = fixture(); store.signIn(); try await until { store.phase == .ready }
        await api.pause(.passes); store.loadMore(); try await untilCount(api, .passes, 2)
        clock.advance(1201); store.foreground(); await api.resume(.passes)
        try await Task.sleep(for: .milliseconds(10)); XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty); XCTAssertEqual(store.phase, .signedOut)
        let (second, secondAPI, _, secondClock) = fixture(); await secondAPI.pause(.account)
        second.signIn(); try await untilCount(secondAPI, .account, 1); secondClock.advance(1201); second.foreground(); await secondAPI.resume(.account)
        try await Task.sleep(for: .milliseconds(10)); await assertCount(secondAPI, .passes, 0); XCTAssertNil(second.account)
    }
    @MainActor
    func testContinuousElapsedExpirySurvivesSleepAdvanceAndWallClockRollback() async throws {
        let (store, _, _, clock) = fixture(); store.signIn(); try await until { store.phase == .ready }
        clock.advance(1201, wallSeconds: -3600); store.foreground(); XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty)
    }
    @MainActor
    func testOfflineReadsAreLabeledStaleAndRevocationClears() async throws {
        let (store, api, _, _) = fixture(); store.signIn(); try await until { store.phase == .ready }
        await api.configure(failure: .offline); store.refresh(); try await until { !store.loading }
        XCTAssertTrue(store.stale); XCTAssertNotNil(store.account)
        await api.configure(failure: .revoked); store.refresh(); try await until { store.phase == .signedOut }
        XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty)
    }
    @MainActor
    func testLogoutClearsImmediatelyOfflineRemovalExplicitRetry() async throws {
        let (store, api, _, _) = fixture(); store.signIn(); try await until { store.phase == .ready }
        await api.configure(failure: .offline); store.logout(); XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty)
        try await untilCount(api, .revoke, 1); try await Task.sleep(for: .milliseconds(10)); XCTAssertTrue(store.revocationPending)
        await api.configure(); store.retryRevocation(); try await until { !store.revocationPending }; await assertCount(api, .revoke, 2)
    }
    @MainActor
    func testInvalidLeaseShapeAndPaginationAreRejected() async throws {
        for token in ["na1_", "na1_" + String(repeating: "A", count: 42), "na1_" + String(repeating: "A", count: 42) + "\n", "staff_" + String(repeating: "A", count: 43)] {
            let (store, api, _, _) = fixture(); await api.configure(token: token); store.signIn(); try await until { store.message != nil }; XCTAssertNil(store.account); await assertCount(api, .account, 0)
        }
        let (store, api, _, _) = fixture(); await api.configure(malformed: true); store.signIn(); try await until { store.message != nil }; XCTAssertNil(store.account)
    }
    @MainActor
    func testIdentityOrSessionClientChangeClearsPrivateState() async throws {
        let (store, api, _, _) = fixture(); store.signIn(); try await until { store.phase == .ready }
        await api.configure(identity: "2"); store.refresh(); try await until { store.phase == .signedOut }; XCTAssertNil(store.account)
        let (second, secondAPI, _, _) = fixture(); second.signIn(); try await until { second.phase == .ready }
        await secondAPI.configure(badClient: true); second.refresh(); try await until { second.phase == .signedOut }; XCTAssertTrue(second.passes.isEmpty)
    }
    @MainActor
    func testUncooperativeExchangeAndBrowserTimeoutInvalidateGeneration() async throws {
        let (store, api, _, _) = fixture(timeout: 0.02); await api.pause(.exchange); store.signIn()
        try await untilCount(api, .exchange, 1); try await until { store.phase == .signedOut }; await api.resume(.exchange)
        try await untilCount(api, .revoke, 1); await assertCount(api, .account, 0)
        let (second, _, browser, _) = fixture(authTimeout: 0.02); browser.automatic = false; second.signIn(); try await until { second.message != nil }; XCTAssertEqual(second.phase, .signedOut)
    }
    @MainActor
    func testRateLimitPreventsImmediateRetryWithoutAutomaticExchange() async throws {
        let (store, api, _, clock) = fixture(); await api.configure(rateLimited: true); store.signIn(); try await until { store.message != nil }
        XCTAssertFalse(store.canRequest); XCTAssertEqual(store.retryDelay, 180); store.signIn(); await assertCount(api, .exchange, 1)
        clock.advance(181); store.foreground(); await api.configure(); store.signIn(); try await until { store.phase == .ready }
    }
    @MainActor
    func testIdleLeaseExpiryClearsPrivateInformationWithoutRefresh() async throws {
        let (store, api, _, _) = fixture()
        await api.setLeaseDuration(0.05)
        store.signIn(); try await until { store.phase == .ready }
        XCTAssertNotNil(store.account); XCTAssertFalse(store.passes.isEmpty)
        try await until { store.phase == .signedOut }
        XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty); XCTAssertTrue(store.passObservations.isEmpty)
        XCTAssertEqual(store.message, AttendeeAuthError.expired.message)
        await assertCount(api, .session, 0); await assertCount(api, .revoke, 0)
    }
    @MainActor
    func testReopenForegroundRevalidatesBeforeMarkingInformationCurrent() async throws {
        let (store, api, _, _) = fixture(); store.signIn(); try await until { store.phase == .ready }
        await api.pause(.session); store.foreground()
        XCTAssertTrue(store.loading); XCTAssertTrue(store.stale)
        try await untilCount(api, .session, 1)
        await api.resume(.session); try await until { !store.loading }
        XCTAssertEqual(store.phase, .ready); XCTAssertFalse(store.stale)
    }

    @MainActor
    func testPendingCallbackExpiresAfterSimulatedSleepDespiteWallClockRollback() async throws {
        let (store, api, browser, clock) = fixture(); browser.automatic = false
        store.signIn(); try await until { browser.calls == 1 }; let callback = browser.callback()!
        clock.advance(601, wallSeconds: -3600)
        XCTAssertFalse(store.receiveExternalCallback(callback)); browser.complete()
        try await until { store.phase == .signedOut }; XCTAssertNil(store.account)
        await assertCount(api, .exchange, 0)
    }
    @MainActor
    func testIdleFailedRemovalDropsExpiredHandleWithoutAutomaticRetry() async throws {
        let (store, api, _, _) = fixture(); await api.setLeaseDuration(0.08)
        store.signIn(); try await until { store.phase == .ready }
        await api.configure(failure: .offline); store.logout()
        try await untilCount(api, .revoke, 1); XCTAssertTrue(store.revocationPending)
        try await until { !store.revocationPending }
        XCTAssertEqual(store.phase, .signedOut); XCTAssertNil(store.account); XCTAssertTrue(store.passes.isEmpty)
        store.retryRevocation(); await assertCount(api, .revoke, 1)
    }
    @MainActor
    func testLateOldExchangeAfterNewSignInCannotClearNewSession() async throws {
        let clock = AttendeeTestClock(); let api = AttendeeLateFlowBridge(clock: clock)
        let store = AttendeeSessionStore(api: api, browser: AttendeeTestBrowser(), synthetic: true, now: { clock.now() }, uptime: { clock.uptime() })
        store.signIn()
        for _ in 0..<1000 { if await api.firstWaiting() { break }; try await Task.sleep(for: .milliseconds(1)) }
        let waiting = await api.firstWaiting(); XCTAssertTrue(waiting)
        store.cancelLogin(); store.signIn(); try await until { store.phase == .ready }
        await api.releaseFirst()
        for _ in 0..<1000 { if await api.revokedOldOnly() { break }; try await Task.sleep(for: .milliseconds(1)) }
        let oldOnly = await api.revokedOldOnly(); XCTAssertTrue(oldOnly)
        XCTAssertEqual(store.phase, .ready); XCTAssertNotNil(store.account); XCTAssertFalse(store.passes.isEmpty)
        store.refresh(); try await until { !store.loading }; XCTAssertEqual(store.phase, .ready)
    }

}

private actor AttendeeLateFlowBridge: AttendeeBridgeAPI {
    let fixture: AttendeeTestBridge
    let clock: AttendeeTestClock
    var first: CheckedContinuation<Void, Never>?
    var exchanges = 0
    var revokedOld = false
    init(clock: AttendeeTestClock) { self.clock = clock; fixture = AttendeeTestBridge(clock: clock) }
    func firstWaiting() -> Bool { first != nil }
    func releaseFirst() { let continuation = first; first = nil; continuation?.resume() }
    func revokedOldOnly() -> Bool { revokedOld }
    func exchange(_ exchange: AttendeeCodeExchange) async throws -> AttendeeLease {
        exchanges += 1
        if exchanges == 1 {
            await withCheckedContinuation { first = $0 }
            return .init(token: "na1_" + String(repeating: "C", count: 43), expiresAt: clock.now().addingTimeInterval(1200))
        }
        return try await fixture.exchange(exchange)
    }
    func account(_ lease: AttendeeLease) async throws -> AttendeeAccountPage { try await fixture.account(lease) }
    func passes(_ lease: AttendeeLease, cursor: String?) async throws -> AttendeePassPage { try await fixture.passes(lease, cursor: cursor) }
    func session(_ lease: AttendeeLease) async throws -> AttendeeSessionPage { try await fixture.session(lease) }
    func revoke(_ lease: AttendeeLease) async throws { revokedOld = lease.token == "na1_" + String(repeating: "C", count: 43) }
}
