import XCTest

final class ShortcutDiscoveryTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testDiscoversActionsAndCreatesChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoSystemIntegration"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.stop"].waitForExistence(timeout: 15))
        app.buttons["chat.stop"].tap()
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        if shortcuts.buttons["New Shortcut"].exists { shortcuts.buttons["New Shortcut"].tap() }
        shortcuts.buttons["Describe a Shortcut"].tap()
        shortcuts.searchFields["Search Actions"].tap()
        shortcuts.searchFields["Search Actions"].typeText("FancyClaw")
        XCTAssertTrue(shortcuts.staticTexts["New FancyClaw Chat"].waitForExistence(timeout: 30), shortcuts.debugDescription)
        XCTAssertTrue(shortcuts.staticTexts["Ask FancyClaw"].exists)
        XCTAssertTrue(shortcuts.staticTexts["Open FancyClaw Chat"].exists)
        let screenshot = XCTAttachment(screenshot: shortcuts.screenshot())
        screenshot.name = "Shortcuts discovery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        shortcuts.staticTexts["New FancyClaw Chat"].tap()
        shortcuts.buttons["play"].tap()
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue), object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 15), .completed, shortcuts.debugDescription)
        XCTAssertTrue(app.staticTexts["Start a conversation"].waitForExistence(timeout: 15), app.debugDescription)
        let created = XCTAttachment(screenshot: app.screenshot())
        created.name = "Chat created from Shortcuts"
        created.lifetime = .keepAlways
        add(created)
    }
}
