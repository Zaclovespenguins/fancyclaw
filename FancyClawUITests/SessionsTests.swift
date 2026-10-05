import XCTest

final class SessionsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCreateRenameAndDeleteInChatsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoConversation"]
        app.launch()
        // The demo opens the seeded chat pushed on Home.
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 15))
        app.openChatsTab()
        let initialList = XCTAttachment(screenshot: app.screenshot())
        initialList.name = "Chats tab"
        initialList.lifetime = .keepAlways
        add(initialList)
        app.buttons["sessions.new"].tap()
        // A new chat is pushed on the Chats tab; go back to manage it.
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 10))
        app.goBackToTab()
        let row = app.sessionRow(titled: "New chat")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("Slice six chat")
        app.alerts.buttons["Save"].tap()
        let renamed = app.sessionRow(titled: "Slice six chat")
        XCTAssertTrue(renamed.waitForExistence(timeout: 10))
        let renamedList = XCTAttachment(screenshot: app.screenshot())
        renamedList.name = "Renamed chat"
        renamedList.lifetime = .keepAlways
        add(renamedList)
        renamed.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete chat"].waitForExistence(timeout: 5))
        cancelConfirmation(in: app, buttonTitle: "Delete chat")
        XCTAssertTrue(renamed.exists, "Cancelling deletion removed the chat")
        renamed.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.buttons["Delete chat"].tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: renamed)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.sessionRow(titled: "Main chat").waitForExistence(timeout: 5))
        // Opening a row pushes that chat on the Chats tab.
        app.sessionRow(titled: "Main chat").tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.toolchip.")).firstMatch
            .waitForExistence(timeout: 10))
    }

    @MainActor func testDateGroupsCombinedStatusesAndSearch() throws {
        let app = launchSessions()
        for title in ["Pinned", "Today", "Yesterday", "Earlier"] {
            let header = app.descendants(matching: .any).matching(identifier: "sessions.group.\(title)").firstMatch
            reveal(header, in: app)
        }
        XCTAssertFalse(app.sessionRow(titled: "Archived chat").exists)
        let running = app.buttons["sessions.row.agent:main:sessions-running"]
        reveal(running, in: app, scrollingUp: false)
        XCTAssertTrue(running.label.contains("Running"), running.label)
        XCTAssertTrue(running.label.contains("Needs approval"), running.label)
        let search = app.searchFields["Search chats"]
        reveal(search, in: app, scrollingUp: false)
        search.tap()
        search.typeText("Weekend")
        search.typeText("\n")
        XCTAssertTrue(app.sessionRow(titled: "Weekend plans").waitForExistence(timeout: 5))
        XCTAssertFalse(app.sessionRow(titled: "Photo sync").exists)
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Weekend".count))
        search.typeText("No matching sessions")
        search.typeText("\n")
        let empty = app.descendants(matching: .any).matching(identifier: "sessions.searchEmpty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.row.")).count, 0)
        // Cancel clears the bound query and restores the complete roster.
        search.tap()
        let cancel = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.sessionRow(titled: "Photo sync").waitForExistence(timeout: 5))
    }

    @MainActor func testResetRequiresConfirmationAndClearsHistory() throws {
        let app = launchSessions()
        let row = app.buttons["sessions.row.agent:main:sessions-running"]
        reveal(row, in: app)
        row.tap()
        let history = app.staticTexts["The date parser is ready for review."]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        app.goBackToTab()
        row.press(forDuration: 1)
        app.buttons["Reset"].tap()
        XCTAssertTrue(app.buttons["Reset chat"].waitForExistence(timeout: 5))
        cancelConfirmation(in: app, buttonTitle: "Reset chat")
        row.tap()
        XCTAssertTrue(history.waitForExistence(timeout: 5), "Cancelling reset removed the history")
        app.goBackToTab()
        row.swipeLeft()
        app.buttons["Reset"].tap()
        app.buttons["Reset chat"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["approval.deny.sessions-approval"].waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: history
        )], timeout: 5), .completed, "Confirmed reset left the old transcript visible")
    }

    @MainActor func testEmptyChatsComposeCreatesFirstConversation() throws {
        let app = launchSessions("-DemoSessionsEmpty")
        XCTAssertTrue(app.staticTexts["No chats yet"].waitForExistence(timeout: 5))
        app.buttons["sessions.new"].tap()
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 10))
        app.goBackToTab()
        XCTAssertTrue(app.sessionRow(titled: "New chat").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No chats yet"].exists)
    }

    @MainActor func testRenameFailureShowsDismissibleErrorAndPreservesTitle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoSessionActionError"]
        app.launch()
        XCTAssertTrue(app.textFields["chat.composer"].waitForExistence(timeout: 15))
        app.openChatsTab()
        let row = app.sessionRow(titled: "Main chat")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1)
        app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Main chat".count))
        field.typeText("Rejected name")
        app.alerts.buttons["Save"].tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The demo Gateway rejected the chat change.")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        XCTAssertFalse(app.sessionRow(titled: "Rejected name").exists)
        app.buttons["Dismiss error"].tap()
        XCTAssertFalse(error.exists)
    }

    @MainActor func testChatsScreenshotsLightDarkDefaultAndXXL() throws {
        for dark in [false, true] {
            for large in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-DemoSessions", dark ? "-PolishDark" : "-PolishLight"]
                if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
                app.launch()
                XCTAssertTrue(app.buttons["sessions.new"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.sessionRow(titled: "Gateway notes").waitForExistence(timeout: 5))
                retain(app, "Chats — \(dark ? "dark" : "light") \(large ? "XXL" : "default") top")
                reveal(app.sessionRow(titled: "Packing checklist"), in: app)
                retain(app, "Chats — \(dark ? "dark" : "light") \(large ? "XXL" : "default") earlier")
                app.terminate()
            }
        }
    }

    @MainActor private func launchSessions(_ mode: String = "-DemoSessions") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [mode]
        app.launch()
        XCTAssertTrue(app.buttons["sessions.new"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func cancelConfirmation(in app: XCUIApplication, buttonTitle: String) {
        // iOS 27 presents confirmationDialog as a popover with a native outside-dismiss region,
        // rather than a Cancel button. Its left margin is outside the centered destructive action.
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            let dismissRegion = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
            dismissRegion.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons[buttonTitle]
        )], timeout: 5), .completed, "The confirmation popover did not dismiss")
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = true) {
        let list = app.descendants(matching: .any).matching(identifier: "sessions.list").firstMatch
        for _ in 0..<8 where !element.isHittable {
            if scrollingUp { list.swipeUp() } else { list.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, element.debugDescription)
    }

    @MainActor private func retain(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
