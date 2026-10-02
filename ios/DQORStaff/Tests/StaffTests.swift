import XCTest
@testable import DQORStaff

@MainActor
final class StaffTests: XCTestCase {
    private func store(offline: Bool = false) async -> StaffStore {
        let store = StaffStore(api: DemoStaffAPI(offline: offline))
        await store.signIn(); store.choose(DemoStaffAPI.days[0]); return store
    }
    func testBatchMixedResultsAndDuplicate() async {
        let store = await store()
        await store.search("")
        store.matches.forEach { store.toggle($0) }
        await store.confirm()
        XCTAssertEqual(store.results.map(\.outcome), [.checkedIn, .checkedIn, .ineligible])
        XCTAssertTrue(store.selection.isEmpty)
        store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        XCTAssertEqual(store.results.first?.outcome, .duplicate)
    }
    func testOfflineNeverReportsSuccess() async {
        let store = await store(offline: true)
        store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertEqual(store.selection.count, 1)
        XCTAssertTrue(store.message?.contains("not confirmed") == true)
    }
    func testCancelAndBackDoNotSubmit() async {
        let store = await store()
        store.toggle(DemoStaffAPI.attendees[0]); store.cancelBatch()
        XCTAssertTrue(store.selection.isEmpty); XCTAssertTrue(store.results.isEmpty)
        store.toggle(DemoStaffAPI.attendees[1]); store.clearDay()
        XCTAssertNil(store.day); XCTAssertTrue(store.selection.isEmpty)
        store.choose(DemoStaffAPI.days[0]); store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        XCTAssertEqual(store.results.first?.outcome, .checkedIn)
    }
    func testScanRepeatAndInvalid() async {
        let store = await store()
        await store.scan("dqor-demo:demo-001"); await store.scan("dqor-demo:demo-001")
        XCTAssertEqual(store.selection.count, 1)
        await store.scan("not-a-ticket")
        XCTAssertTrue(store.message?.contains("not recognized") == true)
        XCTAssertEqual(store.selection.count, 1)
    }
    func testDayScopedAttendance() async {
        let store = await store()
        store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        store.choose(DemoStaffAPI.days[1]); store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        XCTAssertEqual(store.results.first?.outcome, .checkedIn)
    }
    func testScanGateCooldownAndLength() {
        var gate = ScanGate(); let now = Date()
        XCTAssertTrue(gate.accept("ticket", now: now))
        XCTAssertFalse(gate.accept("ticket", now: now.addingTimeInterval(2)))
        XCTAssertTrue(gate.accept("ticket", now: now.addingTimeInterval(3)))
        XCTAssertFalse(gate.accept(String(repeating: "a", count: 4097)))
        XCTAssertFalse(gate.accept(""))
        gate.reset(); XCTAssertTrue(gate.accept("ticket", now: now))
    }
    func testAPIRetryIsIdempotent() async throws {
        let api = DemoStaffAPI(); _ = try await api.signIn(); let id = UUID()
        let first = try await api.checkIn([DemoStaffAPI.attendees[0]], day: DemoStaffAPI.days[0], requestID: id)
        let retry = try await api.checkIn([DemoStaffAPI.attendees[0]], day: DemoStaffAPI.days[0], requestID: id)
        XCTAssertEqual(first.map(\.outcome), retry.map(\.outcome))
    }
    func testSelectionUsesStableIDWhenAttendeeDetailsChange() async {
        let store = await store()
        store.toggle(DemoStaffAPI.attendees[0])
        store.toggle(Attendee(id: "demo-001", name: "Updated synthetic name", email: "updated@example.test"))
        XCTAssertTrue(store.selection.isEmpty)
    }
    func testEventConfigurationBoundsBatchAndChangesContext() async {
        let store = await store()
        XCTAssertEqual(store.batchLimit, 50)
        store.choose(EventDay(id: "small", event: "Small demo", day: "Day 1", theme: .forest, maxBatchSize: 1))
        store.toggle(DemoStaffAPI.attendees[0]); store.toggle(DemoStaffAPI.attendees[1])
        XCTAssertEqual(store.selection.count, 1)
        XCTAssertEqual(store.day?.theme, .forest)
        XCTAssertEqual(EventDay(id: "bounded", event: "Test", day: "Test", maxBatchSize: 500).maxBatchSize, 50)
    }
    func testRolesCannotGrantThemselvesCapabilities() async throws {
        for role in [DemoRole.finance, .av] {
            let api = DemoStaffAPI(role: role)
            let session = try await api.signIn()
            XCTAssertTrue(session.capabilities.isEmpty)
            do {
                _ = try await api.checkIn([DemoStaffAPI.attendees[0]], day: DemoStaffAPI.days[0], requestID: UUID())
                XCTFail("Role must not check in")
            } catch { XCTAssertTrue(error is StaffError) }
            let store = StaffStore(api: api); await store.signIn(); store.choose(DemoStaffAPI.days[0])
            store.toggle(DemoStaffAPI.attendees[0]); XCTAssertTrue(store.selection.isEmpty)
        }
    }
    func testFailedSubmissionRetainsBatchAndNoSuccess() async {
        let store = StaffStore(api: DemoStaffAPI(failCheckIn: true))
        await store.signIn(); store.choose(DemoStaffAPI.days[0]); await store.search("")
        store.toggle(store.matches[0]); await store.confirm()
        XCTAssertEqual(store.selection.count, 1); XCTAssertTrue(store.results.isEmpty)
        await store.confirm(); XCTAssertTrue(store.results.isEmpty)
    }

    func testIncompleteResponseCannotBecomeSuccessAndRetryReusesID() async {
        let api = IncompleteAPI()
        let store = StaffStore(api: api)
        await store.signIn(); store.choose(DemoStaffAPI.days[0]); store.toggle(DemoStaffAPI.attendees[0])
        await store.confirm(); await store.confirm()
        XCTAssertTrue(store.results.isEmpty); XCTAssertEqual(store.selection.count, 1)
        let ids = await api.requestIDs
        XCTAssertEqual(ids.count, 2); XCTAssertEqual(ids.first, ids.last)
        store.cancelBatch(); store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        let updated = await api.requestIDs
        XCTAssertNotEqual(updated.first, updated.last)
    }
    func testSignOutAndEmptySearchClearSensitiveState() async {
        let store = await store(); await store.search("not-present")
        XCTAssertTrue(store.matches.isEmpty); XCTAssertTrue(store.message?.contains("No attendees") == true)
        await store.scan("dqor-demo:demo-001"); await store.signOut()
        XCTAssertNil(store.session); XCTAssertNil(store.day); XCTAssertTrue(store.selection.isEmpty)
        XCTAssertTrue(store.results.isEmpty); XCTAssertNil(store.message)
    }

}


private actor IncompleteAPI: StaffAPI {
    var requestIDs: [UUID] = []
    func signIn() async throws -> StaffSession { StaffSession(displayName: "Test", capabilities: [.searchAttendees, .scanTickets, .checkIn]) }
    func signOut() async {}
    func eventDays() async throws -> [EventDay] { DemoStaffAPI.days }
    func search(_ query: String, day: EventDay) async throws -> [Attendee] { [] }
    func resolveQR(_ payload: String, day: EventDay) async throws -> Attendee { throw StaffError.invalidTicket }
    func checkIn(_ attendees: [Attendee], day: EventDay, requestID: UUID) async throws -> [CheckInResult] {
        requestIDs.append(requestID); return []
    }
}
