import Foundation
import SystemActions
import GatewayProtocol

/// Pure event reducer. It doesn't publish transcript text, commands, or credentials to the Lock Screen.
public struct RunActivityTracker: Sendable {
    public struct Run: Hashable, Sendable {
        public var attributes: RunActivityAttributes
        public var state: RunActivityAttributes.ContentState
    }
    public private(set) var runs: [String: Run] = [:]
    private var terminalRuns: Set<String> = []
    private var chatSequences: [String: Int] = [:]
    private var agentSequences: [String: Int] = [:]
    public init() {}

    @discardableResult
    public mutating func receive(_ frame: GatewayEventFrame, now: Date, agentName: (String) -> String) -> Run? {
        let id: String
        let key: String
        let agent: String?
        let status: RunActivityAttributes.Status
        var startedAt: Date?
        switch frame.event {
        case .chat(let event):
            id = event.runId; key = event.sessionKey; agent = event.agentId
            guard event.seq > chatSequences[id, default: -1] else { return nil }
            chatSequences[id] = event.seq
            switch event.state {
            case .status: status = .thinking
            case .delta: status = .streaming
            case .final(let final): status = final.yielded == true ? .thinking : .completed
            case .aborted: status = .aborted
            case .error: status = .failed
            case .unknown: return nil
            }
        case .agent(let event):
            guard event.stream == "lifecycle", let phase = event.data["phase"]?.stringValue else { return nil }
            id = event.runId
            guard event.seq > agentSequences[id, default: -1] else { return nil }
            agentSequences[id] = event.seq
            guard let sessionKey = event.sessionKey ?? runs[id]?.attributes.sessionKey else { return nil }
            key = sessionKey; agent = event.agentId
            switch phase {
            case "start":
                status = .thinking
                if let milliseconds = event.data["startedAt"]?.intValue, milliseconds > 0 {
                    startedAt = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
                }
            case "finishing": status = .finishing
            case "end": status = event.data["aborted"]?.boolValue == true ? .aborted : .completed
            case "error": status = .failed
            default: return nil
            }
        default: return nil
        }
        guard !id.isEmpty, !key.isEmpty, !terminalRuns.contains(id) else { return nil }
        let inferredAgent = key.split(separator: ":").dropFirst().first.map(String.init) ?? "Assistant"
        var run = runs[id] ?? Run(attributes: .init(runID: id, sessionKey: key),
            state: .init(agentName: agentName(agent ?? inferredAgent), startedAt: startedAt ?? now, status: status))
        if let agent { run.state.agentName = agentName(agent) }
        if let startedAt { run.state.startedAt = startedAt }
        run.state.status = status
        // The system animates elapsed time itself; don't update ActivityKit for every token.
        guard runs[id] != run else { return nil }
        if status.isTerminal { terminalRuns.insert(id); runs.removeValue(forKey: id) }
        else { runs[id] = run }
        return run
    }

    public mutating func disconnect() -> [Run] {
        for id in runs.keys { runs[id]?.state.status = .reconnecting }
        return Array(runs.values)
    }

    /// Catch-up ends activities for runs that finished while the app was suspended.
    public mutating func reconcile(sessionKey: String, activeRunIDs: Set<String>) -> [Run] {
        let matching = runs.values.filter { $0.attributes.sessionKey == sessionKey }
        return matching.compactMap { run in
            var run = run
            let id = run.attributes.runID
            if activeRunIDs.contains(id) {
                guard run.state.status == .reconnecting else { return nil }
                run.state.status = .thinking
                runs[id] = run
                return run
            }
            run.state.status = .completed
            runs.removeValue(forKey: id)
            terminalRuns.insert(id)
            return run
        }
    }
}
