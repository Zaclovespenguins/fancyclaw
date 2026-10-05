import GatewayProtocol

/// Isolated source-derived data; this never reads the owner's installed skills or Gateway.
public enum SkillsDemo {
    public static func payload() throws -> JSONValue {
        guard let payload = try Fixtures.frame("skills-status.res")["payload"] else {
            throw Fixtures.Error.missing("skills-status.res payload")
        }
        return payload
    }
}
