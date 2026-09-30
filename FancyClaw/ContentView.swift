import DesignSystem
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("FancyClaw", systemImage: "bubble.left.and.text.bubble.right")
            } description: {
                MarkdownText("A polished client for **OpenClaw**.")
            }
            .navigationTitle("FancyClaw")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
