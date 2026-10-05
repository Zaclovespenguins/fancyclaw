import Foundation
import Observation
import SystemActions

/// The root tabs. Compose is a tab-bar button, not a destination, so it has no case here.
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home, chats, skills, activity
}

/// Destinations pushed onto a tab's navigation stack.
public enum AppRoute: Hashable, Sendable {
    case chat(sessionKey: String, focusApproval: String? = nil)
    case settings
    case skill(id: String)

    public var sessionKey: String? {
        if case .chat(let key, _) = self { return key }
        return nil
    }
}

/// Tab selection and per-tab navigation paths. Pure state, so routing rules are unit-testable without views.
@MainActor @Observable public final class AppRouter {
    public var selectedTab: AppTab = .home
    private var paths: [AppTab: [AppRoute]] = [:]

    public init() {}

    public func path(for tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }
    public func setPath(_ path: [AppRoute], for tab: AppTab) { paths[tab] = path }

    /// The tab a chat opened from outside a tab's own UI lands on: Home and Chats keep their stack;
    /// Skills and Activity keep it only when something is already pushed, otherwise the chat goes to Home.
    public var chatDestinationTab: AppTab {
        switch selectedTab {
        case .home, .chats: selectedTab
        case .skills, .activity: path(for: selectedTab).isEmpty ? .home : selectedTab
        }
    }

    /// Shows a chat. A chat already on top of the stack is replaced rather than stacked, so repeated
    /// intents, compose taps, and Live Activity opens never build a chat-on-chat history.
    public func openChat(sessionKey: String, focusApproval: String? = nil) {
        let tab = chatDestinationTab
        var path = path(for: tab)
        let route = AppRoute.chat(sessionKey: sessionKey, focusApproval: focusApproval)
        if path.last?.sessionKey != nil { path[path.count - 1] = route } else { path.append(route) }
        paths[tab] = path
        selectedTab = tab
    }

    /// Opens the chat a Live Activity URL names. Returns the session key, or nil for an unrelated URL.
    @discardableResult
    public func openActivityURL(_ url: URL) -> String? {
        guard let key = RunActivityAttributes.sessionKey(from: url) else { return nil }
        openChat(sessionKey: key)
        return key
    }

    /// Approval Review: opens the approval's chat, focused on its card. Returns false when the approval
    /// names no session, so the caller can present the card on its own instead.
    @discardableResult
    public func reviewApproval(id: String, sessionKey: String?) -> Bool {
        guard let sessionKey, !sessionKey.isEmpty else { return false }
        openChat(sessionKey: sessionKey, focusApproval: id)
        return true
    }

    /// Pushes Settings on the Home stack (its avatar is the entry point), reusing an existing Settings entry.
    public func openSettings() {
        var path = path(for: .home)
        if let index = path.firstIndex(of: .settings) { path.removeSubrange((index + 1)...) } else { path.append(.settings) }
        paths[.home] = path
        selectedTab = .home
    }

    /// Removes every pushed chat for a session that no longer exists, along with anything pushed above it.
    public func closeChats(for sessionKey: String) {
        for (tab, path) in paths {
            if let index = path.firstIndex(where: { $0.sessionKey == sessionKey }) {
                paths[tab] = Array(path[..<index])
            }
        }
    }

    /// Session keys that are currently pushed on any tab.
    public var openSessionKeys: Set<String> {
        Set(paths.values.flatMap { $0.compactMap(\.sessionKey) })
    }

    /// Clears every stack and returns to Home, for disconnect.
    public func reset() {
        paths = [:]
        selectedTab = .home
    }
}
