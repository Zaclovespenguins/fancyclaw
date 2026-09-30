import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-OnboardingPreview"]
        app.launch()

        XCTAssertTrue(app.navigationBars["FancyClaw"].waitForExistence(timeout: 10))
        app.buttons["Set up connection"].tap()
        let connectButton = app.buttons["onboarding.connect"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
        XCTAssertTrue(connectButton.isHittable)
    }
}
