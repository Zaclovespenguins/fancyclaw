/// The Gateway protocol revision this client speaks.
///
/// OpenClaw's protocol moves quickly, so FancyClaw pins both the wire version and the release whose schema
/// the fixtures in `TestSupport` were generated from. Run `Scripts/refresh-protocol-schema.mjs` when bumping.
public enum ProtocolVersion {
    /// The only wire protocol version FancyClaw negotiates (`minProtocol` and `maxProtocol`).
    public static let current = 4

    /// The OpenClaw release the protocol models were validated against.
    public static let pinnedRelease = "2026.9.6"
}
