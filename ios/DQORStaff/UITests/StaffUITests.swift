import XCTest
final class StaffUITests: XCTestCase {
    @MainActor
    private func launchDemo(_ app: XCUIApplication) {
        if !app.launchArguments.contains("--demo") { app.launchArguments.append("--demo") }
        app.launch()
    }
    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    private func revealStaffListElement(_ identifier: String, in app: XCUIApplication, button: Bool = true, scrollUp: Bool = true) {
        for attempt in 0..<20 {
            guard let list = app.collectionViews.allElementsBoundByIndex.last else { XCTFail("No active staff list"); return }
            let listFrame = list.frame
            let top = max(listFrame.minY, app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? listFrame.minY) + 8
            let bottom = min(app.frame.maxY, listFrame.maxY)
            let usable = CGRect(x: listFrame.minX, y: top, width: listFrame.width, height: max(0, bottom - top))
            guard usable.height > 0 else { XCTFail("No visible staff list area"); return }
            let element = button ? app.buttons[identifier] : app.staticTexts[identifier]
            var down = !scrollUp
            if element.exists {
                let frame = element.frame
                if element.isHittable && usable.contains(frame) {
                    let geometry = XCTAttachment(string: "target=\(frame); usable=\(usable); ordinary drags=\(attempt)")
                    geometry.name = "Visible staff target \(identifier)"; geometry.lifetime = .keepAlways; add(geometry)
                    capture(app, name: "Visible staff target \(identifier)")
                    return
                }
                down = frame.minY < usable.minY
            }
            let delta = usable.height * 0.1
            let origin = list.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: usable.midX - listFrame.minX, dy: usable.midY + (down ? -delta : delta) - listFrame.minY))
            let end = origin.withOffset(CGVector(dx: usable.midX - listFrame.minX, dy: usable.midY + (down ? delta : -delta) - listFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Staff target \(identifier) did not become fully visible after 20 ordinary drags")
    }
    @MainActor
    func testContinuousScannerRehearsalPreviewRepeatCancelMixedAndBackground() {
        let app = XCUIApplication(); app.launchArguments = ["--scanner-rehearsal"]; launchDemo(app)
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap(); app.buttons["Scan tickets"].tap()
        XCTAssertTrue(app.buttons["Scan sample Alex"].waitForExistence(timeout: 5))
        app.buttons["Scan sample Alex"].tap()
        XCTAssertTrue(app.staticTexts["1 in batch"].waitForExistence(timeout: 5))
        app.buttons["Scan sample Alex"].tap()
        XCTAssertTrue(app.staticTexts["1 in batch"].exists)
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
        app.buttons["Scan invalid sample"].tap()
        XCTAssertTrue(app.staticTexts["Ticket not recognized. Try attendee search or ask an administrator."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 in batch"].exists)
        app.buttons["Scan sample Taylor"].tap()
        XCTAssertTrue(app.staticTexts["2 in batch"].waitForExistence(timeout: 5))
        let manual = app.buttons["Use attendee search"]
        XCTAssertTrue(manual.isHittable)
        XCTAssertGreaterThanOrEqual(manual.frame.height, 48)
        let geometry = XCTAttachment(string: "Light manual lookup accessible frame: \(manual.frame)")
        geometry.name = "Light scanner manual lookup geometry"; geometry.lifetime = .keepAlways; add(geometry)
        capture(app, name: "Synthetic continuous scanner rehearsal")
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeReady = NSPredicate { _, _ in
            app.frame.width > app.frame.height && app.buttons["Done"].isHittable
        }
        let landscapeExpectation = expectation(for: landscapeReady, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeExpectation], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["Done"].exists)
        let landscapeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeAttachment.name = "Synthetic scanner landscape layout"
        landscapeAttachment.lifetime = .keepAlways
        add(landscapeAttachment)
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.press(.home); app.activate()
        let portraitReady = NSPredicate { _, _ in
            app.state == .runningForeground && app.frame.height > app.frame.width &&
                app.buttons["Done"].isHittable && app.buttons["Scan sample Alex"].isHittable
        }
        let portraitExpectation = expectation(for: portraitReady, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portraitExpectation], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["2 in batch"].exists)
        app.buttons["Done"].tap()
        let scannerDismissed = expectation(for: NSPredicate { _, _ in !app.buttons["Done"].exists }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [scannerDismissed], timeout: 5), .completed)
        let review = app.buttons["reviewBatch"]
        for _ in 0..<8 {
            if review.isHittable { break }
            app.swipeUp()
        }
        let reviewReady = expectation(for: NSPredicate { _, _ in review.isHittable }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [reviewReady], timeout: 5), .completed)
        review.tap()
        XCTAssertTrue(app.staticTexts["Confirm event admission and day"].exists)
        app.buttons["Cancel"].tap(); app.buttons["reviewBatch"].tap(); app.buttons["Confirm check-in"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Checked in"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not eligible for this day"].exists)
        capture(app, name: "Synthetic scanner explicit admission outcomes")
        app.swipeDown(); app.swipeDown(); app.buttons["Scan tickets"].tap()
        app.buttons["Scan sample Alex"].tap(); app.buttons["Done"].tap(); app.swipeUp(); app.buttons["reviewBatch"].tap(); app.buttons["Confirm check-in"].tap()
        app.swipeUp(); XCTAssertTrue(app.staticTexts["Already checked in"].waitForExistence(timeout: 5))
        app.buttons["Events"].tap(); app.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["enterDemo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
    }
    @MainActor
    func testDarkScannerManualLookupRemainsReadableAndReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--dark-preview", "--scanner-rehearsal", "--reduce-motion-preview"]
        launchDemo(app)
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap(); app.buttons["Scan tickets"].tap()
        let manual = app.buttons["Use attendee search"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        XCTAssertTrue(manual.isHittable)
        XCTAssertGreaterThanOrEqual(manual.frame.height, 48)
        let geometry = XCTAttachment(string: "Dark manual lookup accessible frame: \(manual.frame)")
        geometry.name = "Dark scanner manual lookup geometry"; geometry.lifetime = .keepAlways; add(geometry)
        capture(app, name: "Dark synthetic scanner manual lookup")
        manual.tap()
        XCTAssertTrue(app.textFields["attendeeSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
    }
    @MainActor
    func testDeniedScannerRetryAndManualFallbackRemainFailClosed() {
        let app = XCUIApplication(); app.launchArguments = ["--scanner-camera-denied", "--offline"]; launchDemo(app)
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap(); app.buttons["Scan tickets"].tap()
        XCTAssertTrue(app.buttons["Open camera settings"].waitForExistence(timeout: 5))
        app.buttons["Retry camera"].tap()
        XCTAssertTrue(app.buttons["Use attendee search"].exists)
        capture(app, name: "Synthetic camera permission denied")
        app.buttons["Use attendee search"].tap(); app.buttons["Search attendees"].tap()
        XCTAssertTrue(app.staticTexts["statusMessage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
        XCTAssertFalse(app.buttons["reviewBatch"].exists)
    }
    @MainActor
    func testSearchCancelConfirmAndBack() {
        let app = XCUIApplication(); launchDemo(app)
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
        let app = XCUIApplication(); app.launchArguments = ["--offline"]; launchDemo(app)
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Search attendees"].tap()
        XCTAssertTrue(app.staticTexts["statusMessage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Checked in"].exists)
        capture(app, name: "Offline lookup")
    }
    @MainActor
    func testFailedCheckInRetainsBatch() {
        let app = XCUIApplication(); app.launchArguments = ["--fail-checkin"]; launchDemo(app)
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
        let app = XCUIApplication(); app.launchArguments = ["--finance"]; launchDemo(app)
        app.buttons["staffDemoShortcut"].tap(); app.buttons["day-1"].tap()
        XCTAssertTrue(app.staticTexts["Check-in access unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Scan tickets"].exists)
        capture(app, name: "Role unavailable")
    }

    @MainActor
    func testBackRequiresDiscardingUnsubmittedBatch() {
        let app = XCUIApplication(); launchDemo(app)
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
        let app = XCUIApplication(); launchDemo(app)
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
        let catalogReady = NSPredicate { _, _ in
            let status = app.staticTexts["Demo environment"]
            return app.buttons["day-1"].isHittable && app.buttons["Sign out"].isHittable &&
                !app.buttons["enterDemo"].exists && status.exists && status.frame.width > 0 &&
                status.frame.height > 0 && app.frame.contains(status.frame)
        }
        let catalogExpectation = XCTNSPredicateExpectation(predicate: catalogReady, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [catalogExpectation], timeout: 5), .completed)
        try audit("Event catalog")
        app.buttons["day-1"].tap(); app.buttons["Search attendees"].tap()
        try audit("Lookup")
        app.buttons["demo-001"].tap(); app.swipeUp(); app.buttons["reviewBatch"].tap()
        try audit("Review")
    }

    @MainActor
    func testDemoDisclosureSupportsMaximumTextAndDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--dark-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchDemo(app)
        let enter = app.buttons["enterDemo"]
        for _ in 0..<12 { if enter.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(enter.isHittable)
        enter.tap()
        let disclosure = app.staticTexts["Demo environment"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.isHittable)
        XCTAssertTrue(app.frame.contains(disclosure.frame))
        XCTAssertGreaterThan(disclosure.frame.height, 40, "The disclosure must follow the largest body text size.")
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription, .trait])
        capture(app, name: "Largest dark demo disclosure")
        revealStaffListElement("day-1", in: app)
        app.buttons["day-1"].tap()
        app.buttons["Events"].tap()
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign out"].isHittable)
        app.buttons["Sign out"].tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 5))
    }

    @MainActor
    func testScannerFallbackAndMixedResults() {
        let app = XCUIApplication(); launchDemo(app)
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        app.buttons["Scan tickets"].tap()
        XCTAssertTrue(app.buttons["Use attendee search"].waitForExistence(timeout: 5))
        capture(app, name: "Scanner fallback")
        app.buttons["Use attendee search"].tap()
        revealStaffListElement("Search attendees", in: app); app.buttons["Search attendees"].tap()
        revealStaffListElement("demo-001", in: app); app.buttons["demo-001"].tap()
        revealStaffListElement("demo-003", in: app)
        app.buttons["demo-003"].tap()
        revealStaffListElement("reviewBatch", in: app)
        app.buttons["reviewBatch"].tap()
        revealStaffListElement("review-demo-001", in: app, button: false)
        XCTAssertTrue(app.staticTexts["review-demo-001"].exists)
        revealStaffListElement("review-demo-003", in: app, button: false)
        XCTAssertTrue(app.staticTexts["review-demo-003"].exists)
        app.buttons["Cancel"].tap()
        revealStaffListElement("reviewBatch", in: app); app.buttons["reviewBatch"].tap()
        revealStaffListElement("Confirm check-in", in: app); app.buttons["Confirm check-in"].tap()
        revealStaffListElement("Checked in", in: app, button: false)
        XCTAssertTrue(app.staticTexts["Checked in"].exists)
        revealStaffListElement("Not eligible for this day", in: app, button: false)
        XCTAssertTrue(app.staticTexts["Not eligible for this day"].waitForExistence(timeout: 5))
        capture(app, name: "Mixed outcomes")
        app.buttons["Events"].tap()
        revealStaffListElement("day-2", in: app)
        XCTAssertTrue(app.buttons["day-2"].waitForExistence(timeout: 5))
        capture(app, name: "Staff catalog after confirmed results and Back")
    }
    @MainActor
    func testLargestDynamicTypeKeyboardAndCameraFallback() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchDemo(app)
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
        let app = XCUIApplication(); app.launchArguments = ["--duplicate-names"]; launchDemo(app)
        app.buttons["enterDemo"].tap(); app.buttons["day-1"].tap()
        revealStaffListElement("Search attendees", in: app); app.buttons["Search attendees"].tap()
        revealStaffListElement("demo-001", in: app)
        XCTAssertTrue(app.buttons["demo-001"].label.contains("alex@example.test"))
        revealStaffListElement("demo-004", in: app)
        XCTAssertTrue(app.buttons["demo-004"].label.contains("alex.second@example.test"))
        revealStaffListElement("demo-001", in: app, scrollUp: false)
        app.buttons["demo-001"].tap()
        revealStaffListElement("demo-004", in: app)
        app.buttons["demo-004"].tap()
        revealStaffListElement("reviewBatch", in: app)
        app.buttons["reviewBatch"].tap()
        revealStaffListElement("review-demo-001", in: app, button: false)
        XCTAssertTrue(app.staticTexts["review-demo-001"].label.contains("alex@example.test"))
        revealStaffListElement("review-demo-004", in: app, button: false)
        XCTAssertTrue(app.staticTexts["review-demo-004"].label.contains("alex.second@example.test"))
        capture(app, name: "Duplicate-name review")
    }

    @MainActor
    func testCompanionNavigationPreservesBatchAndIndependentPassStatuses() {
        let app = XCUIApplication(); launchDemo(app)
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
        launchDemo(app)
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
        let app = XCUIApplication(); launchDemo(app)
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
        launchDemo(app)
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
        launchDemo(app)
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
        launchDemo(app)
        app.buttons["exploreSampleEvent"].tap()
        app.swipeUp()
        app.buttons["eventSchedule"].tap()
        app.segmentedControls["scheduleFilter"].buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Your evening, your way"].exists)
    }

    @MainActor
    func testScheduleRowEntireTouchAreaAndBackStack() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        launchDemo(app)
        defer {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.press(.home); app.activate()
            let restored = expectation(for: NSPredicate { _, _ in app.frame.height > app.frame.width }, evaluatedWith: app)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        }
        app.buttons["exploreSampleEvent"].tap()
        let schedule = app.buttons["eventSchedule"]
        for _ in 0..<12 {
            if schedule.isHittable && app.frame.contains(schedule.frame) { break }
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        }
        XCTAssertTrue(schedule.isHittable)
        XCTAssertTrue(app.frame.contains(schedule.frame))
        XCTAssertGreaterThanOrEqual(schedule.frame.height, 48)
        let geometry = XCTAttachment(string: "Schedule row frame: \(schedule.frame)")
        geometry.name = "Schedule full touch area"; geometry.lifetime = .keepAlways; add(geometry)
        capture(app, name: "Schedule row full touch area portrait")
        for point in [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.5, dy: 0.9)] {
            schedule.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.segmentedControls["scheduleFilter"].exists)
            app.navigationBars.buttons["BackButton"].tap()
            XCTAssertTrue(app.navigationBars["Event preview"].waitForExistence(timeout: 5))
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.press(.home); app.activate()
        let landscapeReady = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeReady], timeout: 5), .completed)
        for _ in 0..<12 {
            if schedule.isHittable && app.frame.contains(schedule.frame) { break }
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        }
        XCTAssertTrue(schedule.isHittable)
        XCTAssertTrue(app.frame.contains(schedule.frame))
        XCTAssertGreaterThanOrEqual(schedule.frame.height, 48)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Schedule row full touch area landscape"; landscape.lifetime = .keepAlways; add(landscape)
        schedule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Event preview"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["enterDemo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWelcomeActionWrapAndScheduleWithSystemTextSettings() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        launchDemo(app)
        let portraitReady = expectation(for: NSPredicate { _, _ in app.frame.height > app.frame.width }, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portraitReady], timeout: 5), .completed)
        let action = app.staticTexts["Explore sample event"]
        for _ in 0..<16 { if action.isHittable && app.frame.contains(action.frame) { break }; app.swipeUp() }
        XCTAssertTrue(action.isHittable)
        XCTAssertTrue(app.frame.contains(action.frame))
        XCTAssertEqual(action.label, "Explore sample event")
        try app.performAccessibilityAudit(for: .textClipped)
        let geometry = XCTAttachment(string: "Welcome action frame: \(action.frame); complete label: \(action.label)")
        geometry.name = "System text settings welcome action"; geometry.lifetime = .keepAlways; add(geometry)
        capture(app, name: "System text settings whole welcome action")
        action.tap()
        XCTAssertTrue(app.navigationBars["Event preview"].waitForExistence(timeout: 5))
        let schedule = app.buttons["eventSchedule"]
        for _ in 0..<16 { if schedule.isHittable && app.frame.contains(schedule.frame) { break }; app.swipeUp() }
        XCTAssertTrue(schedule.isHittable)
        XCTAssertTrue(app.frame.contains(schedule.frame))
        XCTAssertGreaterThanOrEqual(schedule.frame.height, 48)
        capture(app, name: "System text settings schedule action")
        schedule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 5))
        let filter = app.segmentedControls["scheduleFilter"]
        for _ in 0..<16 { if filter.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(filter.isHittable)
        filter.buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Your evening, your way"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Event preview"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["enterDemo"].waitForExistence(timeout: 5))
    }

}
