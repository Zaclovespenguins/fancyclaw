import SwiftUI
import AppIntents
import SystemIntegration
import SystemActions

@main
struct FancyClawApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        let service = IntentService(ask: { try await model.askFromIntent($0) },
            newChat: { try await model.newChatFromIntent() },
            openSession: { try await model.openSessionFromIntent($0) },
            sessions: { try model.cachedIntentSessions() })
        AppDependencyManager.shared.add(dependency: service)
        let newChat = NewChatAction(create: service.newChat)
        AppDependencyManager.shared.add(dependency: newChat)
        FancyClawShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-PolishDark") ? .dark
                    : ProcessInfo.processInfo.arguments.contains("-PolishLight") ? .light : nil)
                #endif
        }
    }
}
