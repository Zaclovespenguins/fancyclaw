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
}
