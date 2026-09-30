import GatewayClient
import GatewayProtocol
import Observation
import UIKit
import SwiftUI
import VisionKit

struct OnboardingView: View {
    var onConnected: (GatewayProfile, GatewayConnection, HelloOK) -> Void
    var initialProfile: GatewayProfile?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var model = OnboardingModel()
    @State private var selectedNearby: GatewayProfile?
    @State private var showingScanner = false

    var body: some View {
        VStack(spacing: 0) {
                header
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                if case .waiting(let requestID, let remaining) = model.state {
                    ScrollView { waitingView(requestID: requestID, remaining: remaining) }
                } else {
                    TabView(selection: $model.selectedPage) {
                        welcomePage.tag(0)
                        connectPage.tag(1)
                        nearbyPage.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .background {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.52, 0.47], [1, 0.5], [0, 1], [0.5, 1], [1, 1]
                ], colors: [.indigo.opacity(0.24), .blue.opacity(0.14), .cyan.opacity(0.2),
                            .purple.opacity(0.16), .blue.opacity(0.1), .mint.opacity(0.16),
                            .indigo.opacity(0.12), .cyan.opacity(0.18), .blue.opacity(0.12)])
                    .ignoresSafeArea()
            }
            .navigationTitle("FancyClaw")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingScanner) {
                SetupCodeScanner(onCode: { code in
                    showingScanner = false
                    model.apply(code: code)
                }, onError: { message in
                    showingScanner = false
                    model.errorMessage = message
                })
                .ignoresSafeArea()
            }
            .confirmationDialog("Trust this Gateway?", isPresented: Binding(
                get: { selectedNearby != nil }, set: { if !$0 { selectedNearby = nil } }), titleVisibility: .visible) {
                Button("Trust and Connect") {
                    if let selectedNearby { model.connect(selectedNearby) }
                    selectedNearby = nil
                }
                Button("Cancel", role: .cancel) { selectedNearby = nil }
            } message: {
                Text(selectedNearby.map { "\($0.url.host ?? $0.url.absoluteString)\nFingerprint: \($0.tlsFingerprint ?? "Not advertised")" } ?? "")
            }
            .task {
                model.onConnected = onConnected
                if let initialProfile {
                    model.urlText = initialProfile.url.absoluteString
                    model.token = initialProfile.token ?? ""
                    model.password = initialProfile.password ?? ""
                    model.usesEphemeralIdentity = true
                    model.selectedPage = 1
                }
            }
            .onChange(of: model.selectedPage) { _, page in
                if page == 2 && initialProfile == nil { model.startDiscovery() }
                else { model.stopDiscovery() }
            }
            .onDisappear { model.stopDiscovery() }
            .sensoryFeedback(.error, trigger: model.errorMessage) { (_: String?, value: String?) in hapticsEnabled && value != nil }
    }

    private var header: some View {
        VStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "pawprint.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .padding(18)
                    .glassEffect(.regular, in: .circle)
                    .accessibilityHidden(true)
            }
            Text("FancyClaw")
                .font(.largeTitle.bold())
            if !dynamicTypeSize.isAccessibilitySize {
                Text("Your private window into OpenClaw")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
            }
        }
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 8 : 24)
        .padding(.bottom, 12)
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 18) {
                ContentUnavailableView {
                    Label {
                        Text("Your Gateway, at hand").foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(Color.primary)
                    }
                } description: {
                    Text("Connect securely to your OpenClaw Gateway to see your sessions and chat.")
                        .foregroundStyle(Color.primary)
                }
                Button { model.selectedPage = 1 } label: {
                    Label("Set up connection", systemImage: "arrow.right")
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(.background, in: .rect(cornerRadius: 24))
            .padding(.horizontal)
            .padding(.bottom, 48)
        }
    }

    private var setupCodeActions: some View {
        Group {
            Button("Use code", systemImage: "arrow.down.doc") { model.applyCode() }
            Button("Scan QR", systemImage: "qrcode.viewfinder") { showingScanner = true }
                .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
        }
        .frame(minHeight: 44)
        .buttonStyle(.borderless)
    }

    private var connectPage: some View {
        Form {
            Section {
                TextField("Paste setup code", text: $model.setupCode, prompt: Text("Paste setup code").foregroundStyle(Color.primary.opacity(0.65)), axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ViewThatFits(in: .horizontal) {
                    HStack { setupCodeActions }
                    VStack(alignment: .leading) { setupCodeActions }
                }
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { model.setupCode = value; model.applyCode() }
                }
            } header: {
                HStack { Text("Setup code").font(.headline).foregroundStyle(Color.primary) }
            }
            Section {
                TextField("Gateway URL", text: $model.urlText, prompt: Text("Gateway URL").foregroundStyle(Color.primary.opacity(0.65)))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Access token", text: $model.token, prompt: Text("Access token").foregroundStyle(Color.primary.opacity(0.65)))
                SecureField("Password", text: $model.password, prompt: Text("Password").foregroundStyle(Color.primary.opacity(0.65)))
                Button {
                    model.connectManual()
                } label: {
                    if model.isConnecting { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Connect").foregroundStyle(Color(uiColor: .systemBackground)).frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isConnecting)
                .accessibilityLabel(model.isConnecting ? "Connecting" : "Connect")
                .accessibilityIdentifier("onboarding.connect")
            } header: {
                HStack { Text("Manual connection").font(.headline).foregroundStyle(Color.primary) }
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 44) }
    }

    private var nearbyPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nearby Gateways").font(.title2.weight(.semibold))
            Text("Choose a Gateway on your local network. Confirm its fingerprint before connecting.")
                .font(.subheadline).foregroundStyle(.secondary)
            if model.nearby.isEmpty {
                ContentUnavailableView("Searching your network", systemImage: "dot.radiowaves.left.and.right",
                                       description: Text("Gateways that advertise Bonjour will appear here."))
            } else {
                List(model.nearby) { gateway in
                    Button {
                        guard let profile = gateway.profile else { return }
                        if gateway.tlsFingerprint != nil { selectedNearby = profile }
                        else { selectedNearby = profile }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(gateway.displayName).font(.headline)
                            Text(gateway.tailnetDNS ?? gateway.host ?? "Resolving local address")
                                .font(.caption).foregroundStyle(.secondary)
                            if let fingerprint = gateway.tlsFingerprint {
                                Text("SHA-256 · \(fingerprint)").font(.caption2.monospaced()).lineLimit(1)
                            }
                        }
                    }
                    .disabled(gateway.profile == nil)
                }
                .scrollContentBackground(.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func waitingView(requestID: String, remaining: Duration) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Waiting for approval").font(.title2.weight(.semibold))
            Text("Approve this device on the Gateway host, then FancyClaw will retry automatically.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("openclaw devices approve \(requestID)")
                .font(.callout.monospaced()).textSelection(.enabled)
                .padding().frame(maxWidth: .infinity).background(.thinMaterial, in: .rect(cornerRadius: 14))
            Button("Copy approval command", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "openclaw devices approve \(requestID)"
            }
            Text("Expires in about \(max(0, Int(remaining.components.seconds / 60))) min")
                .font(.caption).foregroundStyle(.secondary)
            Button("Cancel connection", role: .cancel) { model.cancel() }
        }
        .padding(28)
    }
}

@MainActor @Observable private final class OnboardingModel {
    enum State { case idle, connecting, waiting(requestID: String, remaining: Duration), connected }
    var state: State = .idle
    var selectedPage = 0
    var usesEphemeralIdentity = false
    var setupCode = ""
    var urlText = ""
    var token = ""
    var password = ""
    var errorMessage: String?
    var nearby: [BonjourGateway] = []
    var onConnected: ((GatewayProfile, GatewayConnection, HelloOK) -> Void)?
    private let discovery = BonjourDiscovery()
    private var connectTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private let retrySchedule = PairingRetrySchedule()
    private var identityStore = DeviceIdentityStore()
    private let profileStore = GatewayProfileStore()

    var isConnecting: Bool {
        switch state { case .connecting, .waiting: true; default: false }
    }

    func startDiscovery() {
        discovery.start()
        nearby = discovery.gateways
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.nearby = self.discovery.gateways
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopDiscovery() { discoveryTask?.cancel(); discovery.stop(); connectTask?.cancel() }

    func applyCode() { apply(code: setupCode) }

    func apply(code: String) {
        do {
            let parsed = try SetupCode.parse(code)
            urlText = parsed.profile.url.absoluteString
            token = parsed.profile.token ?? ""
            password = parsed.profile.password ?? ""
            connect(parsed.profile)
        } catch { errorMessage = "That setup code is invalid or has expired." }
    }

    func connectManual() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Enter a valid Gateway URL."; return
        }
        connect(GatewayProfile(url: url, token: token.isEmpty ? nil : token, password: password.isEmpty ? nil : password),
                persist: !usesEphemeralIdentity)
    }

    func connect(_ profile: GatewayProfile, persist: Bool = true) {
        connectTask?.cancel()
        connectTask = Task { [weak self] in await self?.performConnect(profile, persist: persist) }
    }

    func cancel() { connectTask?.cancel(); connectTask = nil; state = .idle }

    private func performConnect(_ profile: GatewayProfile, persist: Bool) async {
        errorMessage = nil
        state = .connecting
        do { try TransportPolicy.validate(profile.url) }
        catch { state = .idle; errorMessage = "Use secure wss:// for public Gateways; ws:// is limited to private networks."; return }
        do {
            let identity = persist ? try identityStore.loadOrCreate() : DeviceIdentity.generate()
            let delegate = profile.tlsFingerprint.map(GatewayTLSDelegate.init(fingerprint:))
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let store = persist ? identityStore : nil
            let connection = GatewayConnection(identity: identity, identityStore: store, session: session)
            let hello = try await PairingCoordinator().connect(using: {
                try await connection.connect(to: profile.url, token: profile.token,
                    bootstrapToken: profile.bootstrapToken, password: profile.password)
            }, onWaiting: { [weak self] requestID, remaining in
                await MainActor.run { self?.state = .waiting(requestID: requestID, remaining: remaining) }
            })
            var connectedProfile = profile
            connectedProfile.bootstrapToken = nil
            if persist { try profileStore.save(connectedProfile) }
            state = .connected
            onConnected?(connectedProfile, connection, hello)
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .idle
            errorMessage = error.localizedDescription
        }
    }
}
