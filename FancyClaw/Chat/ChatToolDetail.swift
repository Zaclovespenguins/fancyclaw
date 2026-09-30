import SwiftUI

struct ChatToolDetail: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
