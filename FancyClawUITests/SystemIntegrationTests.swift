import XCTest

final class SystemIntegrationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testRunActivityDemoAndStop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoSystemIntegration"]
        app.launch()
        let reply = app.staticTexts["This demo run keeps a Live Activity visible. Stop the reply to end it."]
        XCTAssertTrue(reply.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["chat.stop"].exists)
        let foreground = XCTAttachment(screenshot: app.screenshot())
        foreground.name = "System integration demo chat"
        foreground.lifetime = .keepAlways
        add(foreground)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).press(forDuration: 1)
        XCTAssertTrue(springboard.staticTexts["Open FancyClaw to refresh"].waitForExistence(timeout: 10))
        let activity = XCTAttachment(screenshot: springboard.screenshot())
        activity.name = "Live Activity on the Home Screen"
        activity.lifetime = .keepAlways
        add(activity)
        app.activate()
        XCTAssertTrue(app.buttons["chat.stop"].waitForExistence(timeout: 10))
        app.buttons["chat.stop"].tap()
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 10))
    }
}
