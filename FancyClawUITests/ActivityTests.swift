import XCTest

final class ActivityTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testTodayAndScheduledPlaceholders() throws {
        let app = launchActivity()
        XCTAssertTrue(app.staticTexts["Activity is coming soon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A timeline of approvals, runs and replies will appear here."].exists)

        activitySegment("Scheduled", in: app).tap()
        XCTAssertTrue(app.staticTexts["Scheduled jobs from your Gateway will appear here."].waitForExistence(timeout: 5))

        activitySegment("Today", in: app).tap()
        XCTAssertTrue(app.staticTexts["A timeline of approvals, runs and replies will appear here."].waitForExistence(timeout: 5))
    }

    @MainActor func testActivityScreenshotsBothSegmentsLightDarkDefaultAndXXL() throws {
        for dark in [false, true] {
            for large in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-DemoHome", dark ? "-PolishDark" : "-PolishLight"]
                if large {
                    app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
                }
                app.launch()
                XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 15))
                app.selectTab("Activity")
                XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["A timeline of approvals, runs and replies will appear here."].waitForExistence(timeout: 5))
                retain(app, "Activity Today — \(dark ? "dark" : "light") \(large ? "XXL" : "default")")

                activitySegment("Scheduled", in: app).tap()
                XCTAssertTrue(app.staticTexts["Scheduled jobs from your Gateway will appear here."].waitForExistence(timeout: 5))
                retain(app, "Activity Scheduled — \(dark ? "dark" : "light") \(large ? "XXL" : "default")")
                app.terminate()
            }
        }
    }

    @MainActor private func launchActivity() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoHome", "-PolishLight"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 15))
        app.selectTab("Activity")
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func activitySegment(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.segmentedControls.buttons[title]
        if control.exists { return control }
        return app.buttons[title]
    }

    @MainActor private func retain(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
