/// The OpenClaw Gateway protocol this client speaks.
///
/// The protocol moves quickly, so FancyClaw pins to one release and validates
/// its models against fixtures generated from that release's schema.
public enum ProtocolVersion {
    /// The protocol version sent as both `minProtocol` and `maxProtocol` in `connect`.
    public static let current = 4

    /// The OpenClaw release the models and fixtures were verified against.
    public static let pinnedRelease = "2026.9.6"
}
