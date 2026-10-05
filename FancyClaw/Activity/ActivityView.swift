import DesignSystem
import SwiftUI

struct ActivityView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case today = "Today"
        case scheduled = "Scheduled"

        var id: Self { self }

        var message: String {
            switch self {
            case .today: "A timeline of approvals, runs and replies will appear here."
            case .scheduled: "Scheduled jobs from your Gateway will appear here."
            }
        }
    }

    @Environment(\.appTheme) private var theme
    @State private var segment: Segment = .today

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Activity", selection: $segment) {
                    ForEach(Segment.allCases) { option in
                        Text(option.rawValue)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)

                ContentUnavailableView(
                    "Activity is coming soon",
                    systemImage: "waveform.path.ecg",
                    description: Text(segment.message)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            .padding(.horizontal, AppTheme.Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background { AmbientGlow() }
        .foregroundStyle(theme.textPrimary.color)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ActivityPreviewEvent {
    enum Kind: Equatable {
        case needsYou
        case running
        case done
    }

    let time: String
    let title: String
    let detail: String
    let kind: Kind
}

/// Preview-only timeline styling for the future Activity implementation. It is not connected to Gateway data.
private struct TimelineRow: View {
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 11
    let event: ActivityPreviewEvent

    private var dotColor: Color {
        switch event.kind {
        case .needsYou: theme.accent.color
        case .running: theme.online.color
        case .done: theme.textTertiary.color
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(event.time)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary.color)
                .frame(width: timeColumnWidth, alignment: .leading)
                .padding(.top, 14)

            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .background(Circle().stroke(theme.bg.color, lineWidth: 6))
                .shadow(color: dotColor, radius: 5)
                .frame(width: 24)
                .padding(.top, 17)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary.color)
                Text(event.detail)
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .glass(in: RoundedRectangle(cornerRadius: AppTheme.Radius.timelineCard, style: .continuous))
            .overlay {
                if event.kind == .needsYou {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.timelineCard, style: .continuous)
                        .stroke(theme.accent.color.opacity(0.45), lineWidth: 0.5)
                }
            }
        }
    }
}

#Preview("Activity") {
    NavigationStack { ActivityView() }
}

#Preview("Timeline row") {
    TimelineRow(event: ActivityPreviewEvent(time: "9:41 AM", title: "Build needs approval",
                                            detail: "Waiting for your review", kind: .needsYou))
        .padding()
}
