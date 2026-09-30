/// Launch arguments that put the app into a deterministic mode for UI tests.
public enum LaunchArgument: String, CaseIterable, Sendable {
    /// Connect to an in-process fake Gateway instead of a real one.
    case fakeGateway = "-FakeGateway"

    /// Seed a fixture conversation for rendering checks.
    case demoConversation = "-DemoConversation"
}
