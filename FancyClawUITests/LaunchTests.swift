import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPlaceholder() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["FancyClaw"].waitForExistence(timeout: 10))
    }
}
