import Foundation
import GatewayProtocol

/// The collapsed tool summary shown on an assistant message. The Gateway sends no summary, so the client builds it.
public struct ToolSummary: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, failed, done }
    public var text: String
    public var state: State

    /// One tool shows its name and status ("Ran read_file"); several show a count ("Used 3 tools").
    /// Returns nil when there are no tools.
    public static func make(for tools: [ConversationTool]) -> ToolSummary? {
        guard !tools.isEmpty else { return nil }
        let running = tools.filter { $0.status == .running }.count
        let failed = tools.filter { $0.status == .error }.count
        let state: State = running > 0 ? .running : failed > 0 ? .failed : .done
        if tools.count == 1, let tool = tools.first {
            let text = switch tool.status {
            case .running: "Running \(tool.name)"
            case .success: "Ran \(tool.name)"
            case .error: "\(tool.name) failed"
            case .interrupted: "\(tool.name) ended"
            }
            return ToolSummary(text: text, state: state)
        }
        var text = running > 0 ? "Using \(tools.count) tools" : "Used \(tools.count) tools"
        if running > 0 { text += " · \(running) running" }
        if failed > 0 { text += " · \(failed) failed" }
        return ToolSummary(text: text, state: state)
    }
}

public extension ConversationApproval {
    /// The card title: the command preview, else the warning text, else "Run a command".
    var displayTitle: String {
        if let preview = request.request.commandPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview
        }
        if let warning = request.request.warningText?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
            return warning
        }
        return "Run a command"
    }

    /// The one-line receipt once the approval is no longer pending, or nil while it still needs a decision.
    var receipt: String? {
        let command = request.request.command
        switch status {
        case .pending, .resolving: return nil
        case .resolved(.allowOnce): return "Approved · \(command)"
        case .resolved(.allowAlways): return "Always allowed · \(command)"
        case .resolved(.deny): return "Denied · \(command)"
        case .resolved(.unknown): return "Handled by the Gateway · \(command)"
        case .alreadyHandled: return "Handled elsewhere · \(command)"
        case .expired: return "Expired · \(command)"
        }
    }
}

public extension ContentBlock.Media {
    /// "size · TYPE" for a file card, omitting whatever is unknown.
    var fileDetail: String {
        var parts: [String] = []
        if let sizeBytes { parts.append(Int64(sizeBytes).formatted(.byteCount(style: .file))) }
        if let type = fileTypeLabel { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    /// The uppercased file extension, else the MIME subtype.
    var fileTypeLabel: String? {
        if let name = fileName, let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let ext = name[name.index(after: dot)...]
            if !ext.isEmpty, ext.count <= 6 { return ext.uppercased() }
        }
        if let subtype = mimeType?.split(separator: "/").last?.split(separator: "+").first, !subtype.isEmpty {
            return subtype.uppercased()
        }
        return nil
    }

    /// A file name that is safe to use for a temporary download: no path components, no control characters.
    var safeFileName: String {
        let raw = (fileName ?? "").replacingOccurrences(of: "\\", with: "/")
        let last = raw.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        let cleaned = String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." { return "Download" }
        return cleaned
    }
}
