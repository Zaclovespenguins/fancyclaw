import XCTest

final class ApprovalTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testApproveAndOtherSessionBadge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoApprovals"]
        app.launch()
        let approve = app.buttons["approval.allow-once.demo-approval"]
        XCTAssertTrue(approve.waitForExistence(timeout: 15))
        // Decisions enable once the connection's approval scope is known.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: approve)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["swift --version"].exists)
        XCTAssertTrue(app.buttons["approval.deny.demo-approval"].exists)
        XCTAssertFalse(app.buttons["approval.allow-always.demo-approval"].exists)
        let card = XCTAttachment(screenshot: app.screenshot())
        card.name = "Exec approval — command and decisions"
        card.lifetime = .keepAlways
        add(card)

        approve.tap()
        // The resolved card collapses to a one-line receipt.
        let receipt = app.staticTexts["approval.status.demo-approval"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.label.hasPrefix("Approved"), receipt.label)
        XCTAssertFalse(approve.exists)
        app.openChatsTab()
        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@",
            "sessions.row.", "sessions.row.agent:main:main")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        let badge = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.approvals.")).firstMatch
        XCTAssertTrue(badge.exists)
        let drawer = XCTAttachment(screenshot: app.screenshot())
        drawer.name = "Exec approval — other chat badge in Chats tab"
        drawer.lifetime = .keepAlways
        add(drawer)
        other.tap()
        let deny = app.buttons["approval.deny.demo-other-approval"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pwd"].exists)
        XCTAssertFalse(app.staticTexts["swift --version"].exists)
        deny.tap()
        let denied = app.staticTexts["approval.status.demo-other-approval"]
        XCTAssertTrue(denied.waitForExistence(timeout: 5))
        XCTAssertTrue(denied.label.hasPrefix("Denied"), denied.label)
        app.goBackToTab()
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.approvals.")).firstMatch.exists)
    }

    /// Approval Review opens a chat whose history loads after it appears; the card must still end up in view.
    @MainActor
    func testFocusedApprovalStaysInViewWhileHistoryLoads() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoApprovalFocus"]
        app.launch()
        let approve = app.buttons["approval.allow-once.demo-focus-approval"]
        XCTAssertTrue(approve.waitForExistence(timeout: 15))
        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.exists)
        // Wait for history rows to arrive and the scroll position to settle.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Answer")).firstMatch
            .waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(approve.isHittable, "The approval's Approve button is not in view")
        XCTAssertLessThan(approve.frame.maxY, composer.frame.minY)
        XCTAssertTrue(app.buttons["approval.allow-always.demo-focus-approval"].exists)
        let focused = XCTAttachment(screenshot: app.screenshot())
        focused.name = "Approval focus — card in view"
        focused.lifetime = .keepAlways
        add(focused)
        approve.tap()
        XCTAssertTrue(app.staticTexts["approval.status.demo-focus-approval"].waitForExistence(timeout: 5))
    }
}
