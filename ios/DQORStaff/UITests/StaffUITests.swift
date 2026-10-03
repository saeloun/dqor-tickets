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
        app.swipeUp(); capture(app, name: "Selected batch"); app.buttons["reviewBatch"].tap()
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
        capture(app, name: "Offline lookup")
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
        capture(app, name: "Unconfirmed submission")
    }
    @MainActor
    func testRoleWithoutCapability() {
        let app = XCUIApplication(); app.launchArguments = ["--finance"]; app.launch()
        app.buttons["staffDemoShortcut"].tap(); app.buttons["day-1"].tap()
        XCTAssertTrue(app.staticTexts["Check-in access unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Scan tickets"].exists)
        capture(app, name: "Role unavailable")
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

    @MainActor
    func testReadOnlyAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["enterDemo"].waitForExistence(timeout: 5))
        func audit(_ name: String) throws {
            var issues: [String] = []
            var actionableIssues: [String] = []
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .dynamicType, .textClipped, .trait]) { issue in
                issues.append("\(issue.auditType.rawValue): \(issue.compactDescription) | \(issue.detailedDescription) | \(issue.element?.label ?? "unknown element")")
                if issue.auditType != .dynamicType { actionableIssues.append(issue.compactDescription) }
                return true
            }
            XCTAssertTrue(actionableIssues.isEmpty, "\(name): \(issues.joined(separator: ", "))")
            let report = XCTAttachment(string: issues.isEmpty ? "No automated findings" : issues.joined(separator: "\n"))
            report.name = "Accessibility audit - \(name)"; report.lifetime = .keepAlways; add(report)
            capture(app, name: "Accessibility - \(name)")
        }
        try audit("Welcome")
        app.buttons["enterDemo"].tap()
        try audit("Event catalog")
        app.buttons["day-1"].tap(); app.buttons["Search attendees"].tap()
        try audit("Lookup")
        app.buttons["demo-001"].tap(); app.swipeUp(); app.buttons["reviewBatch"].tap()
        try audit("Review")
    }

    @MainActor
    func testScannerFallbackAndMixedResults() {
        let app = XCUIApplication(); app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Scan tickets"].tap()
        XCTAssertTrue(app.buttons["Use attendee search"].waitForExistence(timeout: 5))
        capture(app, name: "Scanner fallback")
        app.buttons["Use attendee search"].tap()
        app.buttons["Search attendees"].tap()
        app.buttons["demo-001"].tap(); app.buttons["demo-003"].tap()
        app.swipeUp(); app.buttons["reviewBatch"].tap(); app.buttons["Confirm check-in"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Not eligible for this day"].waitForExistence(timeout: 5))
        capture(app, name: "Mixed outcomes")
    }
    @MainActor
    func testLargestDynamicTypeKeyboardAndCameraFallback() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        }
        reveal(app.buttons["enterDemo"])
        XCTAssertTrue(app.buttons["enterDemo"].isHittable)
        capture(app, name: "Largest text welcome")
        app.buttons["enterDemo"].tap(); reveal(app.buttons["day-1"]); app.buttons["day-1"].tap()
        reveal(app.buttons["Scan tickets"]); app.buttons["Scan tickets"].tap()
        reveal(app.buttons["Use attendee search"])
        XCTAssertTrue(app.buttons["Use attendee search"].isHittable)
        capture(app, name: "Largest text scanner")
        app.buttons["Use attendee search"].tap()
        let field = app.textFields["attendeeSearch"]; reveal(field); field.tap(); field.typeText("Alex\n")
        reveal(app.buttons["demo-001"])
        XCTAssertTrue(app.buttons["demo-001"].exists)
        capture(app, name: "Largest text lookup")
        reveal(app.buttons["demo-001"]); app.buttons["demo-001"].tap()
        reveal(app.buttons["reviewBatch"]); app.buttons["reviewBatch"].tap()
        reveal(app.buttons["Confirm check-in"])
        XCTAssertTrue(app.buttons["Confirm check-in"].isHittable)
        capture(app, name: "Largest text review")
    }

    @MainActor
    func testDuplicateNamesRemainDistinguishable() {
        let app = XCUIApplication(); app.launchArguments = ["--duplicate-names"]; app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap()
        XCTAssertTrue(app.buttons["demo-001"].label.contains("alex@example.test"))
        XCTAssertTrue(app.buttons["demo-004"].label.contains("alex.second@example.test"))
        app.buttons["demo-001"].tap(); app.buttons["demo-004"].tap()
        app.swipeUp(); app.buttons["reviewBatch"].tap()
        XCTAssertTrue(app.staticTexts["review-demo-001"].label.contains("alex@example.test"))
        XCTAssertTrue(app.staticTexts["review-demo-004"].label.contains("alex.second@example.test"))
        capture(app, name: "Duplicate-name review")
    }

    @MainActor
    func testCompanionNavigationPreservesBatchAndIndependentPassStatuses() {
        let app = XCUIApplication(); app.launch()
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap(); app.buttons["demo-001"].tap()
        app.buttons["exploreEvent"].tap(); app.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Community talks"].waitForExistence(timeout: 5))
        capture(app, name: "Companion schedule")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("no-such-session")
        XCTAssertFalse(app.staticTexts["Community talks"].exists)
        capture(app, name: "Schedule empty search")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["exploreEvent"].tap(); app.buttons["Sample passes"].tap()
        XCTAssertTrue(app.staticTexts["Admission"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Available · sample only"].exists)
        XCTAssertTrue(app.staticTexts["Already redeemed · sample only"].exists)
        XCTAssertTrue(app.staticTexts["Not included"].exists)
        capture(app, name: "Companion sample pass")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        app.navigationBars.buttons["BackButton"].tap()
        app.swipeUp(); app.buttons["reviewBatch"].tap(); app.buttons["Confirm check-in"].tap()
        app.buttons["exploreEvent"].tap(); app.buttons["Activity history"].tap()
        XCTAssertTrue(app.staticTexts["Checked in"].waitForExistence(timeout: 5))
        capture(app, name: "Companion activity history")
        app.buttons["Look up attendee"].tap()
        XCTAssertTrue(app.buttons["demo-001"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["demo-001"].value as? String, "Not selected")
    }

    @MainActor
    func testCompanionLargestTextAndEmptyHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        }
        reveal(app.buttons["enterDemo"]); app.buttons["enterDemo"].tap()
        reveal(app.buttons["day-1"]); app.buttons["day-1"].tap()
        app.buttons["exploreEvent"].tap(); app.buttons["Sample passes"].tap()
        capture(app, name: "Largest text sample pass header")
        reveal(app.staticTexts["Not included"])
        XCTAssertTrue(app.staticTexts["Not included"].isHittable)
        capture(app, name: "Largest text independent entitlements")
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["exploreEvent"].tap(); app.buttons["Activity history"].tap()
        reveal(app.staticTexts["No activity for this day"])
        XCTAssertTrue(app.staticTexts["No activity for this day"].exists)
        capture(app, name: "Largest text empty history")
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Events"].tap()
        reveal(app.buttons["workshop-1"]); app.buttons["workshop-1"].tap()
        app.buttons["exploreEvent"].tap(); app.buttons["Schedule"].tap()
        reveal(app.staticTexts["Hands-on design studio"])
        XCTAssertTrue(app.staticTexts["Hands-on design studio"].exists)
        capture(app, name: "Largest text workshop schedule")
    }

    @MainActor
    func testAttendeeEventAndPassDesignJourney() {
        let app = XCUIApplication(); app.launch()
        capture(app, name: "Premium attendee welcome")
        app.buttons["exploreSampleEvent"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic preview"].waitForExistence(timeout: 5))
        capture(app, name: "Attendee event artwork and identity")
        app.swipeUp()
        capture(app, name: "Attendee event metadata and actions")
        app.buttons["eventSamplePass"].tap()
        XCTAssertTrue(app.staticTexts["Admission"].waitForExistence(timeout: 5))
        capture(app, name: "Attendee ticket card")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Not included"].exists)
        capture(app, name: "Attendee separate pass states")
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["eventSchedule"].tap()
        capture(app, name: "Attendee programme")
        app.navigationBars.buttons["BackButton"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["enterDemo"].exists)
    }
    @MainActor
    func testAttendeeLargestTextDarkNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--dark-preview"]
        app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        }
        reveal(app.buttons["exploreSampleEvent"]); app.buttons["exploreSampleEvent"].tap()
        reveal(app.buttons["eventSamplePass"])
        capture(app, name: "Attendee largest text dark event")
        app.buttons["eventSamplePass"].tap()
        reveal(app.staticTexts["Not included"])
        XCTAssertTrue(app.staticTexts["Not included"].isHittable)
        capture(app, name: "Attendee largest text dark pass")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["eventSamplePass"].exists)
    }

    @MainActor
    func testSavedScheduleRepeatedTapsBackAndReducedMotion() {
        let app = XCUIApplication()
        app.launchArguments = ["--reduce-motion-preview", "--offline"]
        app.launch()
        app.buttons["exploreSampleEvent"].tap()
        app.swipeUp()
        app.buttons["eventSchedule"].tap()
        let saved = app.segmentedControls["scheduleFilter"].buttons["Saved"]
        saved.tap()
        XCTAssertTrue(app.staticTexts["Your evening, your way"].waitForExistence(timeout: 5))
        capture(app, name: "Premium saved schedule empty reduced motion")
        app.buttons["Explore all sessions"].tap()
        let bookmark = app.buttons["save-afterhours-welcome"]
        bookmark.tap()
        XCTAssertEqual(bookmark.value as? String, "Saved")
        bookmark.tap()
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        bookmark.tap()
        saved.tap()
        XCTAssertTrue(app.staticTexts["Settle in"].exists)
        XCTAssertFalse(app.staticTexts["Ideas & encounters"].exists)
        capture(app, name: "Premium saved schedule reduced motion")
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["eventSchedule"].tap()
        app.segmentedControls["scheduleFilter"].buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Settle in"].exists)
        app.buttons["save-afterhours-welcome"].tap()
        XCTAssertTrue(app.staticTexts["Your evening, your way"].exists)
        app.navigationBars.buttons["BackButton"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.terminate()
        app.launch()
        app.buttons["exploreSampleEvent"].tap()
        app.swipeUp()
        app.buttons["eventSchedule"].tap()
        app.segmentedControls["scheduleFilter"].buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Your evening, your way"].exists)
    }

}
