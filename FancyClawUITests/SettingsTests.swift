import XCTest

final class SettingsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testReconnectAndDisconnect() throws {
        let app = XCUIApplication()
        // -DemoOffline connects, then the FakeGateway drops the socket and refuses the automatic recovery.
        app.launchArguments = ["-DemoOffline"]
        app.launch()
        let avatar = app.buttons["home.settings"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 15))
        avatar.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let status = app.descendants(matching: .any)["settings.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(status, value: "Offline", timeout: 15), status.debugDescription)
        let host = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "127.0.0.1", "127.0.0.1")).firstMatch
        XCTAssertTrue(host.exists, "Gateway host is not shown")
        let offline = XCTAttachment(screenshot: app.screenshot())
        offline.name = "Settings — offline with Reconnect"
        offline.lifetime = .keepAlways
        add(offline)

        let reconnect = app.buttons["settings.reconnect"]
        XCTAssertTrue(reconnect.exists)
        reconnect.tap()
        XCTAssertTrue(waitFor(status, value: "Connected", timeout: 15), status.debugDescription)
        XCTAssertFalse(reconnect.exists)

        app.buttons["settings.disconnect"].tap()
        let confirm = app.buttons["settings.confirmDisconnect"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        // Disconnecting leaves the tab shell for onboarding.
        let connect = app.buttons["onboarding.connect"]
        let setup = app.buttons["Set up connection"]
        let onboardingReady = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "onboarding.connect", "Set up connection"
        )).firstMatch
        XCTAssertTrue(onboardingReady.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBar.exists)
        // A forgotten connection can return to the welcome screen; follow its real setup action.
        if setup.exists { setup.tap() }
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
    }

    @MainActor private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
