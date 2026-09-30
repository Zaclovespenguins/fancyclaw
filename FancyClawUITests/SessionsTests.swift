import XCTest

final class SessionsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCreateRenameAndDeleteInDrawer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoConversation"]
        app.launch()
        let drawer = app.buttons["chat.sessions"]
        XCTAssertTrue(drawer.waitForExistence(timeout: 15))
        drawer.tap()
        let initialDrawer = XCTAttachment(screenshot: app.screenshot())
        initialDrawer.name = "Sessions drawer"
        initialDrawer.lifetime = .keepAlways
        add(initialDrawer)
        app.buttons["sessions.new"].tap()
        // Selecting the new chat dismisses the drawer; reopen to manage it.
        XCTAssertTrue(drawer.waitForExistence(timeout: 10))
        drawer.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sessions.row.", "New chat")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("Slice six chat")
        app.alerts.buttons["Save"].tap()
        let renamed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sessions.row.", "Slice six chat")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 10))
        let renamedDrawer = XCTAttachment(screenshot: app.screenshot())
        renamedDrawer.name = "Renamed chat"
        renamedDrawer.lifetime = .keepAlways
        add(renamedDrawer)
        renamed.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.buttons["Delete chat"].tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: renamed)
        waitForExpectations(timeout: 10)
        // Deleting the selected conversation switches back to Main and dismisses its sheet.
        XCTAssertTrue(drawer.waitForExistence(timeout: 5))
        drawer.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sessions.row.", "Main chat")).firstMatch.waitForExistence(timeout: 5))
    }
}
