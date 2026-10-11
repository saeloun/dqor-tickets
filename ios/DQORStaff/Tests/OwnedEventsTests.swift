import XCTest
@testable import DQORStaff

private actor OwnedQueue: OwnedEventsTransport {
    var responses: [OwnedEventsResponse]
    var validators: [String?] = []
    init(_ responses: [OwnedEventsResponse]) { self.responses = responses }
    func fetch(_ resource: OwnedEventsResource, ifNoneMatch: String?) async throws -> OwnedEventsResponse {
        validators.append(ifNoneMatch)
        guard !responses.isEmpty else { throw OwnedEventsError.unavailable }
        return responses.removeFirst()
    }
}
private actor OwnedPaused: OwnedEventsTransport {
    var continuation: CheckedContinuation<OwnedEventsResponse, Never>?
    func fetch(_ resource: OwnedEventsResource, ifNoneMatch: String?) async throws -> OwnedEventsResponse {
        await withCheckedContinuation { continuation = $0 }
    }
    func waiting() -> Bool { continuation != nil }
    func resume(_ response: OwnedEventsResponse) { continuation?.resume(returning: response); continuation = nil }
}
final class OwnedEventsTests: XCTestCase {
    private let etag = "W/\"synthetic-owned\""
    private let resource = OwnedEventsResource.catalog(1)
    private func response(_ status: Int = 200, detail: Bool = false, data: Data? = nil, etag: String? = nil) -> OwnedEventsResponse {
        OwnedEventsResponse(status: status, etag: etag ?? self.etag, data: data ?? Data((detail ? OwnedEventsFixture.detail : OwnedEventsFixture.catalog).utf8))
    }
    private func mutate(detail: Bool = false, _ block: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: Data((detail ? OwnedEventsFixture.detail : OwnedEventsFixture.catalog).utf8)) as! [String: Any]
        block(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testContractCatalogAndIndependentDetailWithOrganizerDatesAndSafeWebsite() async throws {
        let client = OwnedEventsClient(transport: OwnedQueue([response(), response(detail: true)]))
        let catalog = try await client.refresh(resource)
        XCTAssertEqual(catalog.catalog?.pagination.total, 1)
        XCTAssertEqual(catalog.catalog?.events.first?.organizer.name, "Synthetic organizers")
        XCTAssertEqual(catalog.catalog?.events.first?.startDate, "2026-11-07")
        let detail = try await client.refresh(.detail("hosted-event-101"))
        XCTAssertEqual(detail.event, catalog.catalog?.events.first)
        XCTAssertEqual(detail.event?.website.absoluteString, "https://deccanqueenonrails.com/events/synthetic-organizers/synthetic-meetup")
        XCTAssertFalse(detail.stale)
    }
    func test503KeepsStaleSnapshotThen304RecoversWithExactValidator() async throws {
        let queue = OwnedQueue([response(), response(503), response(304, data: Data())])
        let client = OwnedEventsClient(transport: queue)
        let first = try await client.refresh(resource)
        do { _ = try await client.refresh(resource); XCTFail("503 must fail") } catch { XCTAssertEqual(error as? OwnedEventsError, .unavailable) }
        let stale = await client.state(resource)
        XCTAssertTrue(stale.stale); XCTAssertEqual(stale.catalog, first.catalog)
        let recovered = try await client.refresh(resource)
        XCTAssertFalse(recovered.stale); XCTAssertEqual(recovered.catalog, first.catalog)
        let validators = await queue.validators
        XCTAssertEqual(validators, [nil, etag, etag])
    }
    func testDetailWithdrawalRemovesDetailAndCatalogBeforeExplicitRecovery() async throws {
        let client = OwnedEventsClient(transport: OwnedQueue([response(), response(detail: true), response(404), response()]))
        _ = try await client.refresh(resource)
        _ = try await client.refresh(.detail("hosted-event-101"))
        let withdrawn = try await client.refresh(.detail("hosted-event-101"))
        XCTAssertTrue(withdrawn.unavailable); XCTAssertNil(withdrawn.event)
        let catalog = await client.state(resource)
        XCTAssertNil(catalog.catalog)
        let recovered = try await client.refresh(resource)
        XCTAssertNotNil(recovered.catalog)
    }
    func testCatalog404ClearsAllDetailSnapshots() async throws {
        let client = OwnedEventsClient(transport: OwnedQueue([response(detail: true), response(404)]))
        _ = try await client.refresh(.detail("hosted-event-101"))
        let withdrawn = try await client.refresh(resource)
        XCTAssertTrue(withdrawn.unavailable)
        let detail = await client.state(.detail("hosted-event-101"))
        XCTAssertNil(detail.event)
    }
    func testAuthoritativeEmpty200ClearsOldRows() async throws {
        let empty = try mutate { $0["events"] = []; $0["pagination"] = ["page": 1, "per_page": 24, "total": 0] }
        let client = OwnedEventsClient(transport: OwnedQueue([response(), response(data: empty)]))
        _ = try await client.refresh(resource)
        let state = try await client.refresh(resource)
        XCTAssertEqual(state.catalog?.events.count, 0); XCTAssertFalse(state.stale)
    }
    func testOrphan304RetriesExactlyOnceWithoutValidator() async throws {
        let queue = OwnedQueue([response(304, data: Data()), response()])
        let client = OwnedEventsClient(transport: queue)
        let state = try await client.refresh(resource)
        XCTAssertNotNil(state.catalog)
        let validators = await queue.validators
        XCTAssertEqual(validators, [nil, nil])
        let invalid = OwnedEventsClient(transport: OwnedQueue([response(304), response(304)]))
        do { _ = try await invalid.refresh(resource); XCTFail("Repeated orphan 304 must fail") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
    }
    func testMismatched304NeverFreshensSnapshot() async throws {
        let client = OwnedEventsClient(transport: OwnedQueue([response(), response(304, etag: "\"different\"")]))
        _ = try await client.refresh(resource)
        do { _ = try await client.refresh(resource); XCTFail("Mismatched validator must fail") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        let state = await client.state(resource); XCTAssertTrue(state.stale)
    }
    func testForeignIDsAndInvalidPagesNeverReachTransport() async throws {
        let queue = OwnedQueue([])
        let client = OwnedEventsClient(transport: queue)
        for bad in ["external-101", "hosted-event-0", "hosted-event-01", "hosted-event-9223372036854775808", "hosted-event-1/../2"] {
            XCTAssertFalse(OwnedEvent.validID(bad))
            do { _ = try await client.refresh(.detail(bad)); XCTFail("Invalid ID") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        }
        for page in [0, 1001] {
            do { _ = try await client.refresh(.catalog(page)); XCTFail("Invalid page") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        }
        let calls = await queue.validators; XCTAssertTrue(calls.isEmpty)
    }
    func testWrongIdentityUnknownFieldsAndBadDatesRejected() async throws {
        let badFields: [(String, Any)] = [("id", "hosted-event-102"), ("ownership", "external_listing"), ("title", " "), ("starts_at", "2026-11-07T00:15:00"), ("ends_at", "2025-11-07T01:30:00+05:30"), ("timezone", "Invalid/Zone"), ("start_date", "2026-11-08"), ("details_path", "https://example.com/private"), ("private_token", "synthetic")]
        for (key, value) in badFields {
            let data = try mutate(detail: true) { root in var event = root["event"] as! [String: Any]; event[key] = value; root["event"] = event }
            let client = OwnedEventsClient(transport: OwnedQueue([response(detail: true, data: data)]))
            do { _ = try await client.refresh(.detail("hosted-event-101")); XCTFail("Invalid field \(key)") } catch { }
        }
        let data = try mutate { $0["account"] = ["email": "synthetic@example.invalid"] }
        do { _ = try await OwnedEventsClient(transport: OwnedQueue([response(data: data)])).refresh(resource); XCTFail("Closed contract") } catch { }
    }
    func testSchemaPaginationAndDuplicateLimits() async throws {
        let cases = [try mutate { $0["schema_version"] = 2 }, try mutate { $0["content_version"] = "invalid" }, try mutate { $0["pagination"] = ["page": 2, "per_page": 24, "total": 1] }, try mutate { root in let rows = root["events"] as! [[String: Any]]; root["events"] = [rows[0], rows[0]] }, try mutate { root in let row = (root["events"] as! [[String: Any]])[0]; root["events"] = Array(repeating: row, count: 25) }]
        for data in cases {
            do { _ = try await OwnedEventsClient(transport: OwnedQueue([response(data: data)])).refresh(resource); XCTFail("Invalid snapshot") } catch { }
        }
    }
    func testClearAndBackgroundDiscardDelayedReplies() async throws {
        for clear in [true, false] {
            let transport = OwnedPaused(); let client = OwnedEventsClient(transport: transport)
            let request = Task { try await client.refresh(resource) }
            for _ in 0..<1000 { if await transport.waiting() { break }; await Task.yield() }
            let waiting = await transport.waiting(); XCTAssertTrue(waiting)
            guard waiting else { request.cancel(); return }
            if clear { await client.clear() } else { await client.markStale() }
            await transport.resume(response())
            do { _ = try await request.value; XCTFail("Late response") } catch { XCTAssertTrue(error is CancellationError) }
            let state = await client.state(resource); XCTAssertNil(state.catalog)
        }
    }
    func testCacheIsBoundedAndEvictedResourceCannotSendValidator() async throws {
        var replies: [OwnedEventsResponse] = []
        for page in 1...9 {
            let data = try mutate { $0["pagination"] = ["page": page, "per_page": 24, "total": 250] }
            replies.append(response(data: data))
        }
        replies.append(response())
        let queue = OwnedQueue(replies); let client = OwnedEventsClient(transport: queue)
        for page in 1...9 { _ = try await client.refresh(.catalog(page)) }
        let evicted = await client.state(resource); XCTAssertNil(evicted.catalog)
        _ = try await client.refresh(resource)
        let validators = await queue.validators; XCTAssertNil(validators.last!)
    }
    func testPayloadBoundAndValidatorSafety() async throws {
        let large = Data(repeating: 32, count: OwnedEventsHTTPTransport.maximumBodyBytes + 1)
        do { _ = try await OwnedEventsClient(transport: OwnedQueue([response(data: large)])).refresh(resource); XCTFail("Oversized body") } catch { XCTAssertEqual(error as? OwnedEventsError, .invalidResponse) }
        for value in ["bad", "\"a\r\nb\"", "\"a\\b\"", "\"a\"b\"", "\"" + String(repeating: "a", count: 255) + "\""] { XCTAssertFalse(OwnedEventsClient.validETag(value)) }
        XCTAssertTrue(OwnedEventsClient.validETag(etag)); XCTAssertFalse(OwnedEventsIntegration.productionEnabled)
    }
}
