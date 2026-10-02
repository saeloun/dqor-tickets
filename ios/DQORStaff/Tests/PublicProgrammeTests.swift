import XCTest
@testable import DQORStaff

private actor ProgrammeFixtureTransport: ProgrammeTransport {
    var responses: [ProgrammeResponse]
    var validators: [String?] = []
    init(_ responses: [ProgrammeResponse]) { self.responses = responses }
    func fetch(ifNoneMatch: String?) async throws -> ProgrammeResponse {
        validators.append(ifNoneMatch)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

final class PublicProgrammeTests: XCTestCase {
    private func response(sessions: String = "[]", version: Int = 1, etag: String? = "W/\"synthetic\"") -> ProgrammeResponse {
        let json = """
        {"schema_version":\(version),"content_version":"synthetic-fingerprint","event":{"id":"dqor-2026","title":"Synthetic event","start_date":"2026-11-14","end_date":"2026-11-15","timezone":"Asia/Kolkata","venue":"Sample venue","public_url":"https://example.invalid"},"sessions":\(sessions),"speakers":[]}
        """
        return ProgrammeResponse(status: 200, etag: etag, data: Data(json.utf8))
    }
    private let unscheduled = """
    [{"id":"synthetic-session","title":"Unscheduled sample","abstract":null,"starts_at":null,"ends_at":null,"local_date":null,"speaker_id":null,"speaker_name":null,"room":null}]
    """
    func testAuthoritativeEmptySnapshotRemovesWithdrawnRows() async throws {
        let client = PublicProgrammeClient(transport: ProgrammeFixtureTransport([response(sessions: unscheduled), response()]))
        let first = try await client.refresh()
        XCTAssertNil(first.snapshot?.sessions.first?.localDate)
        XCTAssertNil(first.snapshot?.sessions.first?.speakerName)
        let second = try await client.refresh()
        XCTAssertEqual(second.snapshot?.sessions.count, 0)
        XCTAssertFalse(second.isStale)
    }
    func testExactWeakETagAnd304Reuse() async throws {
        let transport = ProgrammeFixtureTransport([response(sessions: unscheduled), ProgrammeResponse(status: 304, etag: nil, data: Data())])
        let client = PublicProgrammeClient(transport: transport)
        let first = try await client.refresh()
        let second = try await client.refresh()
        XCTAssertEqual(first, second)
        let validators = await transport.validators
        XCTAssertEqual(validators, [nil, "W/\"synthetic\""])
    }
    func test304WithoutSnapshotRetriesUnconditionally() async throws {
        let transport = ProgrammeFixtureTransport([ProgrammeResponse(status: 304, etag: nil, data: Data()), response()])
        let client = PublicProgrammeClient(transport: transport)
        let state = try await client.refresh()
        XCTAssertNotNil(state.snapshot)
        let validators = await transport.validators
        XCTAssertEqual(validators, [nil, nil])
    }
    func testFailureRetainsSnapshotButMarksStale() async throws {
        let transport = ProgrammeFixtureTransport([response(sessions: unscheduled), ProgrammeResponse(status: 503, etag: nil, data: Data())])
        let client = PublicProgrammeClient(transport: transport)
        let good = try await client.refresh()
        do { _ = try await client.refresh(); XCTFail("Expected unavailable") }
        catch { XCTAssertEqual(error as? ProgrammeError, .unavailable) }
        let stale = await client.state()
        XCTAssertEqual(stale.snapshot, good.snapshot)
        XCTAssertTrue(stale.isStale)
        do { _ = try await client.refresh(); XCTFail("Expected offline") } catch {}
        let offline = await client.state()
        XCTAssertEqual(offline, stale)
    }
    func testUnsupportedSchemaNeverReplacesCache() async throws {
        let client = PublicProgrammeClient(transport: ProgrammeFixtureTransport([response(), response(version: 2)]))
        let good = try await client.refresh()
        do { _ = try await client.refresh(); XCTFail("Expected schema rejection") }
        catch { XCTAssertEqual(error as? ProgrammeError, .unsupportedSchema) }
        let state = await client.state()
        XCTAssertEqual(state.snapshot, good.snapshot)
        XCTAssertTrue(state.isStale)
    }
    func testMalformedAndRepeated304CannotEstablishSnapshot() async {
        for responses in [[ProgrammeResponse(status: 200, etag: nil, data: Data("{}".utf8))], Array(repeating: ProgrammeResponse(status: 304, etag: nil, data: Data()), count: 2)] {
            let client = PublicProgrammeClient(transport: ProgrammeFixtureTransport(responses))
            do { _ = try await client.refresh(); XCTFail("Expected rejection") } catch {}
            let state = await client.state()
            XCTAssertNil(state.snapshot)
            XCTAssertTrue(state.isStale)
        }
    }
}
