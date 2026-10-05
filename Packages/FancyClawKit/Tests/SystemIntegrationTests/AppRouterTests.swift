import Foundation
import SystemActions
import SystemIntegration
import Testing

@Suite("Tab and route navigation")
@MainActor struct AppRouterTests {
    @Test func startsOnAnEmptyHome() {
        let router = AppRouter()
        #expect(router.selectedTab == .home)
        for tab in AppTab.allCases { #expect(router.path(for: tab).isEmpty) }
    }

    @Test func intentFromHomeRootPushesTheChatOnHome() {
        let router = AppRouter()
        router.openChat(sessionKey: "agent:main:main")
        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home) == [.chat(sessionKey: "agent:main:main")])
    }

    @Test func intentWhileOnChatsStaysOnChats() {
        let router = AppRouter()
        router.selectedTab = .chats
        router.openChat(sessionKey: "agent:main:other")
        #expect(router.selectedTab == .chats)
        #expect(router.path(for: .chats) == [.chat(sessionKey: "agent:main:other")])
        #expect(router.path(for: .home).isEmpty)
    }

    @Test(arguments: [AppTab.skills, .activity])
    func intentFromAPlaceholderRootLandsOnHome(_ tab: AppTab) {
        let router = AppRouter()
        router.selectedTab = tab
        router.openChat(sessionKey: "agent:main:main")
        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home) == [.chat(sessionKey: "agent:main:main")])
        #expect(router.path(for: tab).isEmpty)
    }

    @Test func intentOnATabWithPushedContentStaysThere() {
        let router = AppRouter()
        router.selectedTab = .skills
        router.setPath([.skill(id: "github")], for: .skills)
        router.openChat(sessionKey: "agent:main:main")
        #expect(router.selectedTab == .skills)
        #expect(router.path(for: .skills) == [.skill(id: "github"), .chat(sessionKey: "agent:main:main")])
    }

    @Test func aSecondChatReplacesTheChatOnTop() {
        let router = AppRouter()
        router.openChat(sessionKey: "agent:main:main")
        router.openChat(sessionKey: "agent:main:new")
        #expect(router.path(for: .home) == [.chat(sessionKey: "agent:main:new")])
        router.openSettings()
        router.openChat(sessionKey: "agent:main:third")
        #expect(router.path(for: .home) == [.chat(sessionKey: "agent:main:new"), .settings, .chat(sessionKey: "agent:main:third")])
    }

    @Test func liveActivityURLOpensItsSession() throws {
        let router = AppRouter()
        router.selectedTab = .activity
        let url = try #require(RunActivityAttributes(runID: "run-1", sessionKey: "agent:main:live").sessionURL)
        #expect(router.openActivityURL(url) == "agent:main:live")
        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home) == [.chat(sessionKey: "agent:main:live")])
    }

    @Test func unrelatedURLsDoNotNavigate() throws {
        let router = AppRouter()
        #expect(router.openActivityURL(try #require(URL(string: "https://example.com/session?key=x"))) == nil)
        #expect(router.openActivityURL(try #require(URL(string: "fancyclaw://session"))) == nil)
        #expect(router.path(for: .home).isEmpty)
    }

    @Test func approvalReviewFocusesTheApprovalInItsChat() {
        let router = AppRouter()
        router.selectedTab = .chats
        #expect(router.reviewApproval(id: "approval-1", sessionKey: "agent:main:other"))
        #expect(router.path(for: .chats) == [.chat(sessionKey: "agent:main:other", focusApproval: "approval-1")])
    }

    @Test func approvalReviewWithoutASessionDoesNotNavigate() {
        let router = AppRouter()
        #expect(!router.reviewApproval(id: "approval-1", sessionKey: nil))
        #expect(!router.reviewApproval(id: "approval-1", sessionKey: ""))
        #expect(router.path(for: .home).isEmpty)
    }

    @Test func settingsIsPushedOnceOnHome() {
        let router = AppRouter()
        router.selectedTab = .chats
        router.openSettings()
        router.openSettings()
        #expect(router.selectedTab == .home)
        #expect(router.path(for: .home) == [.settings])
    }

    @Test func closingADeletedSessionPopsItsChatsEverywhere() {
        let router = AppRouter()
        router.openChat(sessionKey: "agent:main:gone")
        router.openSettings()
        router.selectedTab = .chats
        router.openChat(sessionKey: "agent:main:gone")
        router.setPath([.chat(sessionKey: "agent:main:kept")], for: .activity)
        #expect(router.openSessionKeys == ["agent:main:gone", "agent:main:kept"])
        router.closeChats(for: "agent:main:gone")
        #expect(router.path(for: .home).isEmpty)
        #expect(router.path(for: .chats).isEmpty)
        #expect(router.path(for: .activity) == [.chat(sessionKey: "agent:main:kept")])
        #expect(router.selectedTab == .chats)
    }

    @Test func resetReturnsToAnEmptyHome() {
        let router = AppRouter()
        router.selectedTab = .chats
        router.openChat(sessionKey: "agent:main:main")
        router.reset()
        #expect(router.selectedTab == .home)
        #expect(router.openSessionKeys.isEmpty)
    }
}
