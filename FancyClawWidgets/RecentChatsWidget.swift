import SwiftUI
import WidgetKit

/// Shows the most recent chats. Placeholder until the shared cache exists.
struct RecentChatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentChats", provider: Provider()) { _ in
            RecentChatsView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Chats")
        .description("Jump back into a recent conversation.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

private struct SimpleEntry: TimelineEntry {
    let date: Date
}

private struct RecentChatsView: View {
    var body: some View {
        Label("FancyClaw", systemImage: "bubble.left.and.text.bubble.right")
            .font(.headline)
    }
}

#Preview(as: .systemSmall) {
    RecentChatsWidget()
} timeline: {
    SimpleEntry(date: .now)
}
