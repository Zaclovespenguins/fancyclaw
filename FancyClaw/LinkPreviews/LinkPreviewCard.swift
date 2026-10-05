import ChatCore
import DesignSystem
import SwiftUI

/// One VoiceOver link with a context menu; text reflows beside the image or below it at accessibility sizes.
struct LinkPreviewCard: View {
    let url: URL
    @Environment(\.appTheme) private var theme
    @Environment(\.linkPreviewLoader) private var loader
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var imageSize: CGFloat = 104
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 18
    @State private var presentation = LinkPreviewPresentation<LinkPreviewMetadata>()
    @State private var showingSafari = false

    private var metadata: LinkPreviewMetadata { presentation.value ?? .fallback(for: url) }

    var body: some View {
        Button { showingSafari = true } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { artwork; details }
                } else {
                    HStack(alignment: .center, spacing: 12) { artwork; details }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: AppTheme.Radius.chatCard))
            .modifier(PreviewCardSurface(reduceTransparency: reduceTransparency))
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metadata.title == metadata.domain ? metadata.domain : "\(metadata.title), \(metadata.domain)")
        .accessibilityHint("Opens in Safari. Additional actions available.")
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("chat.linkPreview.\(url.host() ?? "link")")
        .contextMenu {
            Button("Copy Link", systemImage: "doc.on.doc") { UIPasteboard.general.url = url }
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        .sheet(isPresented: $showingSafari) { SafariLinkView(url: url).ignoresSafeArea() }
        .task(id: url) {
            guard let loader else { return }
            await presentation.load { try await loader.load(url) }
        }
        .onDisappear { presentation.cancel() }
    }

    private var artwork: some View {
        Group {
            if let bytes = metadata.imageData, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    theme.accent.color.opacity(0.10)
                    Image(systemName: "globe").font(.title).foregroundStyle(theme.accentText.color)
                }
            }
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : imageSize, height: imageSize)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metadata.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text("Website").font(.caption).foregroundStyle(theme.textSecondary.color)
            HStack(spacing: 5) {
                if let bytes = metadata.iconData, let icon = UIImage(data: bytes) {
                    Image(uiImage: icon).resizable().scaledToFit().frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "link").font(.caption)
                }
                Text(metadata.domain).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.textSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreviewCardSurface: ViewModifier {
    let reduceTransparency: Bool
    @Environment(\.appTheme) private var theme

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.surface(in: .rect(cornerRadius: AppTheme.Radius.chatCard), opacity: 0.05)
        } else {
            content
                .background(theme.bg.color.opacity(0.96), in: .rect(cornerRadius: AppTheme.Radius.chatCard))
                .glass(in: .rect(cornerRadius: AppTheme.Radius.chatCard), interactive: true)
        }
    }
}
