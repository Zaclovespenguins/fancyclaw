import SwiftUI
import SystemActions

struct RunActivityView: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.agentName).font(.headline)
                Text(state.status.label).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            RunElapsedTime(state: state)
        }
        .accessibilityElement(children: .combine)
    }
}
