import XCTest

/// Navigation helpers for the tab shell: chats are pushed with the tab bar hidden.
extension XCUIApplication {
    var tabBar: XCUIElement { tabBars.firstMatch }

    /// The compose (New Chat) button drawn as the detached search-role tab.
    var composeButton: XCUIElement { tabBars.buttons["New Chat"] }

    /// Taps the navigation bar's back button and waits for the tab bar to return.
    @MainActor func goBackToTab(file: StaticString = #filePath, line: UInt = #line) {
        let back = navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No back button", file: file, line: line)
        back.tap()
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar did not return", file: file, line: line)
    }

    @MainActor func selectTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(name) tab", file: file, line: line)
        button.tap()
    }

    /// Leaves a pushed chat and shows the Chats tab list.
    @MainActor func openChatsTab(file: StaticString = #filePath, line: UInt = #line) {
        if !tabBar.exists { goBackToTab(file: file, line: line) }
        selectTab("Chats", file: file, line: line)
        XCTAssertTrue(navigationBars["Chats"].waitForExistence(timeout: 5), file: file, line: line)
    }

    func sessionRow(titled title: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sessions.row.", title)).firstMatch
    }
}
