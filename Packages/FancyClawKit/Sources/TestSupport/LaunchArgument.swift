/// Launch arguments that put the app into a deterministic mode for UI tests.
public enum LaunchArgument: String, CaseIterable, Sendable {
    /// Chats with every date group and a running session that also needs approval.
    case demoSessions = "-DemoSessions"
    /// An empty Chats roster, isolated from saved profiles and caches.
    case demoSessionsEmpty = "-DemoSessionsEmpty"
    /// Home dashboard with pending commands, a run and recent history.
    case demoHome = "-DemoHome"
    /// Connect to an in-process fake Gateway instead of a real one.
    case fakeGateway = "-FakeGateway"

    /// Seed attachment drafts on an isolated FakeGateway.
    case demoAttachments = "-DemoAttachments"

    /// Seed a fixture conversation for rendering checks.
    case demoConversation = "-DemoConversation"

    /// Seed final and streaming links; metadata is stubbed and never contacts the websites.
    case demoLinkPreviews = "-DemoLinkPreviews"
}
