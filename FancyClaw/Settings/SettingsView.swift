import DesignSystem
import GatewayClient
import SwiftUI

/// `@AppStorage` keys owned by Settings. The haptics key predates the redesign and must stay stable.
enum SettingsKeys {
    static let hapticsEnabled = "hapticsEnabled"
    static let userName = "userName"
    static let showLinkPreviews = "showLinkPreviews"
}

/// Connection, preferences, appearance, and About. Replaces the chat's former connection menu.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.appTheme) private var theme
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @AppStorage(SettingsKeys.showLinkPreviews) private var showLinkPreviews = true
    @AppStorage(ThemeID.storageKey) private var themeID: ThemeID = .default
    @State private var confirmingDisconnect = false

    private var statusColor: Color {
        switch model.status {
        case .connected: theme.online.color
        case .reconnecting: theme.warning.color
        case .offline: theme.textTertiary.color
        }
    }

    private var statusText: String {
        switch model.status {
        case .connected: "Connected"
        case .reconnecting: "Reconnecting…"
        case .offline: "Offline"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private func header(_ title: String) -> some View {
        Text(title).foregroundStyle(theme.textSecondary.color)
    }

    private func footer(_ text: String) -> some View {
        Text(text).foregroundStyle(theme.textSecondary.color)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.status")
                .accessibilityValue(statusText)
                if let host = model.gatewayHost {
                    LabeledContent("Gateway", value: host)
                        .accessibilityIdentifier("settings.host")
                }
                if model.status != .connected {
                    Button("Reconnect", systemImage: "arrow.clockwise") {
                        Task { await model.reconnect() }
                    }
                    .accessibilityIdentifier("settings.reconnect")
                }
                Button("Disconnect", systemImage: "xmark.circle") {
                    confirmingDisconnect = true
                }
                // The theme's danger token keeps destructive text above 4.5:1; the dialog keeps the destructive role.
                .foregroundStyle(theme.danger.color)
                .accessibilityIdentifier("settings.disconnect")
            } header: {
                header("Connection")
            }

            Section {
                Toggle("Haptics", isOn: $hapticsEnabled)
                    .accessibilityIdentifier("settings.haptics")
                Toggle("Show link previews", isOn: $showLinkPreviews)
                    .accessibilityIdentifier("settings.linkPreviews")
                Text("Previews load titles and images from linked websites.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                header("Preferences")
            }

            Section {
                // A read-only row until more themes exist.
                LabeledContent("Theme", value: themeID.displayName)
                    .accessibilityIdentifier("settings.theme")
            } header: {
                header("Appearance")
            } footer: {
                footer("More themes coming soon.")
            }

            Section {
                TextField("Your name", text: $userName)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .accessibilityIdentifier("settings.name")
            } header: {
                header("Profile")
            } footer: {
                footer("Used to greet you on Home. Stays on this iPhone.")
            }

            Section {
                LabeledContent("FancyClaw", value: appVersion)
                LabeledContent("Gateway version", value: model.gatewayVersion ?? "Unknown")
                    .accessibilityIdentifier("settings.gatewayVersion")
            } header: {
                header("About")
            }
        }
        // A solid base rather than the glow: grouped headers and footers must stay readable over it.
        .scrollContentBackground(.hidden)
        .background { theme.bg.color.ignoresSafeArea() }
        .navigationTitle("Settings")
        // The floating tab bar would cover the last rows; Settings is a pushed detail screen.
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("Disconnect from this Gateway?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await model.disconnect() }
            }
            .accessibilityIdentifier("settings.confirmDisconnect")
        } message: {
            Text("FancyClaw forgets this Gateway on this iPhone. Set it up again to reconnect.")
        }
    }
}
