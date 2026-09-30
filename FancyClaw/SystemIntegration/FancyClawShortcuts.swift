import AppIntents
import SystemIntegration
import SystemActions

public struct FancyClawShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskFancyClawIntent(), phrases: ["Ask \(.applicationName)"],
                    shortTitle: "Ask FancyClaw", systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(intent: NewChatIntent(), phrases: ["Start a new chat in \(.applicationName)"],
                    shortTitle: "New Chat", systemImageName: "square.and.pencil")
        AppShortcut(intent: OpenSessionIntent(), phrases: ["Open a chat in \(.applicationName)", "Open \(\.$target) in \(.applicationName)"],
                    shortTitle: "Open Chat", systemImageName: "bubble.left")
    }
}
