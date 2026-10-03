import XCTest
@testable import DQORStaff

@MainActor
final class CompanionTests: XCTestCase {
    func testSharedArtworkIsBundledAndAttendeePreviewCannotBecomeStaffDay() {
        XCTAssertNotNil(EventArtwork.cover)
        XCTAssertFalse(DemoStaffAPI.days.contains(DemoCompanion.previewDay))
        XCTAssertEqual(DemoCompanion.schedule(for: DemoCompanion.previewDay).count, 3)
        XCTAssertEqual(DemoCompanion.passes(for: DemoCompanion.previewDay).count, 1)
    }
    func testFixturesAreScopedAndEntitlementsIndependent() {
        let first = DemoStaffAPI.days[0], second = DemoStaffAPI.days[1]
        XCTAssertTrue(Set(DemoCompanion.schedule(for: first).map(\.id)).isDisjoint(with: DemoCompanion.schedule(for: second).map(\.id)))
        let pass = DemoCompanion.passes(for: first)[0]
        XCTAssertEqual(pass.admission, .available)
        XCTAssertEqual(pass.meal, .redeemed)
        XCTAssertEqual(pass.party, .notIncluded)
        let live = EventDay(id: "unknown", event: "Unknown", day: "Today")
        XCTAssertTrue(DemoCompanion.passes(for: live).isEmpty)
        XCTAssertTrue(DemoCompanion.schedule(for: live).isEmpty)
    }
    func testHistoryScanRepeatFailureAndSignOut() async {
        let store = StaffStore(api: DemoStaffAPI())
        await store.signIn(); store.choose(DemoStaffAPI.days[0])
        await store.scan("dqor-demo:demo-001"); await store.scan("dqor-demo:demo-001")
        XCTAssertEqual(store.activity.count, 1)
        XCTAssertTrue(store.activity[0].summary.contains("not confirmed"))
        await store.scan("secret-invalid-payload")
        XCTAssertNil(store.activity.last?.attendeeID)
        XCTAssertFalse(store.activity.contains { $0.summary.contains("secret") })
        await store.confirm()
        XCTAssertEqual(store.activity.last?.summary, "Checked in")
        store.choose(DemoStaffAPI.days[1])
        XCTAssertTrue(store.activity.filter { $0.dayID == store.day?.id }.isEmpty)
        await store.signOut(); XCTAssertTrue(store.activity.isEmpty)
    }
    func testFailedSubmissionNeverRecordsSuccessAndHistoryIsBounded() async {
        let store = StaffStore(api: DemoStaffAPI(failCheckIn: true))
        await store.signIn(); store.choose(DemoStaffAPI.days[0])
        store.toggle(DemoStaffAPI.attendees[0]); await store.confirm()
        XCTAssertEqual(store.selection.count, 1)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertTrue(store.activity.last?.summary.contains("Submission failed") == true)
        for i in 0..<105 { await store.scan("invalid-\(i)") }
        XCTAssertEqual(store.activity.count, 100)
        XCTAssertFalse(store.activity.contains { $0.summary == "Checked in" })
    }
}
