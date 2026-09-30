import ChatCore
import SwiftUI

struct AttachmentTray: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let attachments: [PreparedAttachment]
    var remove: ((UUID) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 8) {
                        if let data = attachment.thumbnail, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(.rect(cornerRadius: 8))
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .frame(width: 40, height: 48)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName)
                                .foregroundStyle(Color.primary)
                                .font(.subheadline)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            Text(Int64(attachment.data.count), format: .byteCount(style: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 240 : 140, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(attachment.fileName)
                        if let remove {
                            Button { remove(attachment.id) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(attachment.fileName)")
                                .accessibilityIdentifier("attachment.remove")
                        }
                    }
                    .padding(8)
                    .background(.quaternary, in: .rect(cornerRadius: 16))
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("attachment.tray")
    }
}
