import GatewayClient

/// Coalesces updates at a fixed cadence rather than postponing them until a stream goes quiet.
@MainActor
final class StreamingThrottle {
    private let timing: GatewayTiming
    private let interval: Duration
    private var lastPublish: Duration?
    private var task: Task<Void, Never>?

    init(timing: GatewayTiming, interval: Duration) {
        self.timing = timing
        self.interval = interval
    }

    func schedule(_ publish: @escaping @MainActor () -> Void) {
        let now = timing.now()
        if interval <= .zero || lastPublish == nil || now - (lastPublish ?? now) >= interval {
            task?.cancel()
            task = nil
            lastPublish = now
            publish()
        } else if task == nil {
            let delay = interval - (now - (lastPublish ?? now))
            task = Task { [weak self, timing] in
                do { try await timing.sleep(delay) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.task = nil
                self.lastPublish = timing.now()
                publish()
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        lastPublish = nil
    }
}
