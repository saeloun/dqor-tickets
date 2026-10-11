import XCTest

final class PublicProgrammeUITests: XCTestCase {
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            if element.exists && element.frame.maxY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "Element must be reachable: \(element.identifier)")
    }
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    private func fresh(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 15))
    }
    @MainActor
    func testFixtureSavingDetailsSearchBackOffline304WithdrawalAndClear() {
        let app = XCUIApplication(); app.launchArguments = ["--public-fixture", "--reduce-motion-preview"]; app.launch()
        fresh(app); capture(app, "Synthetic public home")
        XCTAssertFalse(app.buttons["enterDemo"].exists)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        let bookmark = app.buttons["publicSave-synthetic-published"]
        reveal(bookmark, in: app); bookmark.tap(); XCTAssertEqual(bookmark.value as? String, "Saved")
        bookmark.tap(); XCTAssertEqual(bookmark.value as? String, "Not saved")
        bookmark.tap()
        reveal(app.buttons["publicDetails-synthetic-published"], in: app); app.buttons["publicDetails-synthetic-published"].tap()
        XCTAssertTrue(app.staticTexts["A synthetic session used to rehearse navigation and saving. It is not part of the live programme."].exists)
        capture(app, "Synthetic expanded session reduced motion")
        app.swipeDown(); app.segmentedControls["publicScheduleFilter"].buttons["Saved"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic unscheduled session"].exists)
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["publicSchedule"].tap()
        app.segmentedControls["publicScheduleFilter"].buttons["All sessions"].tap()
        let search = app.textFields["publicProgrammeSearch"]; reveal(search, in: app); search.tap(); search.typeText("unscheduled\n")
        XCTAssertTrue(app.staticTexts["Synthetic unscheduled session"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic published session"].exists)
        reveal(app.staticTexts["Time to be announced"], in: app)
        capture(app, "Synthetic unscheduled search")
        app.navigationBars.buttons["BackButton"].tap()
        reveal(app.buttons["Offline"], in: app); app.buttons["Offline"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["programmeStale"].waitForExistence(timeout: 10))
        capture(app, "Synthetic cached offline status")
        reveal(app.buttons["Unchanged 304"], in: app); app.buttons["Unchanged 304"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown(); fresh(app)
        reveal(app.buttons["Withdraw all"], in: app); app.buttons["Withdraw all"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown(); fresh(app)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        XCTAssertTrue(app.staticTexts["No sessions published"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["publicSave-synthetic-published"].exists)
        capture(app, "Authoritative empty synthetic programme")
        app.navigationBars.buttons["BackButton"].tap()
        reveal(app.buttons["clearPublicProgramme"], in: app); app.buttons["clearPublicProgramme"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["publicSchedule"].exists)
        app.buttons["clearPublicProgramme"].tap(); app.buttons["Clear local data"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["Your local programme is cleared"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.staticTexts["programmeFresh"].exists)
        capture(app, "Privacy clear survives foreground")
    }
    @MainActor
    func testPaddedSearchAndOneTapRecoveryPreserveSavedSessions() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--reduce-motion-preview"]
        app.launch(); fresh(app)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        reveal(app.buttons["publicSave-synthetic-published"], in: app)
        app.buttons["publicSave-synthetic-published"].tap()
        let search = app.textFields["publicProgrammeSearch"]
        reveal(search, in: app); search.tap(); search.typeText("  unscheduled  \n")
        capture(app, "Padded synthetic search before recovery")
        XCTAssertTrue(app.staticTexts["Synthetic unscheduled session"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic published session"].exists)
        let clear = app.buttons["publicClearSearch"]
        reveal(clear, in: app); XCTAssertGreaterThanOrEqual(clear.frame.height, 48); clear.tap()
        reveal(search, in: app); search.tap(); search.typeText("   \n")
        XCTAssertFalse(app.staticTexts["No matching sessions"].exists)
        reveal(app.staticTexts["Synthetic unscheduled session"], in: app)
        reveal(clear, in: app); clear.tap()
        XCTAssertFalse(app.staticTexts["No matching sessions"].exists)
        reveal(app.buttons["publicSave-synthetic-published"], in: app)
        XCTAssertEqual(app.buttons["publicSave-synthetic-published"].value as? String, "Saved")
        reveal(search, in: app); search.tap(); search.typeText("no matching programme\n")
        XCTAssertTrue(app.staticTexts["No matching sessions"].waitForExistence(timeout: 5))
        let reset = app.buttons["publicResetFilters"]
        reveal(reset, in: app)
        XCTAssertGreaterThanOrEqual(reset.frame.height, 48)
        capture(app, "Synthetic no-match one-tap recovery")
        reset.tap()
        XCTAssertFalse(app.staticTexts["No matching sessions"].exists)
        reveal(app.buttons["publicSave-synthetic-published"], in: app)
        XCTAssertEqual(app.buttons["publicSave-synthetic-published"].value as? String, "Saved")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["publicSchedule"].exists)
    }
    @MainActor
    func testLargestTextDarkSearchResetPreservesBookmarksAndBack() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--dark-preview", "--reduce-motion-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); fresh(app)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        reveal(app.buttons["publicSave-synthetic-published"], in: app)
        app.buttons["publicSave-synthetic-published"].tap()
        reveal(app.segmentedControls["publicScheduleFilter"], in: app)
        app.segmentedControls["publicScheduleFilter"].buttons["Saved"].tap()
        let day = app.buttons["publicDayFilter"]
        reveal(day, in: app); day.tap(); app.buttons["Thu, 8 Oct"].tap()
        let search = app.textFields["publicProgrammeSearch"]
        reveal(search, in: app); search.tap(); search.typeText("unmatched\n")
        reveal(app.staticTexts["No matching sessions"], in: app)
        let reset = app.buttons["publicResetFilters"]
        reveal(reset, in: app)
        XCTAssertGreaterThanOrEqual(reset.frame.height, 48)
        capture(app, "Largest text dark synthetic search recovery")
        reset.tap()
        reveal(app.buttons["publicSave-synthetic-published"], in: app)
        XCTAssertEqual(app.buttons["publicSave-synthetic-published"].value as? String, "Saved")
        XCTAssertFalse(app.staticTexts["No matching sessions"].exists)
        reveal(app.staticTexts["Synthetic unscheduled session"], in: app)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["publicSchedule"].exists)
    }
    @MainActor
    func testInitialOfflineLargestTextMakesRecoveryReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--public-offline", "--reduce-motion-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["programmeError"].waitForExistence(timeout: 10))
        reveal(app.buttons["refreshPublicProgramme"], in: app)
        XCTAssertTrue(app.buttons["refreshPublicProgramme"].isEnabled)
        XCTAssertFalse(app.buttons["publicSchedule"].exists)
        capture(app, "Largest text initial offline recovery")
        reveal(app.buttons["Published"], in: app); app.buttons["Published"].tap()
        fresh(app)
        XCTAssertTrue(app.buttons["publicSchedule"].exists)
    }
    @MainActor
    func testLargestTextDarkProgrammeAndSlowRefreshClear() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--dark-preview", "--reduce-motion-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); fresh(app)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        reveal(app.buttons["publicSave-synthetic-published"], in: app)
        capture(app, "Largest text dark synthetic programme")
        app.buttons["publicSave-synthetic-published"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        reveal(app.buttons["Slow response"], in: app); app.buttons["Slow response"].tap()
        XCTAssertFalse(app.buttons["Slow response"].isEnabled)
        app.buttons["clearPublicProgrammeToolbar"].tap(); app.buttons["Clear local data"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["Your local programme is cleared"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["programmeFresh"].exists)
        reveal(app.buttons["refreshPublicProgramme"], in: app)
        XCTAssertTrue(app.buttons["refreshPublicProgramme"].isEnabled)
        capture(app, "Largest text clear cancels slow refresh")
    }
    @MainActor
    func testLivePublicProgrammeSaveRestartForegroundAndPrivacyClear() throws {
        guard ProcessInfo.processInfo.environment["DQOR_RUN_LIVE_PUBLIC_SMOKE"] == "1" else { throw XCTSkip("Live read is explicitly opt-in") }
        let app = XCUIApplication(); app.launch(); fresh(app)
        XCTAssertEqual(app.staticTexts["publicEventTitle"].label, "Deccan Queen on Rails 2026")
        XCTAssertFalse(app.staticTexts["Synthetic preview"].exists)
        capture(app, "Live production DQOR public event")
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        let bookmark = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'publicSave-'")).firstMatch
        reveal(bookmark, in: app)
        let identifier = bookmark.identifier
        if bookmark.value as? String == "Saved" { bookmark.tap() }
        bookmark.tap(); XCTAssertEqual(bookmark.value as? String, "Saved")
        capture(app, "Live production DQOR programme")
        app.terminate(); app.launch(); fresh(app)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        app.segmentedControls["publicScheduleFilter"].buttons["Saved"].tap()
        XCTAssertTrue(app.buttons[identifier].exists)
        XCTAssertEqual(app.buttons[identifier].value as? String, "Saved")
        capture(app, "Live saved session survives cold restart")
        XCUIDevice.shared.press(.home); app.activate(); fresh(app)
        app.navigationBars.buttons["BackButton"].tap()
        reveal(app.buttons["clearPublicProgramme"], in: app); app.buttons["clearPublicProgramme"].tap(); app.buttons["Clear local data"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["Your local programme is cleared"].waitForExistence(timeout: 5))
        capture(app, "Live public privacy clear")
    }
}
