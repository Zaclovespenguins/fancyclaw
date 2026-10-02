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
    @State private var isDownloading = false
    @State private var errorText: String?
    @State private var previewURL: URL?
    @State private var failureCount = 0

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
                let detail = errorText ?? media.fileDetail
                if !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(errorText == nil ? theme.textSecondary.color : theme.danger.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if canDownload {
                Button(action: download) {
                    Group {
                        if isDownloading {
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
                .disabled(isDownloading)
                .accessibilityLabel("Download \(name)")
                .accessibilityIdentifier("chat.file.download")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .surface(in: .rect(cornerRadius: 20), opacity: 0.07)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.file.\(name)")
        .sensoryFeedback(.error, trigger: failureCount) { _, _ in hapticsEnabled }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            // Nothing is kept once the preview closes.
            if new == nil, let old { TemporaryDownload.remove(old) }
        }
        .onDisappear { if let previewURL { TemporaryDownload.remove(previewURL) } }
    }

    private func download() {
        guard !isDownloading else { return }
        isDownloading = true
        errorText = nil
        Task {
            defer { isDownloading = false }
            do {
                let data = try await load(media)
                previewURL = try TemporaryDownload.write(data, named: media.safeFileName)
            } catch is CancellationError {
            } catch {
                errorText = "Download failed. Try again."
                failureCount += 1
            }
        }
    }
}

/// Temporary download files, each in its own directory so the whole directory can be removed afterwards.
private enum TemporaryDownload {
    static func write(_ data: Data, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "chat-download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        do { try data.write(to: url, options: [.completeFileProtection]) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
