/// Well-known values for reaching an OpenClaw Gateway.
public enum GatewayDefaults {
    /// The port a Gateway serves WebSocket and HTTP on unless configured otherwise.
    public static let port = 18789

    /// The Bonjour service type Gateways advertise on the local network.
    public static let bonjourServiceType = "_openclaw-gw._tcp"
}
