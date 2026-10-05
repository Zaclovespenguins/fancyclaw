import SwiftUI
import ChatCore
import DesignSystem
import GatewayClient
import GatewayProtocol

struct ContentView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ThemeID.storageKey) private var themeID: ThemeID = .default

    var body: some View {
        Group {
            if model.isPreparing {
                NavigationStack {
                    ProgressView("Opening FancyClaw…")
                        .navigationTitle("FancyClaw")
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else if model.conversation != nil {
                // The tab shell owns its per-tab navigation stacks.
                RootView(model: model)
            } else {
                NavigationStack {
                    OnboardingView(onConnected: connected, initialProfile: model.initialProfile)
                }
            }
        }
        .environment(\.appTheme, themeID.theme)
        .tint(themeID.theme.accent.color)
        .task { await model.prepare() }
        .onOpenURL { url in Task { await model.openActivityURL(url) } }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.setForeground(phase != .background) }
        }
        .alert("Connection issue", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func connected(profile: GatewayProfile, connection: GatewayConnection, hello: HelloOK) {
        Task { await model.activate(profile: profile, connection: connection, hello: hello) }
    }
}

#Preview { ContentView(model: AppModel()) }
