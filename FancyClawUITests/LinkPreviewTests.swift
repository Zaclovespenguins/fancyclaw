import XCTest

final class LinkPreviewTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testFinishedPreviewContextMenuAndSettingsGate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoLinkPreviews"]
        app.launch()
        try setPreviews(true, in: app)
        try reopenDemoChat(in: app)
        let card = preview(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let loaded = NSPredicate(format: "label CONTAINS %@", "Build thoughtful apps with SwiftUI")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: card)], timeout: 5), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["chat.linkPreview.streaming.example.com"].exists)
        let fallback = app.descendants(matching: .any).matching(identifier: "chat.linkPreview.offline.example.com").firstMatch
        XCTAssertTrue(fallback.exists)
        XCTAssertEqual(fallback.label, "offline.example.com")
        if !card.isHittable { app.scrollViews["chat.transcript"].swipeDown() }
        card.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy Link"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Share"].exists)
        app.buttons["Copy Link"].tap()

        try setPreviews(false, in: app)
        try reopenDemoChat(in: app)
        XCTAssertFalse(preview(in: app).exists)
        // Inline Markdown remains present when its separate preview is disabled.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "can help shape the interface")).firstMatch.exists)
        try setPreviews(true, in: app)
        try reopenDemoChat(in: app)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 5))
    }

    @MainActor func testLinkPreviewScreenshotsLightDarkDefaultAndXXL() throws {
        for dark in [false, true] {
            for large in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-DemoLinkPreviews", dark ? "-PolishDark" : "-PolishLight"]
                if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
                app.launch()
                try setPreviews(true, in: app, captureName:
                    "Settings previews — \(dark ? "dark" : "light") \(large ? "XXL" : "default")")
                try reopenDemoChat(in: app)
                let card = preview(in: app)
                XCTAssertTrue(card.waitForExistence(timeout: 10))
                let loaded = NSPredicate(format: "label CONTAINS %@", "Build thoughtful apps with SwiftUI")
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: card)], timeout: 5), .completed)
                XCTAssertTrue(card.isHittable)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Link preview — \(dark ? "dark" : "light") \(large ? "XXL" : "default")"
                shot.lifetime = .keepAlways
                add(shot)
                app.terminate()
            }
        }
    }

    @MainActor private func preview(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "chat.linkPreview.developer.apple.com").firstMatch
    }

    @MainActor private func setPreviews(_ enabled: Bool, in app: XCUIApplication, captureName: String? = nil) throws {
        // A hidden TabView can still expose a tabBar container while its root buttons are unavailable.
        if app.buttons["chat.back"].exists || !app.tabBars.buttons["Home"].exists {
            XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 15))
            app.goBackToTab()
        }
        app.selectTab("Home")
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let toggle = app.switches["settings.linkPreviews"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let expected = enabled ? "1" : "0"
        if toggle.value as? String != expected {
            // SwiftUI can expose a row-sized switch containing the native trailing switch.
            let nativeSwitch = toggle.descendants(matching: .switch).firstMatch
            let target = nativeSwitch.exists ? nativeSwitch : toggle
            XCTAssertTrue(target.isHittable, target.debugDescription)
            target.tap()
        }
        let valueChanged = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected), object: toggle
        )], timeout: 5)
        if valueChanged != .completed {
            let hierarchy = XCTAttachment(string: toggle.debugDescription)
            hierarchy.name = "Settings link-preview switch — expected \(expected)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Settings — link-preview toggle did not update"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(valueChanged, .completed, "Expected link previews value \(expected). \(toggle.debugDescription)")
        XCTAssertTrue(app.staticTexts["settings.linkPreviewExplanation"].exists)
        if let captureName {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = captureName
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app.goBackToTab()
    }

    @MainActor private func reopenDemoChat(in app: XCUIApplication) throws {
        app.selectTab("Chats")
        let row = app.sessionRow(titled: "Main chat")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 5))
    }
}
