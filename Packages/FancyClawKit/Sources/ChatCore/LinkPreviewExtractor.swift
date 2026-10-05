import Foundation
import GatewayClient

/// Detects web URLs for previews, independently of Textual's Markdown rendering.
public enum LinkPreviewExtractor {
    public static func urls(in message: ConversationMessage, gatewayBaseURL: URL? = nil) -> [URL] {
        guard message.role == .assistant, !message.isStreaming, !message.text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let text = excludingCodeAndImages(message.text)
        let media = Set((message.images + message.files).compactMap { block -> String? in
            guard let reference = block.url,
                  let url = URL(string: reference, relativeTo: gatewayBaseURL)?.absoluteURL else { return nil }
            return identity(url)
        })
        var seen: Set<String> = []
        var result: [URL] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let key = identity(url), let normalizedURL = URL(string: key),
                  !media.contains(key),
                  !url.path.contains("/api/chat/media/"), !url.path.contains("/api/artifacts/"),
                  gatewayBaseURL.map({ !ArtifactURLResolver.isSameOrigin(normalizedURL, gateway: $0) }) ?? true,
                  seen.insert(key).inserted else { continue }
            result.append(url)
            if result.count == 3 { break }
        }
        return result
    }

    private static func identity(_ url: URL) -> String? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.fragment = nil
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url?.absoluteString
    }

    /// Conservative lexical exclusions for common fenced/inline code and Markdown image destinations.
    /// Textual still owns Markdown parsing; this is not a second Markdown renderer.
    private static func excludingCodeAndImages(_ source: String) -> String {
        let text = NSMutableString(string: source)
        // Examples inside code must not claim a reference label used by a real link elsewhere.
        let codePatterns = [
            #"(?ms)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?(?:^ {0,3}\1[^\n]*(?:\n|$)|\z)"#,
            #"(?s)(`+).*?\1"#
        ]
        for pattern in codePatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)).reversed() {
                mask(match.range, in: text)
            }
        }
        let codeExcluded = text as String
        // Reference and shortcut images keep their existing Textual image handling as well.
        if let images = try? NSRegularExpression(pattern: #"!\[([^\]]*)\](?:\[([^\]]*)\])?"#),
           let definitions = try? NSRegularExpression(pattern: #"(?m)^ {0,3}\[([^\]]+)\]:[^\n]*(?:\n|$)"#) {
            let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let references = Set(images.matches(in: codeExcluded, range: NSRange(codeExcluded.startIndex..., in: codeExcluded)).compactMap { match -> String? in
                let reference = match.range(at: 2)
                let label = reference.location != NSNotFound && reference.length > 0 ? reference : match.range(at: 1)
                guard let range = Range(label, in: codeExcluded) else { return nil }
                return normalize(String(codeExcluded[range]))
            })
            for definition in definitions.matches(in: codeExcluded, range: NSRange(codeExcluded.startIndex..., in: codeExcluded)).reversed() {
                guard let range = Range(definition.range(at: 1), in: codeExcluded),
                      references.contains(normalize(String(codeExcluded[range]))) else { continue }
                mask(definition.range, in: text)
            }
        }
        if let expression = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^\n]*?\)"#) {
            for match in expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)).reversed() {
                mask(match.range, in: text)
            }
        }
        return text as String
    }

    private static func mask(_ range: NSRange, in text: NSMutableString) {
        let whitespace = text.substring(with: range).map { character in
            character.isNewline ? String(character) : String(repeating: " ", count: character.utf16.count)
        }.joined()
        text.replaceCharacters(in: range, with: whitespace)
    }
}
