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
