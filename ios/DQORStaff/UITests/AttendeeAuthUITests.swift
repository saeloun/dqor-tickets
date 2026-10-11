import XCTest
import UIKit

final class AttendeeAuthUITests: XCTestCase {
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
    private func capture(_ name: String) {
        print("Runner OS accessibility [\(name)]: reduceMotion=\(UIAccessibility.isReduceMotionEnabled), darkerSystemColors=\(UIAccessibility.isDarkerSystemColorsEnabled)")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    private func auditContrast(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: .contrast) { issue in
            if let element = issue.element { print("Contrast audit node: \(element.identifier) | \(element.label) | \(element.frame)") }
            return false
        }
    }
    @MainActor
    private func open(_ app: XCUIApplication, extra: [String] = [], synthetic: Bool = true) {
        app.launchArguments = ["--public-fixture", "--reduce-motion-preview"] + (synthetic ? ["--attendee-auth-fixture"] : []) + extra
        app.launch(); reveal(app.staticTexts["programmeFresh"], in: app); XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
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
    func testSyntheticCancelBannerHasVisibleAccessibilityBounds() {
        let app = XCUIApplication(); open(app)
        reveal(app.buttons["attendeeSignIn"], in: app); app.buttons["attendeeSignIn"].tap()
        XCTAssertTrue(app.buttons["attendeeCancelToolbar"].waitForExistence(timeout: 3))
        app.buttons["attendeeCancelToolbar"].tap()
        XCTAssertTrue(app.buttons["attendeeSignIn"].waitForExistence(timeout: 5))
        let message = app.staticTexts["attendeeMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "Sign-in canceled.")
        print(app.debugDescription)
        XCTAssertGreaterThanOrEqual(message.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(message.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("Synthetic canceled sign-in banner visible accessibility bounds")
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
        app.tabBars.buttons["Pass"].tap()
        reveal(app.buttons["attendeeLoadMore"], in: app); app.buttons["attendeeLoadMore"].tap()
        capture("Synthetic pass pagination immediately after load more")
        print(app.debugDescription)
        let fourthPass = app.staticTexts.matching(identifier: "attendeePass-4").matching(NSPredicate(format: "label == %@", "Expired")).firstMatch
        reveal(fourthPass, in: app); XCTAssertTrue(fourthPass.exists); XCTAssertEqual(fourthPass.label, "Expired")
        capture("Synthetic read-only pass status pagination")
        app.tabBars.buttons["You"].tap()
        reveal(app.buttons["attendeeScenario-Offline"], in: app); app.buttons["attendeeScenario-Offline"].tap()
        let offlineMessage = app.staticTexts["attendeeMessage"]
        XCTAssertTrue(offlineMessage.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(offlineMessage.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(offlineMessage.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertTrue(app.staticTexts["attendeeMessage"].exists)
        XCTAssertEqual(app.staticTexts["attendeeMessage"].label, "Connection unavailable. Private information has not been revalidated.")
        reveal(app.staticTexts.matching(identifier: "attendeeFreshness").firstMatch, in: app)
        XCTAssertEqual(app.staticTexts["attendeeFreshness"].label, "Saved in memory · not revalidated")
        capture("Synthetic offline private information unvalidated")
        app.buttons["attendeeLogoutToolbar"].tap(); XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        reveal(app.buttons["attendeeRevokeRetry"], in: app); capture("Synthetic offline logout local clearing")
        app.terminate(); app.launch(); reveal(app.staticTexts["programmeFresh"], in: app); XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
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
        reveal(app.staticTexts["attendeeUnavailable"], in: app)
        XCTAssertTrue(app.staticTexts["attendeeUnavailable"].exists); XCTAssertFalse(app.buttons["attendeeSignIn"].exists)
        reveal(app.buttons["attendeeOfficialAccount"], in: app); XCTAssertTrue(app.buttons["attendeeOfficialAccount"].isHittable)
        capture("Injected older-iOS availability policy on actual iOS26.5 simulator")
    }
    @MainActor
    func testMinimalistTabsPreserveSavedFiltersAndCancelPendingSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--attendee-auth-fixture", "--reduce-motion-preview"]
        app.launch()
        reveal(app.staticTexts["programmeFresh"], in: app)
        XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
        capture("DQOR minimalist synthetic Home")
        app.tabBars.buttons["Programme"].tap()
        let saved = app.buttons["publicSave-synthetic-published"]
        reveal(saved, in: app)
        if saved.value as? String == "Saved" { saved.tap() }
        saved.tap()
        reveal(app.segmentedControls["publicScheduleFilter"], in: app)
        app.segmentedControls["publicScheduleFilter"].buttons["Saved"].tap()
        app.tabBars.buttons["Pass"].tap()
        reveal(app.buttons["attendeeOfficialTickets"], in: app)
        XCTAssertTrue(app.buttons["attendeeOfficialTickets"].isHittable)
        XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        capture("DQOR Pass official credential access without fake QR")
        app.tabBars.buttons["Programme"].tap()
        XCTAssertTrue(app.segmentedControls["publicScheduleFilter"].buttons["Saved"].isSelected)
        reveal(saved, in: app)
        XCTAssertEqual(saved.value as? String, "Saved")
        XCTAssertFalse(app.staticTexts["Synthetic unscheduled session"].exists)
        app.tabBars.buttons["You"].tap()
        app.buttons["attendeeSignIn"].tap()
        XCTAssertTrue(app.buttons["attendeeCancelToolbar"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.buttons["attendeeSignIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["attendeeName"].exists)
        capture("DQOR tab leave cancels synthetic sign-in")
        app.tabBars.buttons["Home"].tap()
        app.buttons["clearPublicProgrammeToolbar"].tap()
        app.buttons["Clear local data"].tap()
        XCTAssertTrue(app.staticTexts["Your local programme is cleared"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testSupportedProfileServicesAndWebsiteFailureAtLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--website-action-failure", "--dark-preview", "--reduce-motion-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        reveal(app.staticTexts["programmeFresh"], in: app)
        XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
        app.tabBars.buttons["You"].tap()
        reveal(app.staticTexts["attendeeUnavailable"], in: app)
        XCTAssertTrue(app.staticTexts["attendeeUnavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["attendeeSignIn"].exists)
        for key in ["profile", "visibility", "preferences", "security", "help", "contact", "conduct"] {
            let action = app.buttons["website-" + key]
            reveal(action, in: app)
            XCTAssertTrue(action.isEnabled)
            XCTAssertGreaterThanOrEqual(action.frame.height, 48)
        }
        let profile = app.buttons["website-profile"]
        reveal(profile, in: app); profile.tap()
        let failure = app.staticTexts["websiteOpenFailure-profile"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        profile.tap()
        XCTAssertTrue(profile.isEnabled)
        XCTAssertTrue(profile.label.contains("Edit your profile"))
        XCTAssertTrue(profile.label.contains("social links"))
        XCTAssertTrue(failure.exists)
        capture("DQOR supported profile services MAX dark browser failure")
        app.tabBars.buttons["Pass"].tap()
        let tickets = app.buttons["attendeeOfficialTickets"]
        reveal(tickets, in: app); tickets.tap()
        XCTAssertTrue(app.staticTexts["websiteOpenFailure-tickets"].waitForExistence(timeout: 5))
        capture("DQOR actual ticket handoff failure remains recoverable")
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["programmeFresh"].exists)
    }

    @MainActor
    func testMinimalistSurfacesKeepTextContrastAndPublicHelpAccess() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture", "--reduce-motion-preview"]
        app.launch()
        reveal(app.staticTexts["programmeFresh"], in: app)
        XCTAssertTrue(app.staticTexts["programmeFresh"].waitForExistence(timeout: 10))
        try auditContrast(app)
        capture("DQOR minimalist Home contrast")
        app.swipeUp(); try auditContrast(app)
        reveal(app.buttons["offlineDemo"], in: app); try auditContrast(app)
        capture("DQOR Home lower services contrast")
        app.tabBars.buttons["Pass"].tap()
        try auditContrast(app)
        capture("DQOR minimalist Pass contrast")
        app.swipeUp(); try auditContrast(app)
        reveal(app.buttons["website-help"], in: app); try auditContrast(app)
        capture("DQOR Pass lower services contrast")
        app.tabBars.buttons["You"].tap()
        try auditContrast(app)
        capture("DQOR minimalist You contrast")
        app.swipeUp(); try auditContrast(app)
        reveal(app.buttons["website-conduct"], in: app); try auditContrast(app)
        capture("DQOR You lower services contrast")
        let help = app.buttons["website-help"]
        reveal(help, in: app); help.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(safari.webViews.staticTexts["Frequently asked questions"].waitForExistence(timeout: 15))
        capture("Official public help opens in owned simulator Safari")
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["attendeeName"].exists)
    }

    @MainActor
    func testHomeStaffDemoEntryAndBackRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--public-fixture"]
        app.launch()
        reveal(app.buttons["offlineDemo"], in: app)
        app.buttons["offlineDemo"].tap()
        XCTAssertTrue(app.buttons["staffDemoShortcut"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reviewBatch"].exists)
        XCTAssertFalse(app.buttons["Confirm check-in"].exists)
        capture("DQOR Home enters clearly separate offline staff demo")
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "DQOR", "Back")).firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        reveal(app.buttons["homeHeroProgramme"], in: app)
        XCTAssertTrue(app.buttons["homeHeroProgramme"].isHittable)
        capture("DQOR staff demo Back restores Home")
    }

}
