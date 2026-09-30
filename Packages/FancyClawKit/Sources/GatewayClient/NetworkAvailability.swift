import Network

/// Bridges NWPathMonitor without sharing mutable callback state across executors.
public final class NetworkAvailability: Sendable {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: .init(label: "FancyClaw.NetworkAvailability"))
        }
    }
}
