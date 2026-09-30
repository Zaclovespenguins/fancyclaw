import Foundation
import GatewayClient
import GatewayProtocol
import Observation

/// Owns the visible text transcript and reduces Gateway chat events into it.
@MainActor @Observable
public final class ConversationStore {
    public let sessionKey: String
    public private(set) var messages: [ConversationMessage] = []
    public private(set) var isStreaming = false
    public var errorMessage: String?

    private let connection: GatewayConnection
    private var eventTask: Task<Void, Never>?
    private var activeRunID: String?
    private var runIDsByIdempotencyKey: [String: String] = [:]
    private var assistantEntryIDsByRunID: [String: String] = [:]
    private var runs: [String: RunState] = [:]
    private var outbox: [String: PendingSend] = [:]

    private struct RunState {
        var lastSequence = -1
        var isTerminal = false
    }

    private struct PendingSend {
        let text: String
        let messageID: String
    }

    public init(connection: GatewayConnection, sessionKey: String = SessionKey.main.rawValue) {
        self.connection = connection
        self.sessionKey = sessionKey
    }

    /// Registers for Gateway events and consumes them until cancelled.
    public func start() async {
        guard eventTask == nil else { return }
        let stream = await connection.events()
        eventTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { return }
                self?.receive(frame)
            }
        }
    }

    public func stopListening() {
        eventTask?.cancel()
        eventTask = nil
    }

    /// Marks the active run as uncertain after a transport loss while keeping its idempotent outbox entry.
    public func connectionDidDisconnect() {
        if isStreaming { errorMessage = "Connection lost. Your message will remain here while the Gateway reconnects." }
        isStreaming = false
        activeRunID = nil
    }

    /// Adds an optimistic user message, then submits it with a stable retry key.
    public func send(_ text: String) async {
        await submit(text, idempotencyKey: UUID().uuidString)
    }

    /// Retries a failed outbox entry using the same idempotency key.
    public func retry(idempotencyKey: String) async {
        guard let pending = outbox[idempotencyKey] else { return }
        await submit(pending.text, idempotencyKey: idempotencyKey, existingMessageID: pending.messageID)
    }

    public func abort() async {
        guard isStreaming else { return }
        do {
            let _: JSONValue = try await connection.request(
                "chat.abort", params: ChatAbortParams(sessionKey: sessionKey, runId: activeRunID),
                returning: JSONValue.self
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reconciles the visible transcript with a Gateway history snapshot while retaining unconfirmed echoes.
    public func reconcileHistory(_ history: [ChatMessage]) {
        var canonical: [ConversationMessage] = []
        var confirmedKeys: Set<String> = []
        for message in history {
            let role: MessageRole
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            default: continue
            }
            if role == .assistant, let runID = message.metadata?.runId, let entryID = message.entryId {
                adoptAssistantEntryID(entryID, for: runID)
            }
            let id = message.entryId
                ?? message.idempotencyKey.map { "\($0):user" }
                ?? "history:\(message.metadata?.runId ?? "unknown"):\(canonical.count)"
            if let key = message.idempotencyKey { confirmedKeys.insert(key) }
            let currentStreaming = messages.first(where: { $0.id == id || $0.id == assistantMessageID(for: message.metadata?.runId ?? "") })
            canonical.append(ConversationMessage(
                id: id, role: role, text: Self.visibleText(message),
                isStreaming: currentStreaming?.isStreaming ?? false
            ))
        }
        for (key, pending) in outbox where !confirmedKeys.contains(key) {
            if !canonical.contains(where: { $0.id == pending.messageID }) {
                if let optimistic = messages.first(where: { $0.id == pending.messageID }) { canonical.append(optimistic) }
            }
        }
        // Preserve a streamed assistant that has not appeared in the latest history page yet.
        for message in messages where message.role == .assistant && message.isStreaming
            && !canonical.contains(where: { $0.id == message.id }) {
            canonical.append(message)
        }
        messages = canonical
        for key in confirmedKeys { outbox.removeValue(forKey: key) }
    }

    /// Public for deterministic reducer tests and callers that already own an event stream.
    public func receive(_ frame: GatewayEventFrame) {
        guard case .chat(let event) = frame.event,
              event.sessionKey == sessionKey,
              !event.runId.isEmpty else { return }

        var run = runs[event.runId, default: RunState()]
        guard !run.isTerminal, event.seq > run.lastSequence else { return }
        run.lastSequence = event.seq

        switch event.state {
        case .status:
            activeRunID = event.runId
            isStreaming = true
        case .delta(let delta):
            activeRunID = event.runId
            isStreaming = true
            errorMessage = nil
            if let entryID = delta.message?.entryId { adoptAssistantEntryID(entryID, for: event.runId) }
            let text = delta.message.map(Self.visibleText) ?? delta.deltaText
            let id = assistantMessageID(for: event.runId)
            if let index = messages.firstIndex(where: { $0.id == id }) {
                if delta.message != nil || delta.isReplacement {
                    messages[index].text = text
                } else {
                    messages[index].text += text
                }
                messages[index].isStreaming = true
            } else {
                messages.append(ConversationMessage(id: id, role: .assistant, text: text, isStreaming: true))
            }
        case .final(let final):
            settle(event.runId, message: final.message, error: nil)
            run.isTerminal = true
        case .aborted(let aborted):
            settle(event.runId, message: aborted.message, error: nil)
            run.isTerminal = true
        case .error(let failure):
            let copy = Self.errorCopy(kind: failure.errorKind, message: failure.errorMessage)
            settle(event.runId, message: failure.message, error: copy)
            run.isTerminal = true
        case .unknown:
            break
        }
        runs[event.runId] = run
    }

    private func submit(_ text: String, idempotencyKey: String, existingMessageID: String? = nil) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let messageID = existingMessageID ?? "\(idempotencyKey):user"
        if existingMessageID == nil {
            messages.append(ConversationMessage(id: messageID, role: .user, text: text))
        }
        outbox[idempotencyKey] = PendingSend(text: text, messageID: messageID)
        errorMessage = nil
        isStreaming = true
        activeRunID = runIDsByIdempotencyKey[idempotencyKey] ?? idempotencyKey

        do {
            let response: ChatSendResponse = try await connection.request(
                "chat.send",
                params: ChatSendParams(sessionKey: sessionKey, message: text, idempotencyKey: idempotencyKey),
                returning: ChatSendResponse.self
            )
            adopt(response, idempotencyKey: idempotencyKey)
            if response.status == .ok && runs[response.runId]?.isTerminal != true {
                var state = runs[response.runId, default: RunState()]
                state.isTerminal = true
                runs[response.runId] = state
                if activeRunID == response.runId { isStreaming = false; activeRunID = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
            isStreaming = false
            if activeRunID == idempotencyKey { activeRunID = nil }
        }
    }

    func adopt(_ response: ChatSendResponse, idempotencyKey: String) {
        let previousRunID = runIDsByIdempotencyKey[idempotencyKey] ?? idempotencyKey
        runIDsByIdempotencyKey[idempotencyKey] = response.runId
        if response.runId != previousRunID {
            let oldAssistantID = assistantMessageID(for: previousRunID)
            if let entryID = assistantEntryIDsByRunID.removeValue(forKey: previousRunID) {
                assistantEntryIDsByRunID[response.runId] = entryID
            }
            if let state = runs.removeValue(forKey: previousRunID) {
                runs[response.runId] = merge(state, with: runs[response.runId])
            }
            if activeRunID == previousRunID { activeRunID = response.runId }
            if let index = messages.firstIndex(where: { $0.id == oldAssistantID }) {
                messages[index].id = assistantMessageID(for: response.runId)
            }
        }
        if runs[response.runId]?.isTerminal == true, activeRunID == response.runId {
            isStreaming = false
            activeRunID = nil
        }
    }

    private func settle(_ runID: String, message: ChatMessage?, error: String?) {
        if let entryID = message?.entryId, message?.role == .assistant {
            adoptAssistantEntryID(entryID, for: runID)
        }
        if let message, message.role == .assistant {
            let id = message.entryId ?? assistantMessageID(for: runID)
            let text = Self.visibleText(message)
            if let index = messages.firstIndex(where: { $0.id == id || $0.id == assistantMessageID(for: runID) }) {
                messages[index].text = text
                messages[index].isStreaming = false
                if messages[index].id != id { messages[index].id = id }
            } else {
                messages.append(ConversationMessage(id: id, role: .assistant, text: text))
            }
        } else if let index = messages.firstIndex(where: { $0.id == assistantMessageID(for: runID) }) {
            messages[index].isStreaming = false
        }
        if activeRunID == runID || activeRunID == nil {
            isStreaming = false
            activeRunID = nil
        }
        errorMessage = error
    }

    private func assistantMessageID(for runID: String) -> String {
        assistantEntryIDsByRunID[runID] ?? "\(runID):assistant"
    }

    private func adoptAssistantEntryID(_ entryID: String, for runID: String) {
        let fallbackID = "\(runID):assistant"
        assistantEntryIDsByRunID[runID] = entryID
        if let index = messages.firstIndex(where: { $0.id == fallbackID }) {
            messages[index].id = entryID
        }
    }

    private static func visibleText(_ message: ChatMessage) -> String {
        message.content.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined()
    }

    private static func errorCopy(kind: ChatErrorKind?, message: String?) -> String {
        switch kind {
        case .refusal: "The assistant couldn’t help with that request."
        case .timeout: "The request timed out. Try again."
        case .rateLimit: "The service is busy. Try again in a moment."
        case .contextLength: "This conversation is too long for the selected model. Start a new chat or shorten your message."
        case .unclassified, .unknown, nil: message ?? "The assistant couldn’t complete the request."
        }
    }

    private func merge(_ state: RunState, with other: RunState?) -> RunState {
        guard let other else { return state }
        return RunState(lastSequence: max(state.lastSequence, other.lastSequence),
                        isTerminal: state.isTerminal || other.isTerminal)
    }
}
