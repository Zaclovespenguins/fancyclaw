import Foundation
import GatewayProtocol
import os

/// Owns recovery of an already authenticated connection. Pairing stays in onboarding.
public actor ConnectionLifecycle {
    private static let logger = Logger(subsystem: "com.zacisnotacompany.fancyclaw", category: "ConnectionLifecycle")
    public private(set) var status: ConnectionStatus = .offline
    private let connection: GatewayConnection
    private let timing: GatewayTiming
    private let jitter: @Sendable () -> Double
    private let resync: @Sendable () async -> Void
    private var profile: GatewayProfile?
    private var foreground = true
    private var reachable = true
    private var interval: Duration = .seconds(15)
    private var lastTick: Duration = .zero
    private var lastSequence: Int?
    private var observers: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]
    private var eventTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var epoch = UUID()

    public init(connection: GatewayConnection, timing: GatewayTiming = .continuous,
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
                resync: @escaping @Sendable () async -> Void = {}) {
        self.connection = connection
        self.timing = timing
        self.jitter = jitter
        self.resync = resync
    }

    public func statuses() -> AsyncStream<ConnectionStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func setStatus(_ value: ConnectionStatus) {
        status = value
        for observer in observers.values { observer.yield(value) }
    }

    public func start(profile: GatewayProfile, hello: HelloOK) async {
        await stop()
        self.profile = profile
        interval = .milliseconds(max(hello.policy.tickIntervalMs, 1))
        lastTick = timing.now()
        let events = await connection.events()
        let failures = await connection.disconnections()
        eventTask = Task { [weak self] in
            for await frame in events {
                guard !Task.isCancelled else { break }
                await self?.receive(frame)
            }
        }
        failureTask = Task { [weak self] in
            for await _ in failures {
                guard !Task.isCancelled else { break }
                await self?.scheduleRecovery()
            }
        }
        setStatus(.connected)
        startWatchdog()
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let timing = timing
        let interval = interval
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await timing.sleep(interval) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.checkLiveness()
            }
        }
    }

    public func checkLiveness() {
        if status == .connected && timing.now() - lastTick > interval * 2 {
            scheduleRecovery()
        }
    }

    public func receive(_ frame: GatewayEventFrame) async {
        if let seq = frame.seq {
            if let previous = lastSequence, previous < Int.max, seq > previous + 1 { await resync() }
            if seq > (lastSequence ?? Int.min) { lastSequence = seq }
        }
        switch frame.event {
        case .tick: lastTick = timing.now()
        case .shutdown(let shutdown):
            scheduleRecovery(after: .milliseconds(max(shutdown.restartExpectedMs ?? 0, 0)))
        default: break
        }
    }

    public func setForeground(_ value: Bool) async {
        foreground = value
        await reconcileAvailability()
    }

    public func setReachable(_ value: Bool) async {
        reachable = value
        await reconcileAvailability()
    }

    /// True when the app is foregrounded and the network is reachable.
    public var isAvailable: Bool { foreground && reachable }

    private func reconcileAvailability() async {
        if !foreground || !reachable {
            // Publish offline before suspending so an interleaved foreground/reachable change sees it.
            epoch = UUID()
            recovery?.cancel()
            recovery = nil
            watchdog?.cancel()
            setStatus(.offline)
            await connection.disconnect()
            // Availability may have returned while disconnecting; that caller saw .offline and may have scheduled recovery already.
            if foreground && reachable && status != .connected { scheduleRecovery() }
        } else if status != .connected {
            scheduleRecovery()
        }
    }

    private func scheduleRecovery(after delay: Duration = .zero) {
        guard foreground, reachable, profile != nil, recovery == nil else { return }
        setStatus(.reconnecting)
        watchdog?.cancel()
        let generation = epoch
        recovery = Task { [weak self] in await self?.recover(after: delay, generation: generation) }
    }

    private func recover(after initialDelay: Duration, generation: UUID) async {
        await connection.disconnect()
        var delay = initialDelay
        var attempt = 0
        while !Task.isCancelled, generation == epoch, foreground, reachable, let profile {
            do {
                if delay > .zero { try await timing.sleep(delay) }
                try Task.checkCancellation()
                let hello = try await connection.connect(to: profile.url, token: profile.token,
                    bootstrapToken: profile.bootstrapToken, password: profile.password)
                guard generation == epoch, !Task.isCancelled else { return }
                interval = .milliseconds(max(hello.policy.tickIntervalMs, 1))
                lastTick = timing.now()
                lastSequence = nil
                recovery = nil
                setStatus(.connected)
                startWatchdog()
                await resync()
                return
            } catch is CancellationError { return }
            catch let error as GatewayErrorShape where error.code != .unavailable && error.retryable != true {
                Self.logger.error("Gateway recovery requires authentication")
                guard generation == epoch else { return }
                recovery = nil
                setStatus(.offline)
                return
            } catch {
                Self.logger.info("Gateway reconnect attempt failed")
                delay = ReconnectPolicy().delay(attempt: attempt, jitter: jitter())
                attempt += 1
            }
        }
    }

    public func stop() async {
        epoch = UUID()
        eventTask?.cancel()
        failureTask?.cancel()
        watchdog?.cancel()
        recovery?.cancel()
        eventTask = nil
        failureTask = nil
        watchdog = nil
        recovery = nil
        profile = nil
        lastSequence = nil
        setStatus(.offline)
    }
}
