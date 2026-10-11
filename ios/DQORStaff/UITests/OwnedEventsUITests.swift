import XCTest

final class OwnedEventsUITests: XCTestCase {
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.midY > app.navigationBars.firstMatch.frame.maxY + 4 && element.frame.midY < app.frame.maxY - 40 { return }
            app.swipeUp()
        }
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.midY > app.navigationBars.firstMatch.frame.maxY + 4 && element.frame.midY < app.frame.maxY - 40 { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    @MainActor private func tap(_ label: String, in app: XCUIApplication) { let button = app.buttons[label]; reveal(button, in: app); button.tap() }
    @MainActor private func fresh(_ app: XCUIApplication) { app.swipeDown(); app.swipeDown(); XCTAssertTrue(app.staticTexts["ownedFresh"].waitForExistence(timeout: 10)) }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
    @MainActor func testBrowseDetailsBack503304WithdrawalRecoveryAndClear() {
        let app = XCUIApplication(); app.launchArguments = ["--owned-events-fixture"]; app.launch()
        fresh(app); XCTAssertTrue(app.staticTexts["ownedPreview"].exists); capture(app, "Owned synthetic event catalog")
        app.buttons["hosted-event-101"].tap()
        XCTAssertTrue(app.staticTexts["ownedTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic organizers"].exists)
        XCTAssertEqual(app.staticTexts["ownedTimeRange"].label, "12:15\u{202f}AM – 1:30\u{202f}AM")
        XCTAssertTrue(app.staticTexts["ownedPreview"].exists)
        XCTAssertTrue(app.buttons["ownedWebsite"].exists)
        capture(app, "Owned synthetic event detail")
        tap("Service unavailable", in: app); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["ownedStale"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ownedTitle"].exists)
        capture(app, "Owned synthetic stale detail")
        tap("Unchanged", in: app); fresh(app)
        XCTAssertFalse(app.staticTexts["ownedStale"].exists)
        tap("Withdraw event", in: app); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["ownedWithdrawn"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ownedTitle"].exists)
        capture(app, "Owned synthetic withdrawn detail")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ownedWithdrawn"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["hosted-event-101"].exists)
        tap("Published", in: app); fresh(app)
        XCTAssertTrue(app.buttons["hosted-event-101"].exists)
        tap("ownedClear", in: app)
        XCTAssertTrue(app.staticTexts["Your local events are cleared."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["hosted-event-101"].exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Your local events are cleared."].exists)
        XCTAssertFalse(app.buttons["hosted-event-101"].exists)
        capture(app, "Owned synthetic cleared after foreground")
        tap("ownedRefresh", in: app); fresh(app)
        XCTAssertTrue(app.buttons["hosted-event-101"].exists)
    }
    @MainActor func testLargestTextDetailAndForegroundRevalidation() {
        let app = XCUIApplication(); app.launchArguments = ["--owned-events-fixture", "--dark-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        fresh(app); reveal(app.buttons["hosted-event-101"], in: app); app.buttons["hosted-event-101"].tap()
        XCTAssertTrue(app.staticTexts["ownedTitle"].waitForExistence(timeout: 10))
        reveal(app.buttons["ownedWebsite"], in: app); XCTAssertTrue(app.buttons["ownedWebsite"].isHittable)
        capture(app, "Owned synthetic detail largest text")
        tap("Service unavailable", in: app); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["ownedStale"].waitForExistence(timeout: 10))
        tap("Published", in: app); fresh(app)
        XCUIDevice.shared.press(.home); app.activate(); fresh(app)
        XCTAssertTrue(app.staticTexts["ownedTitle"].exists)
        capture(app, "Owned synthetic detail foreground revalidated")
    }
}
