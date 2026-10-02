import XCTest
final class StaffUITests: XCTestCase {
    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    func testSearchCancelConfirmAndBack() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["enterDemo"].waitForExistence(timeout: 5))
        capture(app, name: "Welcome")
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap()
        capture(app, name: "Attendee lookup")
        app.buttons["demo-001"].tap()
        app.swipeUp(); app.buttons["reviewBatch"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture(app, name: "Review batch")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["reviewBatch"].exists)
        app.buttons["reviewBatch"].tap(); app.buttons["Confirm check-in"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Checked in"].waitForExistence(timeout: 5))
        capture(app, name: "Confirmed result")
        app.buttons["Events"].tap()
        XCTAssertTrue(app.buttons["day-2"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testOfflineSearchShowsFailure() {
        let app = XCUIApplication(); app.launchArguments = ["--offline"]; app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap()
        XCTAssertTrue(app.staticTexts["statusMessage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
    }
    @MainActor
    func testFailedCheckInRetainsBatch() {
        let app = XCUIApplication(); app.launchArguments = ["--fail-checkin"]; app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap(); app.buttons["demo-001"].tap()
        app.swipeUp(); app.buttons["reviewBatch"].tap(); app.buttons["Confirm check-in"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["statusMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reviewBatch"].exists)
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
    }
    @MainActor
    func testRoleWithoutCapability() {
        let app = XCUIApplication(); app.launchArguments = ["--finance"]; app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        XCTAssertTrue(app.staticTexts["Check-in access unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Scan tickets"].exists)
    }

    @MainActor
    func testBackRequiresDiscardingUnsubmittedBatch() {
        let app = XCUIApplication(); app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap(); app.buttons["demo-001"].tap()
        app.buttons["Events"].tap()
        XCTAssertTrue(app.buttons["Discard batch"].waitForExistence(timeout: 5))
        app.buttons["Discard batch"].tap()
        XCTAssertTrue(app.buttons["day-2"].waitForExistence(timeout: 5))
        capture(app, name: "Event catalog")
        app.buttons["day-1"].tap()
        XCTAssertFalse(app.buttons["reviewBatch"].exists)
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
    }

}
