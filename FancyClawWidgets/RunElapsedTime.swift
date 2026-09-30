import SwiftUI
import SystemActions

struct RunElapsedTime: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if !state.status.isTerminal && state.status != .reconnecting {
            Text(state.startedAt, style: .timer)
                .monospacedDigit()
                .font(.caption)
                .accessibilityLabel("Elapsed time")
        } else {
            Image(systemName: state.status == .completed ? "checkmark.circle" : "pause.circle")
                .accessibilityLabel(state.status.label)
        }
    }
}
