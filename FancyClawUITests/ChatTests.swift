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
        // One chip summarizes the message's tools; expanding it lists each tool.
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.toolchip.")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue(chip.label.hasPrefix("Using 3 tools"), chip.label)
        let tool = app.buttons["chat.tool.demo-exec"]
        XCTAssertFalse(tool.exists)
        chip.tap()
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        tool.tap()
        XCTAssertEqual(tool.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Swift 6.4"].exists)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Rich output — expanded tool"
        expanded.lifetime = .keepAlways
        add(expanded)
        tool.tap()
        XCTAssertEqual(tool.value as? String, "Collapsed")
        chip.tap()
        XCTAssertFalse(tool.exists)

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

    @MainActor
    func testTopBarMenusAndFileCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoConversation"]
        app.launch()
        let more = app.buttons["chat.menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete"].exists)
        // Reset asks for confirmation; cancel it.
        app.buttons["Reset"].tap()
        XCTAssertTrue(app.buttons["Reset chat"].waitForExistence(timeout: 3))
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap() }
        XCTAssertTrue(app.buttons["chat.agentModel"].waitForExistence(timeout: 3))

        // Tapping the title offers the agent and model choices.
        let title = app.buttons["chat.agentModel"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let model = app.buttons["Fake model"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Helper"].exists)
        model.tap()
        let modelSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "test/fake-model"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [modelSelected], timeout: 5), .completed)

        // The assistant's file shows name, size and type, with a download button.
        let card = app.descendants(matching: .any)["chat.file.gateway-summary.md"]
        for _ in 0..<4 where !card.exists { app.scrollViews["chat.transcript"].swipeDown() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.file.download"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Chat — file card"
        shot.lifetime = .keepAlways
        add(shot)

        // Agent choice creates a separate chat and reflects the selected Gateway agent in the title.
        title.tap()
        let helper = app.buttons["Helper"]
        XCTAssertTrue(helper.waitForExistence(timeout: 5))
        helper.tap()
        let newTitle = app.buttons["chat.agentModel"].firstMatch
        let helperSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Helper"), object: newTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [helperSelected], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["Start a conversation"].exists)
    }

    @MainActor
    func testSessionActionFailureShowsDismissibleError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoSessionActionError"]
        app.launch()
        let title = app.buttons["chat.agentModel"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        let model = app.buttons["Fake model"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        let message = app.staticTexts["The demo Gateway rejected the chat change."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertFalse((title.value as? String)?.contains("test/fake-model") == true)
        app.buttons["Dismiss error"].tap()
        XCTAssertFalse(message.exists)
        // A later failure is reported again after dismissal, without silently changing the selected model.
        title.tap()
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
    }
}
