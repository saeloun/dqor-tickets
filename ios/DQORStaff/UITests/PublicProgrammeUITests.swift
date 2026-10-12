import XCTest
import UIKit

final class PublicProgrammeUITests: XCTestCase {
    @MainActor
    private func reachable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let navigation = app.navigationBars.firstMatch
        let tabs = app.tabBars.firstMatch
        let top = navigation.exists ? navigation.frame.maxY : app.frame.minY
        let bottom = tabs.exists ? tabs.frame.minY : app.frame.maxY
        return element.frame.midY >= top + 4 && element.frame.midY <= bottom - 4
    }
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, preferTop: Bool = false) {
        for sweep in 0..<2 {
            for _ in 0..<24 {
                if reachable(element, in: app) { return }
                let navigation = app.navigationBars.firstMatch
                let tabs = app.tabBars.firstMatch
                let top = navigation.exists ? navigation.frame.maxY : app.frame.minY
                let bottom = tabs.exists ? tabs.frame.minY : app.frame.maxY
                let height = bottom - top
                guard height > 0 else { break }
                let towardTop: Bool
                if element.exists {
                    if element.frame.midY < top + 4 { towardTop = true }
                    else if element.frame.midY > bottom - 4 { towardTop = false }
                    else { towardTop = preferTop || sweep == 1 }
                } else { towardTop = sweep == 1 }
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let upper = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: top - app.frame.minY + height * 0.2))
                let lower = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: top - app.frame.minY + height * 0.8))
                if towardTop { upper.press(forDuration: 0.05, thenDragTo: lower) }
                else { lower.press(forDuration: 0.05, thenDragTo: upper) }
            }
        }
        XCTAssertTrue(reachable(element, in: app), "Element must have an unobstructed tap point: \(element.identifier)")
    }
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        print("Runner OS accessibility [\(name)]: reduceMotion=\(UIAccessibility.isReduceMotionEnabled), darkerSystemColors=\(UIAccessibility.isDarkerSystemColorsEnabled)")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    private func fresh(_ app: XCUIApplication) {
        reveal(app.staticTexts["programmeFresh"], in: app)
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
        reveal(app.buttons["Offline"], in: app)
        capture(app, "Synthetic Offline control before press")
        print("Synthetic Offline control: \(app.buttons["Offline"].frame) | \(app.buttons["Offline"].label)")
        print(app.debugDescription)
        app.buttons["Offline"].tap()
        capture(app, "Synthetic Offline control after press")
        print(app.debugDescription)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        reveal(app.staticTexts["programmeStale"], in: app, preferTop: true)
        XCTAssertTrue(app.staticTexts["programmeStale"].waitForExistence(timeout: 10))
        capture(app, "Synthetic cached offline status")
        reveal(app.buttons["Unchanged 304"], in: app); app.buttons["Unchanged 304"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown(); fresh(app)
        reveal(app.buttons["Withdraw all"], in: app); app.buttons["Withdraw all"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown(); fresh(app)
        reveal(app.buttons["publicSchedule"], in: app); app.buttons["publicSchedule"].tap()
        reveal(app.staticTexts["No sessions published"], in: app)
        XCTAssertTrue(app.staticTexts["No sessions published"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["publicSave-synthetic-published"].exists)
        capture(app, "Authoritative empty synthetic programme")
        app.navigationBars.buttons["BackButton"].tap()
        reveal(app.buttons["clearPublicProgramme"], in: app); app.buttons["clearPublicProgramme"].tap()
        app.buttons["Cancel"].tap()
        reveal(app.buttons["publicSchedule"], in: app)
        XCTAssertTrue(app.buttons["publicSchedule"].exists)
        reveal(app.buttons["clearPublicProgramme"], in: app)
        app.buttons["clearPublicProgramme"].tap(); app.buttons["Clear local data"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        reveal(app.staticTexts["Your local programme is cleared"], in: app, preferTop: true)
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
        reveal(app.staticTexts["programmeError"], in: app)
        XCTAssertTrue(app.staticTexts["programmeError"].waitForExistence(timeout: 10))
        reveal(app.buttons["refreshPublicProgramme"], in: app)
        XCTAssertTrue(app.buttons["refreshPublicProgramme"].isEnabled)
        XCTAssertFalse(app.buttons["publicSchedule"].exists)
        capture(app, "Largest text initial offline recovery")
        reveal(app.buttons["Published"], in: app); app.buttons["Published"].tap()
        fresh(app)
        reveal(app.buttons["publicSchedule"], in: app)
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
        reveal(app.staticTexts["Your local programme is cleared"], in: app, preferTop: true)
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
        reveal(app.staticTexts["Your local programme is cleared"], in: app, preferTop: true)
        XCTAssertTrue(app.staticTexts["Your local programme is cleared"].waitForExistence(timeout: 5))
        capture(app, "Live public privacy clear")
    }
}
