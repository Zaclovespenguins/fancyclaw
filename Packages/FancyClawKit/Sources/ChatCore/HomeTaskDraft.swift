import Foundation
import GatewayProtocol
import Observation

/// An ephemeral Home draft. A failed submission freezes its payload, selected agent/model, session and retry key.
@MainActor @Observable public final class HomeTaskDraft {
    public var text = ""
    public var attachments: [PreparedAttachment] = []
    /// Nil is the Gateway default: no sessions.patch is sent.
    public var selectedModelID: String?
    public var errorMessage: String?
    public private(set) var isSubmitting = false
    private var attempt: Attempt?
    private var attemptInvalidated = false
    public var hasFrozenTask: Bool { attempt != nil }
    public var pendingSessionKey: String? { attempt?.session?.key }
    public var pendingIdempotencyKey: String? { attempt?.idempotencyKey }
    public var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    private struct Attempt {
        let idempotencyKey = UUID().uuidString
        let creationKey = UUID().uuidString
        let text: String
        let attachments: [PreparedAttachment]
        let agentID: String?
        let model: ModelSummary?
        var session: SessionSummary?
        var modelConfigured = false
    }

    public init() {}

    /// The send operation must acknowledge the exact key, or throw without discarding this draft.
    @discardableResult
    public func submit(sessions: SessionStore, connected: Bool,
                       send: (SessionSummary, String, [PreparedAttachment], String) async throws -> Void,
                       open: (String) async -> Void) async -> Bool {
        guard connected, !isSubmitting, canSubmit, !Task.isCancelled else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        if attemptInvalidated {
            errorMessage = "That chat was reset or deleted. Edit this as a new task."
            return false
        }
        if attempt == nil {
            let model = selectedModelID.flatMap { id in sessions.models.first { $0.selectionID == id } }
            if selectedModelID != nil && (model == nil || model?.available == false) {
                errorMessage = "That model is unavailable. Choose another model or Gateway default."
                return false
            }
            attempt = Attempt(text: text.trimmingCharacters(in: .whitespacesAndNewlines), attachments: attachments,
                              agentID: sessions.defaultAgentID, model: model)
        }
        guard var snapshot = attempt else { return false }
        if snapshot.session == nil {
            guard let key = await sessions.create(agentID: snapshot.agentID, idempotencyKey: snapshot.creationKey),
                  let session = sessions.sessions.first(where: { $0.key == key }) else {
                errorMessage = sessions.errorMessage ?? "Couldn’t create a chat."
                return false
            }
            snapshot.session = session
            attempt = snapshot
        }
        guard let session = snapshot.session,
              let current = sessions.sessions.first(where: { $0.key == session.key }),
              current.sessionId == session.sessionId, current.archived != true else {
            errorMessage = "That chat was reset or deleted. Edit this as a new task."
            return false
        }
        if let model = snapshot.model, !snapshot.modelConfigured {
            guard !Task.isCancelled else { return false }
            guard await sessions.setModel(model, for: current) else {
                errorMessage = sessions.errorMessage ?? "Couldn’t choose the model."
                return false
            }
            snapshot.modelConfigured = true
            attempt = snapshot
        }
        do {
            try Task.checkCancellation()
            guard !attemptInvalidated else { errorMessage = "That chat was reset or deleted. Edit this as a new task."; return false }
            try await send(session, snapshot.text, snapshot.attachments, snapshot.idempotencyKey)
            try Task.checkCancellation()
            guard !attemptInvalidated else { errorMessage = "That chat was reset or deleted. Edit this as a new task."; return false }
            text = ""
            attachments = []
            attempt = nil
            await open(session.key)
            return true
        } catch is CancellationError { return false }
        catch { errorMessage = error.localizedDescription; return false }
    }

    /// Explicitly abandon the frozen retry after the person chooses to edit as a separate task.
    public func editAsNewTask() {
        guard !isSubmitting else { return }
        attempt = nil
        attemptInvalidated = false
        errorMessage = nil
    }

    /// A session event can invalidate an incarnation even when the Gateway omitted sessionId.
    public func invalidateSession(_ key: String) {
        if attempt?.session?.key == key { attemptInvalidated = true }
    }
}
