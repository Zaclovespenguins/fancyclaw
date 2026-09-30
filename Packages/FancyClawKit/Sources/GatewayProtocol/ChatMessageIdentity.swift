import Foundation

extension ChatMessage {
    /// Stable across overlapping pages, independent of the message's position in a page.
    public var historyIdentity: String {
        if let entryId { return entryId }
        if let idempotencyKey { return "\(idempotencyKey):\(role.rawValue)" }
        if let runId = metadata?.runId { return "\(runId):\(role.rawValue):\(toolCallId ?? "")" }
        // Legacy entries without Gateway IDs use their canonical encoded value.
        let encoder = GatewayCoding.encoder()
        encoder.outputFormatting.insert(.sortedKeys)
        return "legacy:" + ((try? encoder.encode(self).base64EncodedString()) ?? "")
    }
}
