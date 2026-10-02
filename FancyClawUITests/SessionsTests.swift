import XCTest

final class SessionsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCreateRenameAndDeleteInChatsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoConversation"]
        app.launch()
        // The demo opens the seeded chat pushed on Home.
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 15))
        app.openChatsTab()
        let initialList = XCTAttachment(screenshot: app.screenshot())
        initialList.name = "Chats tab"
        initialList.lifetime = .keepAlways
        add(initialList)
        app.buttons["sessions.new"].tap()
        // A new chat is pushed on the Chats tab; go back to manage it.
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 10))
        app.goBackToTab()
        let row = app.sessionRow(titled: "New chat")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("Slice six chat")
        app.alerts.buttons["Save"].tap()
        let renamed = app.sessionRow(titled: "Slice six chat")
        XCTAssertTrue(renamed.waitForExistence(timeout: 10))
        let renamedList = XCTAttachment(screenshot: app.screenshot())
        renamedList.name = "Renamed chat"
        renamedList.lifetime = .keepAlways
        add(renamedList)
        renamed.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.buttons["Delete chat"].tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: renamed)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.sessionRow(titled: "Main chat").waitForExistence(timeout: 5))
        // Opening a row pushes that chat on the Chats tab.
        app.sessionRow(titled: "Main chat").tap()
        XCTAssertTrue(app.buttons["chat.tool.demo-exec"].waitForExistence(timeout: 10))
    }
}
