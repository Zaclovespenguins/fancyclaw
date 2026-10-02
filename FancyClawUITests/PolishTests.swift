import XCTest

final class PolishTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOnboardingAccessibilityAndErrorRecovery() throws {
        let app = launch("-OnboardingPreview")
        XCTAssertTrue(app.buttons["Set up connection"].waitForExistence(timeout: 10))
        try audit(app)
        capture(app, "Onboarding — light")
        app.buttons["Set up connection"].tap()
        let connect = app.buttons["onboarding.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()
        XCTAssertTrue(app.buttons["Dismiss error"].waitForExistence(timeout: 5))
        try audit(app)
        capture(app, "Connection error — light")
        app.buttons["Dismiss error"].tap()
        XCTAssertFalse(app.buttons["Dismiss error"].exists)
    }

    @MainActor
    func testChatAndDrawerAccessibility() throws {
        let app = launch("-DemoAttachments")
        XCTAssertTrue(app.buttons["Remove Coast.jpg"].waitForExistence(timeout: 10))
        try audit(app)
        capture(app, "Attachment composer — light")
        app.buttons["Remove Coast.jpg"].tap()
        app.buttons["Remove Notes.txt"].tap()
        XCTAssertTrue(app.staticTexts["Start a conversation"].exists)
        try audit(app)
        app.openChatsTab()
        XCTAssertTrue(app.sessionRow(titled: "Main chat").waitForExistence(timeout: 5))
        waitForStableFrame(app.sessionRow(titled: "Main chat"))
        waitForStableFrame(app.searchFields["Search chats"])
        try audit(app)
        capture(app, "Chats tab — light")
    }

    @MainActor
    func testLargeTextDarkMode() throws {
        let app = launch("-DemoApprovals", largeDark: true)
        XCTAssertTrue(app.buttons["approval.allow-once.demo-approval"].waitForExistence(timeout: 10))
        try audit(app)
        capture(app, "Approval — dark XXL")
        app.buttons["approval.allow-once.demo-approval"].tap()
        XCTAssertTrue(app.staticTexts["Approved once"].waitForExistence(timeout: 5))
        app.openChatsTab()
        XCTAssertTrue(app.sessionRow(titled: "Main chat").waitForExistence(timeout: 5))
        waitForStableFrame(app.sessionRow(titled: "Main chat"))
        waitForStableFrame(app.searchFields["Search chats"])
        try audit(app)
        capture(app, "Chats tab — dark XXL")
        app.terminate()
        app.launchArguments = ["-OnboardingPreview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL", "-PolishDark"]
        app.launch()
        XCTAssertTrue(app.buttons["Set up connection"].waitForExistence(timeout: 10))
        try audit(app)
        capture(app, "Onboarding — dark XXL")
        app.buttons["Set up connection"].tap()
        let connect = app.buttons["onboarding.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()
        XCTAssertTrue(app.buttons["Dismiss error"].waitForExistence(timeout: 5))
        try audit(app)
        capture(app, "Connection error — dark XXL")
    }

    @MainActor
    func testRichOutputAccessibilityAndLargeText() throws {
        let app = launch("-DemoConversation", largeDark: true)
        XCTAssertTrue(app.buttons["chat.tool.demo-exec"].waitForExistence(timeout: 10))
        try audit(app)
        capture(app, "Rich output — dark XXL")
        app.scrollViews["chat.transcript"].swipeDown()
        app.scrollViews["chat.transcript"].swipeDown()
        capture(app, "Markdown — dark XXL")
    }

    @MainActor
    func testHomeAndSettingsAccessibility() throws {
        for largeDark in [false, true] {
            let app = launch("-DemoConversation", largeDark: largeDark)
            let suffix = largeDark ? "dark XXL" : "light"
            XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 10))
            app.goBackToTab()
            XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
            waitForStableFrame(app.buttons["home.settings"])
            try audit(app)
            capture(app, "Home placeholder — \(suffix)")
            app.buttons["home.settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            try audit(app)
            capture(app, "Settings — \(suffix)")
            app.swipeUp()
            capture(app, "Settings about — \(suffix)")
            app.goBackToTab()
            for tab in ["Skills", "Activity"] {
                app.selectTab(tab)
                XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
                try audit(app)
                capture(app, "\(tab) placeholder — \(suffix)")
            }
            app.terminate()
        }
    }

    @MainActor
    func testLaunchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-OnboardingPreview"]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
        }
    }

    @MainActor
    private func launch(_ mode: String, largeDark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [mode, largeDark ? "-PolishDark" : "-PolishLight"]
        if largeDark {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        }
        app.launch()
        return app
    }

    @MainActor
    private func waitForStableFrame(_ element: XCUIElement) {
        // Elements exist before a navigation transition finishes; audit only once the frame settles.
        var lastFrame = CGRect.zero
        var unchangedSince = Date.now
        let stable = NSPredicate { _, _ in
            let frame = element.frame
            if frame != lastFrame { lastFrame = frame; unchangedSince = .now }
            return element.isHittable && Date.now.timeIntervalSince(unchangedSince) > 1
        }
        expectation(for: stable, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        try app.performAccessibilityAudit { issue in
            print("Accessibility issue: \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.debugDescription ?? "no element")")
            return false
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
