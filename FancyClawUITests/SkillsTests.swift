import XCTest

final class SkillsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testGridSearchAndReadOnlyDetail() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["skills.tile.GitHub"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["skills.tile.Gmail"].exists)
        let search = app.searchFields["Search skills"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("pull requests")
        XCTAssertTrue(app.buttons["skills.tile.GitHub"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skills.tile.Gmail"].exists)
        app.buttons["skills.tile.GitHub"].tap()
        XCTAssertTrue(app.navigationBars["GitHub"].waitForExistence(timeout: 5))
        let detail = detailList(in: app)
        XCTAssertTrue(detail.staticTexts["Read repositories, issues and pull requests."].exists)
        XCTAssertEqual(detail.staticTexts["skills.detail.status"].label, "Availability, Ready")
        XCTAssertEqual(detail.switches.count, 0)
        XCTAssertFalse(detail.buttons["Install"].exists)
        app.buttons["skills.detail.done"].tap()
        XCTAssertTrue(app.navigationBars["Skills"].waitForExistence(timeout: 5))
    }

    @MainActor func testMissingAlternativesAndAgentVisibilityRemainSeparate() throws {
        let app = launch()
        app.buttons["skills.tile.Browser"].tap()
        XCTAssertTrue(app.navigationBars["Browser"].waitForExistence(timeout: 5))
        let browserDetail = detailList(in: app)
        XCTAssertEqual(browserDetail.staticTexts["skills.detail.status"].label, "Availability, Missing requirements")
        reveal(browserDetail.staticTexts.matching(identifier: "At least one binary").firstMatch, in: app)
        XCTAssertTrue(browserDetail.staticTexts.matching(identifier: "chromium, google-chrome").firstMatch.exists)
        app.buttons["skills.detail.done"].tap()
        reveal(app.buttons["skills.tile.Obsidian"], in: app)
        app.buttons["skills.tile.Obsidian"].tap()
        XCTAssertTrue(app.navigationBars["Obsidian"].waitForExistence(timeout: 5))
        let notesDetail = detailList(in: app)
        XCTAssertEqual(notesDetail.staticTexts["skills.detail.status"].label, "Availability, Ready")
        XCTAssertTrue(notesDetail.staticTexts["Visible in model prompt, No"].exists)
        XCTAssertTrue(notesDetail.staticTexts["Supports user invocation, Yes"].exists)
        XCTAssertFalse(notesDetail.staticTexts["Off"].exists)
    }

    @MainActor func testEmptySearchEmptyAndErrorRetryStates() throws {
        let app = launch("-DemoSkillsEmpty")
        XCTAssertTrue(app.staticTexts["No skills installed"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["-DemoSkillsError", "-PolishLight"]
        app.launch()
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The demo Gateway refused to read skills.")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let retry = app.buttons["skills.retry"]
        XCTAssertTrue(retry.isEnabled)
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-DemoSkills", "-PolishLight"]
        app.launch()
        XCTAssertTrue(app.buttons["skills.tile.GitHub"].waitForExistence(timeout: 10))
        let search = app.searchFields["Search skills"]
        search.tap(); search.typeText("unmatched skill")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "skills.searchEmpty").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skills.tile.GitHub"].exists)
    }

    @MainActor func testOfflineRetainsLastLoadedSkillsAndDetails() throws {
        let app = launch("-DemoSkillsOffline")
        let reconnect = app.buttons["skills.reconnect"]
        XCTAssertTrue(reconnect.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Offline · Showing the last loaded skills"].exists)
        reveal(app.buttons["skills.tile.GitHub"], in: app)
        app.buttons["skills.tile.GitHub"].tap()
        XCTAssertTrue(app.navigationBars["GitHub"].waitForExistence(timeout: 5))
        let detail = detailList(in: app)
        XCTAssertTrue(detail.staticTexts["Last loaded status · May have changed on the Gateway"].exists)
        XCTAssertEqual(detail.staticTexts["skills.detail.status"].label, "Availability, Ready")
    }

    @MainActor func testScreenshotsLightDarkDefaultAndXXL() throws {
        for dark in [false, true] {
            for large in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-DemoSkills", dark ? "-PolishDark" : "-PolishLight"]
                if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
                app.launch()
                XCTAssertTrue(app.buttons["skills.tile.Browser"].waitForExistence(timeout: 15))
                retain(app, "Skills — \(dark ? "dark" : "light") \(large ? "XXL" : "default") grid")
                app.buttons["skills.tile.Browser"].tap()
                XCTAssertTrue(app.navigationBars["Browser"].waitForExistence(timeout: 5))
                retain(app, "Skills — \(dark ? "dark" : "light") \(large ? "XXL" : "default") detail")
                app.terminate()
            }
        }
    }

    @MainActor private func launch(_ mode: String = "-DemoSkills") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [mode, "-PolishLight"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Skills"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            let scroll = app.scrollViews["skills.grid"]
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    /// Scope status queries to the native sheet List; the underlying grid remains in the UI hierarchy.
    @MainActor private func detailList(in app: XCUIApplication) -> XCUIElement {
        let collection = app.collectionViews["skills.detail"]
        if collection.waitForExistence(timeout: 5) { return collection }
        let table = app.tables["skills.detail"]
        XCTAssertTrue(table.waitForExistence(timeout: 5), "No native skill detail list")
        return table
    }

    @MainActor private func retain(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways
        add(image)
    }
}
