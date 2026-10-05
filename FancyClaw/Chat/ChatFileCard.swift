import ChatCore
import DesignSystem
import GatewayProtocol
import QuickLook
import SwiftUI

/// A file the assistant produced: glyph, name, "size · type", and a download button.
/// Downloading writes a temporary file for Quick Look and removes it when the preview closes.
struct ChatFileCard: View {
    let media: ContentBlock.Media
    let load: @Sendable (ContentBlock.Media) async throws -> Data

    @Environment(\.appTheme) private var theme
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var download = TemporaryMediaDownload()

    private var canDownload: Bool { media.url != nil || media.artifactId != nil }
    private var name: String { media.fileName ?? "Attachment" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(theme.accentText.color)
                .frame(width: 34, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                let detail = download.errorMessage ?? media.fileDetail
                if !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(download.errorMessage == nil ? theme.textSecondary.color : theme.danger.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canDownload {
                Button { download.start(media: media, load: load) } label: {
                    Group {
                        if download.isDownloading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.textPrimary.color)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .surface(in: .circle, opacity: 0.08)
                    .contentShape(.circle)
                }
                .buttonStyle(PressScale())
                .disabled(download.isDownloading)
                .accessibilityLabel("Download \(name)")
                .accessibilityIdentifier("chat.file.download")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .surface(in: .rect(cornerRadius: 20), opacity: 0.07)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.file.\(name)")
        .sensoryFeedback(.error, trigger: download.failureCount) { _, _ in hapticsEnabled }
        .quickLookPreview($download.previewURL)
        .onDisappear { download.cancel() }
    }
}
