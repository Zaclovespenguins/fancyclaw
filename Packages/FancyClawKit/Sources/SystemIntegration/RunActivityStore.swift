import Foundation
import GatewayClient
import GatewayProtocol
import Observation

/// One connection-wide listener continues to track runs when the selected chat changes.
@MainActor @Observable public final class RunActivityStore {
    private let connection: GatewayConnection
    private let driver: any RunActivityDriver
    private let agentName: (String) -> String
    private var tracker = RunActivityTracker()
    private var eventTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var isStarting = false
    private var generation = UUID()
    public var sessionKeys: Set<String> { Set(tracker.runs.values.map(\.attributes.sessionKey)) }
    public var activeRuns: [RunActivityTracker.Run] { Array(tracker.runs.values) }
    public var terminalRunIDs: Set<String> { tracker.terminalRunIDs }

    public init(connection: GatewayConnection, driver: any RunActivityDriver, agentName: @escaping (String) -> String) {
        self.connection = connection
        self.driver = driver
        self.agentName = agentName
    }

    public func start() async {
        guard eventTask == nil, !isStarting else { return }
        isStarting = true
        let token = generation
        defer { if generation == token { isStarting = false } }
        let stream = await connection.events()
        guard generation == token, eventTask == nil else { return }
        eventTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                await self.receive(frame)
            }
        }
    }

    public func receive(_ frame: GatewayEventFrame, now: Date = .now) async {
        if let run = tracker.receive(frame, now: now, agentName: agentName) { enqueue([run]) }
        await deliveryTask?.value
    }

    public func connectionDidDisconnect() async {
        enqueue(tracker.disconnect())
        await deliveryTask?.value
    }

    public func reconcile(sessionKey: String, activeRunIDs: Set<String>) async {
        applySnapshot(sessionKey: sessionKey, activeRunIDs: activeRunIDs)
        await deliveryTask?.value
    }

    /// Reduce the snapshot synchronously with the conversation's reconciliation. Driver delivery stays ordered.
    public func applySnapshot(sessionKey: String, activeRunIDs: Set<String>) {
        enqueue(tracker.reconcile(sessionKey: sessionKey, activeRunIDs: activeRunIDs))
    }

    private func enqueue(_ runs: [RunActivityTracker.Run]) {
        guard !runs.isEmpty else { return }
        let previous = deliveryTask
        let driver = driver
        deliveryTask = Task {
            await previous?.value
            for run in runs { await driver.publish(run) }
        }
    }

    public func stop() async {
        generation = UUID()
        isStarting = false
        eventTask?.cancel()
        eventTask = nil
        tracker = RunActivityTracker()
        await deliveryTask?.value
        await driver.endAll()
    }
}
