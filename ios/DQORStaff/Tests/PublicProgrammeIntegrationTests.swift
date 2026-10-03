import XCTest
@testable import DQORStaff

private actor DelayedPublicTransport: ProgrammeTransport {
    private var continuations: [CheckedContinuation<ProgrammeResponse, Never>] = []
    func fetch(ifNoneMatch: String?) async throws -> ProgrammeResponse {
        await withCheckedContinuation { continuations.append($0) }
    }
    func pending() -> Bool { !continuations.isEmpty }
    func count() -> Int { continuations.count }
    func complete(_ response: ProgrammeResponse) { if !continuations.isEmpty { continuations.removeFirst().resume(returning: response) } }
    func completeLatest(_ response: ProgrammeResponse) { continuations.popLast()?.resume(returning: response) }
}

private actor SequencePublicTransport: ProgrammeTransport {
    private var responses: [ProgrammeResponse]
    init(_ responses: [ProgrammeResponse]) { self.responses = responses }
    func fetch(ifNoneMatch: String?) async throws -> ProgrammeResponse {
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

final class PublicProgrammeIntegrationTests: XCTestCase {
    private func fixture(_ sessions: String = "[]") -> ProgrammeResponse {
        let json = """
        {"schema_version":1,"content_version":"synthetic","event":{"id":"synthetic","title":"Synthetic programme","start_date":"2026-10-08","end_date":"2026-10-11","timezone":"Asia/Kolkata","venue":"Synthetic venue","public_url":"https://example.invalid"},"sessions":\(sessions),"speakers":[]}
        """
        return ProgrammeResponse(status: 200, etag: "W/\"synthetic\"", data: Data(json.utf8))
    }
    @MainActor
    private func settle(_ store: PublicProgrammeStore) async throws {
        for _ in 0..<200 {
            if !store.loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Programme refresh did not settle")
    }
    @MainActor
    func testStoreOfflineRetainsSnapshotAndWithdrawalClearsBookmarks() async throws {
        let session = """
        [{"id":"synthetic-session","title":"Synthetic session","abstract":null,"starts_at":null,"ends_at":null,"local_date":null,"speaker_id":null,"speaker_name":null,"room":null}]
        """
        let store = PublicProgrammeStore(transport: SequencePublicTransport([fixture(session), ProgrammeResponse(status: 503, etag: nil, data: Data()), fixture()]), isFixture: true)
        store.refresh(); try await settle(store)
        store.toggle("synthetic-session")
        XCTAssertEqual(store.savedIDs, ["synthetic-session"])
        store.refresh(); try await settle(store)
        XCTAssertEqual(store.snapshot?.sessions.count, 1)
        XCTAssertTrue(store.isStale)
        XCTAssertNotNil(store.message)
        store.refresh(); try await settle(store)
        XCTAssertEqual(store.snapshot?.sessions.count, 0)
        XCTAssertTrue(store.savedIDs.isEmpty)
        XCTAssertFalse(store.isStale)
        XCTAssertNil(store.message)
        store.refresh(); try await settle(store)
        XCTAssertTrue(store.isStale)
        XCTAssertTrue(store.message?.contains("Connection unavailable") == true)
    }
    @MainActor
    func testPrivacyClearDuringStalledResponseCannotRepopulateOrForegroundReload() async throws {
        let transport = DelayedPublicTransport()
        let store = PublicProgrammeStore(transport: transport, defaults: nil)
        store.refresh()
        for _ in 0..<100 {
            if await transport.pending() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = await transport.pending()
        XCTAssertTrue(pending)
        await store.clear()
        await transport.complete(fixture())
        await Task.yield()
        store.refresh(automatic: true)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.loading)
        XCTAssertTrue(store.cleared)
        XCTAssertTrue(store.savedIDs.isEmpty)
    }
    func testClientClearRejectsResponseAlreadyInFlight() async throws {
        let transport = DelayedPublicTransport()
        let client = PublicProgrammeClient(transport: transport)
        let request = Task { try await client.refresh() }
        for _ in 0..<100 {
            if await transport.pending() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await client.clear()
        await transport.complete(fixture())
        do { _ = try await request.value; XCTFail("Expected cleared request rejection") }
        catch { XCTAssertTrue(error is CancellationError) }
        let state = await client.state()
        XCTAssertNil(state.snapshot)
    }
    @MainActor
    func testBookmarksPersistAcrossStoreRestartAndClearRemovesPreferences() async throws {
        let suite = "dqor-public-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = """
        [{"id":"published-id","title":"Synthetic session","abstract":null,"starts_at":null,"ends_at":null,"local_date":null,"speaker_id":null,"speaker_name":null,"room":null}]
        """
        let first = PublicProgrammeStore(transport: SequencePublicTransport([fixture(session)]), defaults: defaults)
        first.refresh(); try await settle(first); first.toggle("published-id")
        let restarted = PublicProgrammeStore(transport: SequencePublicTransport([fixture(session), fixture()]), defaults: defaults)
        XCTAssertEqual(restarted.savedIDs, ["published-id"])
        XCTAssertNil(restarted.snapshot)
        restarted.refresh(); try await settle(restarted)
        XCTAssertEqual(restarted.savedIDs, ["published-id"])
        restarted.refresh(); try await settle(restarted)
        XCTAssertTrue(restarted.savedIDs.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: PublicProgrammeStore.savedKey), [])
        await restarted.clear()
        XCTAssertNil(defaults.object(forKey: PublicProgrammeStore.savedKey))
    }
    func testClearAllowsImmediateReloadWhileOldTransportIgnoresCancellation() async throws {
        let transport = DelayedPublicTransport()
        let client = PublicProgrammeClient(transport: transport)
        let old = Task { try await client.refresh() }
        for _ in 0..<100 { if await transport.pending() { break }; try await Task.sleep(for: .milliseconds(10)) }
        await client.clear()
        let reload = Task { try await client.refresh() }
        for _ in 0..<100 { if await transport.count() == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        let pending = await transport.count()
        XCTAssertEqual(pending, 2)
        await transport.completeLatest(fixture())
        let fresh = try await reload.value
        XCTAssertFalse(fresh.isStale)
        await transport.complete(ProgrammeResponse(status: 503, etag: nil, data: Data()))
        do { _ = try await old.value; XCTFail("Expected old generation rejection") } catch {}
        let state = await client.state()
        XCTAssertEqual(state, fresh)
    }
    func testEventTimezoneIsIndependentOfDeviceAndDoesNotInventEndTime() {
        let time = PublicProgrammeFormatting.time("2026-10-08T03:30:00Z", timezone: "Asia/Kolkata")
        let local = PublicProgrammeFormatting.time("2026-10-08T09:00:00+05:30", timezone: "Asia/Kolkata")
        XCTAssertEqual(time, local)
        XCTAssertNil(PublicProgrammeFormatting.time(nil, timezone: "Asia/Kolkata"))
        XCTAssertEqual(PublicProgrammeFormatting.date("2026-10-08", timezone: "Asia/Kolkata", format: "yyyy-MM-dd"), "2026-10-08")
    }
}

final class LivePublicProgrammeTests: XCTestCase {
    func testApprovedProductionReadAndExactWeakETag304() async throws {
        guard ProcessInfo.processInfo.environment["DQOR_RUN_LIVE_PUBLIC_SMOKE"] == "1" else { throw XCTSkip("Live read is explicitly opt-in") }
        let transport = PublicProgrammeHTTPTransport()
        let first = try await transport.fetch(ifNoneMatch: nil)
        XCTAssertEqual(first.status, 200)
        let etag = try XCTUnwrap(first.etag)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(PublicProgramme.self, from: first.data)
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.event.id, "dqor-2026")
        XCTAssertEqual(snapshot.event.timezone, "Asia/Kolkata")
        XCTAssertEqual(snapshot.event.publicUrl, "https://deccanqueenonrails.com")
        let second = try await transport.fetch(ifNoneMatch: etag)
        XCTAssertEqual(second.status, 304)
        XCTAssertTrue(second.data.isEmpty)
        let attachment = XCTAttachment(string: "URLSession production read:200; conditional read:304; exactETag:\(etag); sessions:\(snapshot.sessions.count); speakers:\(snapshot.speakers.count); event:\(snapshot.event.title)")
        attachment.name = "Production public read receipt"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
