import XCTest

final class ChatTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendShowsFakeGatewayReply() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FakeGateway"]
        app.launch()

        let connectButton = app.buttons["onboarding.connect"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 10))
        connectButton.tap()

        // Connecting lands on Home; the compose button starts and pushes a new chat.
        XCTAssertTrue(app.composeButton.waitForExistence(timeout: 10))
        app.composeButton.tap()

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Hello from UI test")
        app.buttons["chat.send"].tap()

        let reply = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Hello from FakeGateway.")
        ).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 15))
    }

    @MainActor
    func testAttachmentTrayRemoveAndSendWithoutText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoAttachments"]
        app.launch()
        let remove = app.buttons["Remove Coast.jpg"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Notes.txt"].exists)
        XCTAssertTrue(app.buttons["chat.send"].isEnabled)
        let draft = XCTAttachment(screenshot: app.screenshot())
        draft.name = "Attachments — image and file draft"
        draft.lifetime = .keepAlways
        add(draft)
        remove.tap()
        XCTAssertFalse(remove.exists)
        app.buttons["chat.send"].tap()
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hello from FakeGateway.")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Notes.txt"].exists)
        XCTAssertFalse(app.buttons["attachment.remove"].exists)
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        app.buttons["chat.attach"].tap()
        XCTAssertTrue(app.buttons["Photo Library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take Photo"].exists)
        XCTAssertTrue(app.buttons["Choose File"].exists)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.alerts["Attachment unavailable"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
    }

    @MainActor
    func testRichOutputControlsAndPartialMarkdown() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoConversation"]
        app.launch()
        let tool = app.buttons["chat.tool.demo-exec"]
        XCTAssertTrue(tool.waitForExistence(timeout: 10))
        tool.tap()
        XCTAssertEqual(tool.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Swift 6.4"].exists)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Rich output — expanded tool"
        expanded.lifetime = .keepAlways
        add(expanded)
        tool.tap()
        XCTAssertEqual(tool.value as? String, "Collapsed")

        let copy = app.buttons.matching(identifier: "markdown.copyCode").allElementsBoundByIndex.last!
        copy.tap()
        XCTAssertTrue(app.buttons["Code copied"].waitForExistence(timeout: 3))
        let partial = XCTAttachment(screenshot: app.screenshot())
        partial.name = "Rich output — math and partial fence"
        partial.lifetime = .keepAlways
        add(partial)

        let transcript = app.scrollViews["chat.transcript"]
        transcript.swipeDown()
        transcript.swipeDown()
        let report = XCTAttachment(screenshot: app.screenshot())
        report.name = "Rich output — table and nested list"
        report.lifetime = .keepAlways
        add(report)
    }

}
