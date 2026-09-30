import AppIntents
import SwiftUI
import SystemActions
import WidgetKit

struct NewChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zacisnotacompany.fancyclaw.new-chat") {
            ControlWidgetButton(action: NewChatIntent()) {
                Label("New chat", systemImage: "square.and.pencil")
            }
        }
        .displayName("New FancyClaw Chat")
        .description("Open FancyClaw and start a new chat.")
    }
}
