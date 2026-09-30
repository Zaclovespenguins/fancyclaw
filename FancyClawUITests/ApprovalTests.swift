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
        XCTAssertTrue(approve.isEnabled)
        XCTAssertTrue(app.staticTexts["swift --version"].exists)
        XCTAssertTrue(app.buttons["approval.deny.demo-approval"].exists)
        XCTAssertFalse(app.buttons["approval.allow-always.demo-approval"].exists)
        let card = XCTAttachment(screenshot: app.screenshot())
        card.name = "Exec approval — command and decisions"
        card.lifetime = .keepAlways
        add(card)

        approve.tap()
        XCTAssertTrue(app.staticTexts["Approved once"].waitForExistence(timeout: 5))
        XCTAssertFalse(approve.exists)
        XCTAssertEqual(app.buttons["chat.sessions"].value as? String, "1 pending command approvals")
        app.buttons["chat.sessions"].tap()
        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@",
            "sessions.row.", "sessions.row.agent:main:main")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        let badge = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.approvals.")).firstMatch
        XCTAssertTrue(badge.exists)
        let drawer = XCTAttachment(screenshot: app.screenshot())
        drawer.name = "Exec approval — other chat badge"
        drawer.lifetime = .keepAlways
        add(drawer)
        other.tap()
        let deny = app.buttons["approval.deny.demo-other-approval"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pwd"].exists)
        XCTAssertFalse(app.staticTexts["swift --version"].exists)
        deny.tap()
        XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chat.sessions"].value as? String, "0 pending command approvals")
    }
}
