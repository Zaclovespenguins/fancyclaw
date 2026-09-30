public enum ConnectionStatus: String, Sendable {
    case connected = "Connected"
    case reconnecting = "Reconnecting"
    case offline = "Offline"
}
