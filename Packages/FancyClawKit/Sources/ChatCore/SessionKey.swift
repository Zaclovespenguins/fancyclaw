/// Identifies a chat session on the Gateway, such as `agent:main:main`.
public struct SessionKey: RawRepresentable, Hashable, Sendable, Codable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The main session of the default agent.
    public static let main = SessionKey(rawValue: "agent:main:main")
}
