import XCTest

final class HomeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testPromptStartsNewChatWithMessageAndGatewayReply() throws {
        let app = launch()
        let prompt = app.textFields["home.prompt"]
        prompt.tap()
        prompt.typeText("Plan a weekend trip")
        let send = app.buttons["home.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Plan a weekend trip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hello from FakeGateway."].waitForExistence(timeout: 10))
        app.goBackToTab()
        XCTAssertEqual(app.textFields["home.prompt"].value as? String, "What should I take care of?")
    }

    @MainActor func testFailedSendKeepsDraftOnHomeAndRetryUsesOriginalChat() throws {
        let app = launch("-DemoHomeSendError")
        let prompt = app.textFields["home.prompt"]
        prompt.tap()
        prompt.typeText("Keep this task")
        app.buttons["home.send"].tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The demo Gateway rejected this task.")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["chat.back"].exists)
        XCTAssertEqual(prompt.value as? String, "Keep this task")
        XCTAssertFalse(prompt.isEnabled)
        XCTAssertTrue(app.buttons["home.editNewTask"].exists)
        app.buttons["home.send"].tap()
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        app.selectTab("Chats")
        let newRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sessions.row.", "New chat"))
        XCTAssertEqual(newRows.count, 1, "Home Retry created another chat")
        newRows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Keep this task"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Keep this task").count, 1)
    }

    @MainActor func testApprovalReviewOpensFocusedChatAndMissingSessionUsesSheet() throws {
        let app = launch()
        let review = app.buttons["home.review.home-approval"]
        reveal(review, in: app)
        review.tap()
        let approve = app.buttons["approval.allow-once.home-approval"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        let hittable = NSPredicate(format: "isHittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: approve)], timeout: 10), .completed)
        app.goBackToTab()
        let global = app.buttons["home.review.home-global-approval"]
        reveal(global, in: app)
        global.tap()
        XCTAssertTrue(app.navigationBars["Review command"].waitForExistence(timeout: 5))
        let deny = app.buttons["approval.deny.home-global-approval"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        deny.tap()
        XCTAssertTrue(app.staticTexts["approval.status.home-global-approval"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["home.review.home-global-approval"].exists)
    }

    @MainActor func testRecentRunningAndSeeAllRoutes() throws {
        let app = launch()
        let recent = app.buttons["home.recent.agent:main:main"]
        reveal(recent, in: app)
        recent.tap()
        XCTAssertTrue(app.staticTexts["Your weekend plans are ready."].waitForExistence(timeout: 10))
        app.goBackToTab()
        let running = app.buttons["home.run.agent:main:home-running"]
        reveal(running, in: app)
        running.tap()
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 5))
        app.goBackToTab()
        let all = app.buttons["home.seeAll"]
        reveal(all, in: app)
        all.tap()
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("No matching sessions")
        // Submit the native search without cancelling it or clearing its bound query. The keyboard otherwise
        // covers the collapsed tab control; the selected Chats control expands the other tab choices.
        search.typeText("\n")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch
        )], timeout: 5), .completed, "Search submission did not dismiss the keyboard")
        XCTAssertEqual(search.value as? String, "No matching sessions", "The search query was cleared")
        app.selectTab("Home")
        XCTAssertTrue(app.buttons["home.recent.agent:main:main"].exists, "Chats search filtered Home Recent")
    }

    @MainActor func testHomeOfflineDraftRemainsEditableAndSendDisabled() throws {
        let app = launch("-DemoOffline")
        let status = app.buttons["home.status"]
        let offline = NSPredicate(format: "label CONTAINS %@", "Offline")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: offline, object: status)], timeout: 15), .completed)
        let prompt = app.textFields["home.prompt"]
        XCTAssertTrue(prompt.isEnabled)
        prompt.tap()
        prompt.typeText("Write this later")
        XCTAssertEqual(prompt.value as? String, "Write this later")
        XCTAssertFalse(app.buttons["home.send"].isEnabled)
        XCTAssertFalse(app.buttons["home.attach"].isEnabled)
        XCTAssertFalse(app.buttons["home.model"].isEnabled)
    }

    @MainActor func testHomeScreenshotsLightDarkDefaultAndXXL() throws {
        for dark in [false, true] {
            for large in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-DemoHome", dark ? "-PolishDark" : "-PolishLight"]
                if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
                app.launch()
                XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 15))
                retain(app, "Home — \(dark ? "dark" : "light") \(large ? "XXL" : "default") header")
                reveal(app.buttons["home.recent.agent:main:main"], in: app)
                retain(app, "Home — \(dark ? "dark" : "light") \(large ? "XXL" : "default") sections")
                app.terminate()
            }
        }
    }

    @MainActor private func launch(_ mode: String = "-DemoHome") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [mode]
        app.launch()
        let ready = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["home.settings", "chat.back"])).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        if app.buttons["chat.back"].exists { app.goBackToTab() }
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.scrollViews["home.scroll"].swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }

    @MainActor private func retain(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
