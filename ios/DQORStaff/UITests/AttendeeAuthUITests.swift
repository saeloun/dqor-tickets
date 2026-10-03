import XCTest

final class AttendeeAuthUITests: XCTestCase {
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        for _ in 0..<16 { if element.isHittable { return }; app.swipeDown() }
        XCTAssertTrue(element.isHittable, "Account action must be reachable")
    }
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    private func open(_ app: XCUIApplication, extra: [String] = [], synthetic: Bool = true) {
        app.launchArguments = ["--public-fixture", "--reduce-motion-preview"] + (synthetic ? ["--attendee-auth-fixture"] : []) + extra
        app.launch(); XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
        reveal(app.buttons["attendeeAccount"], in: app); app.buttons["attendeeAccount"].tap()
    }
    @MainActor
    func testProductionClosedAccountShowsOnlyOfficialWebsiteFallback() {
        let app = XCUIApplication(); open(app, synthetic: false)
        XCTAssertTrue(app.staticTexts["attendeeUnavailable"].exists); XCTAssertFalse(app.buttons["attendeeSignIn"].exists); XCTAssertFalse(app.staticTexts["Synthetic account rehearsal"].exists)
        reveal(app.buttons["attendeeOfficialAccount"], in: app); XCTAssertTrue(app.buttons["attendeeOfficialAccount"].isHittable)
        capture("Closed native account official website fallback")
        app.navigationBars.buttons["BackButton"].tap(); XCTAssertTrue(app.buttons["attendeeAccount"].exists)
    }
    @MainActor
    func testSyntheticExternalReturnPaginationOfflineLogoutAndRestart() {
        let app = XCUIApplication(); open(app)
        app.buttons["attendeeSignIn"].tap(); XCTAssertFalse(app.buttons["attendeeSignIn"].exists)
        reveal(app.buttons["Return wrong state"], in: app); app.buttons["Return wrong state"].tap()
        XCTAssertTrue(app.staticTexts["attendeeMessage"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        reveal(app.buttons["attendeeSignIn"], in: app); app.buttons["attendeeSignIn"].tap()
        reveal(app.buttons["Simulate external browser return"], in: app); app.buttons["Simulate external browser return"].tap()
        XCTAssertTrue(app.staticTexts["attendeeName"].waitForExistence(timeout: 5))
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        capture("Synthetic private account no credential")
        reveal(app.buttons["attendeeLoadMore"], in: app); app.buttons["attendeeLoadMore"].tap()
        let fourthPass = app.staticTexts.matching(identifier: "attendeePass-4").matching(NSPredicate(format: "label == %@", "Expired")).firstMatch
        reveal(fourthPass, in: app); XCTAssertTrue(fourthPass.exists); XCTAssertEqual(fourthPass.label, "Expired")
        capture("Synthetic read-only pass status pagination")
        reveal(app.buttons["attendeeScenario-Offline"], in: app); app.buttons["attendeeScenario-Offline"].tap()
        reveal(app.staticTexts["attendeeMessage"], in: app); XCTAssertTrue(app.staticTexts["attendeeMessage"].exists)
        XCTAssertEqual(app.staticTexts["attendeeMessage"].label, "Connection unavailable. Private information has not been revalidated.")
        reveal(app.staticTexts.matching(identifier: "attendeeFreshness").firstMatch, in: app)
        XCTAssertEqual(app.staticTexts["attendeeFreshness"].label, "Saved in memory · not revalidated")
        capture("Synthetic offline private information unvalidated")
        app.buttons["attendeeLogoutToolbar"].tap(); XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        reveal(app.buttons["attendeeRevokeRetry"], in: app); capture("Synthetic offline logout local clearing")
        app.terminate(); app.launch(); XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
        reveal(app.buttons["attendeeAccount"], in: app); app.buttons["attendeeAccount"].tap()
        XCTAssertFalse(app.staticTexts["attendeeName"].exists); XCTAssertTrue(app.buttons["attendeeSignIn"].exists)
    }
    @MainActor
    func testSlowExchangeCancelBackAndForegroundCannotRestoreIdentity() {
        let app = XCUIApplication(); open(app)
        reveal(app.buttons["attendeeScenario-Slow response"], in: app)
        app.buttons["attendeeScenario-Slow response"].tap()
        reveal(app.buttons["attendeeSignIn"], in: app); app.buttons["attendeeSignIn"].tap()
        reveal(app.buttons["Approve synthetic return"], in: app); app.buttons["Approve synthetic return"].tap()
        XCTAssertTrue(app.buttons["attendeeCancelToolbar"].waitForExistence(timeout: 3)); app.buttons["attendeeCancelToolbar"].tap()
        XCTAssertTrue(app.buttons["attendeeSignIn"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        capture("Synthetic slow exchange explicit cancellation")
        app.buttons["attendeeSignIn"].tap(); app.navigationBars.buttons["BackButton"].tap()
        app.buttons["attendeeAccount"].tap(); XCTAssertTrue(app.buttons["attendeeSignIn"].exists)
        XCUIDevice.shared.press(.home); app.activate(); XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        capture("Synthetic Back and foreground private state remains clear")
    }
    @MainActor
    func testInjectedOlderIOSPolicyLargestTextOfficialFallback() {
        let app = XCUIApplication(); open(app, extra: ["--attendee-older-policy", "--dark-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.staticTexts["attendeeUnavailable"].exists); XCTAssertFalse(app.buttons["attendeeSignIn"].exists)
        reveal(app.buttons["attendeeOfficialAccount"], in: app); XCTAssertTrue(app.buttons["attendeeOfficialAccount"].isHittable)
        capture("Injected older-iOS availability policy on actual iOS26.5 simulator")
    }
}
