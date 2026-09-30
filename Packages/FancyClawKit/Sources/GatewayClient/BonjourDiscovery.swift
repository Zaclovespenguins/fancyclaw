import Foundation
import Network
import Observation

public struct BonjourGateway: Identifiable, Hashable, Sendable {
    public var id: String { serviceName + "@" + endpointDescription }
    public var serviceName: String
    public var displayName: String
    public var endpointDescription: String
    public var host: String?
    public var port: Int
    public var tls: Bool
    public var tlsFingerprint: String?
    public var tailnetDNS: String?

    public var profile: GatewayProfile? {
        let target = tailnetDNS ?? host
        guard let target else { return nil }
        var components = URLComponents()
        components.scheme = tls ? "wss" : "ws"
        components.host = target
        components.port = port
        guard let url = components.url else { return nil }
        return GatewayProfile(url: url, tlsFingerprint: tlsFingerprint)
    }
}

/// Browses `_openclaw-gw._tcp` services on the local network.
@MainActor @Observable public final class BonjourDiscovery {
    public private(set) var gateways: [BonjourGateway] = []
    private var browser: NWBrowser?
    private var resolutions: [NWEndpoint: BonjourGateway] = [:]

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_openclaw-gw._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        browser.stateUpdateHandler = { _ in }
        self.browser = browser
        browser.start(queue: .main)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        gateways = []
        resolutions = [:]
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        let retained = Set(results.map(\.endpoint))
        resolutions = resolutions.filter { retained.contains($0.key) }
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            let txt: [String: String]
            if case .bonjour(let record) = result.metadata { txt = record.dictionary }
            else { txt = [:] }
            resolutions[result.endpoint] = BonjourGateway(serviceName: name,
                displayName: txt["displayName"] ?? name,
                endpointDescription: String(describing: result.endpoint), host: txt["lanHost"],
                port: Int(txt["gatewayPort"] ?? "18789") ?? 18789,
                tls: txt["gatewayTls"]?.lowercased() == "true" || txt["gatewayTls"] == "1",
                tlsFingerprint: txt["gatewayTlsSha256"], tailnetDNS: txt["tailnetDns"])
        }
        gateways = resolutions.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
