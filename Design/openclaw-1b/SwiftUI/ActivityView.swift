import SwiftUI

struct ActivityView: View {
    enum Segment: String, CaseIterable { case today = "Today", scheduled = "Scheduled" }
    @State private var segment: Segment = .today

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    ForEach(MockData.activity) { TimelineRow(event: $0) }
                }
                .background(alignment: .leading) {
                    LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                        .frame(width: 1.5)
                        .padding(.leading, 55).padding(.top, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(AmbientGlow())
        .navigationTitle("Activity")
        .refreshable { }
    }
}

struct TimelineRow: View {
    let event: ActivityEvent

    private var dot: Color {
        switch event.kind {
        case .needsYou: Theme.accent
        case .running: Theme.online
        case .done: .white.opacity(0.3)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(event.time)
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 44, alignment: .leading).padding(.top, 14)
            Circle().fill(dot).frame(width: 11, height: 11)
                .background(Circle().stroke(Theme.bg, lineWidth: 6))
                .shadow(color: dot, radius: 5)
                .frame(width: 24).padding(.top, 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 15, weight: .semibold))
                Text(event.detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11).padding(.horizontal, 14)
            .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if event.kind == .needsYou {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.accent.opacity(0.45), lineWidth: 0.5)
                }
            }
        }
    }
}

#Preview { NavigationStack { ActivityView() }.preferredColorScheme(.dark) }
