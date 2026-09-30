import ActivityKit
import Foundation

public struct RunActivityAttributes: ActivityAttributes, Hashable, Sendable {
    public let runID: String
    public let sessionKey: String
    public init(runID: String, sessionKey: String) {
        self.runID = runID
        self.sessionKey = sessionKey
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var agentName: String
        public var startedAt: Date
        public var status: Status
        public init(agentName: String, startedAt: Date, status: Status) {
            self.agentName = agentName
            self.startedAt = startedAt
            self.status = status
        }
    }

    public enum Status: String, Codable, Hashable, Sendable {
        case thinking, streaming, finishing, reconnecting, completed, aborted, failed
        public var label: String {
            switch self {
            case .thinking: "Thinking"
            case .streaming: "Replying"
            case .finishing: "Finishing"
            case .reconnecting: "Open FancyClaw to refresh"
            case .completed: "Completed"
            case .aborted: "Stopped"
            case .failed: "Failed"
            }
        }
        public var isTerminal: Bool { self == .completed || self == .aborted || self == .failed }
    }
}
