import ActivityKit
import SwiftUI
import SystemActions
import WidgetKit

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            RunActivityView(state: context.state)
                .padding()
                .widgetURL(context.attributes.sessionURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("FancyClaw", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.caption)
                        .fixedSize(horizontal: true, vertical: false)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunElapsedTime(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.agentName).font(.headline)
                        Text(context.state.status.label).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "bubble.left.and.text.bubble.right").accessibilityLabel("FancyClaw")
            } compactTrailing: {
                RunElapsedTime(state: context.state).frame(maxWidth: 55)
            } minimal: {
                Image(systemName: "bubble.left.and.text.bubble.right").accessibilityLabel("FancyClaw")
            }
            .widgetURL(context.attributes.sessionURL)
        }
    }
}

#Preview("Replying", as: .content, using: RunActivityAttributes(runID: "preview", sessionKey: "agent:main:main")) {
    RunLiveActivity()
} contentStates: {
    RunActivityAttributes.ContentState(agentName: "Main", startedAt: .now.addingTimeInterval(-42), status: .streaming)
    RunActivityAttributes.ContentState(agentName: "Main", startedAt: .now.addingTimeInterval(-42), status: .reconnecting)
}
