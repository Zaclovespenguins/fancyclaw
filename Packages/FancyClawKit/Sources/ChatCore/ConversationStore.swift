import Foundation
import GatewayClient
import GatewayProtocol
import Observation
import Persistence

/// Owns the visible text transcript and reduces Gateway chat events into it.
@MainActor @Observable
public final class ConversationStore {
    public let sessionKey: String
    public let gatewayBaseURL: URL?
    public private(set) var messages: [ConversationMessage] = []
    public private(set) var isStreaming = false
    public var draftAttachments: [PreparedAttachment] = []
    public var errorMessage: String?
    public private(set) var hasMoreHistory = false
    public private(set) var isLoadingHistory = false
    public private(set) var deltaCursor: String?
    public var onRunSnapshot: ((Set<String>) -> Void)?
    private var nextOffset: Int?
    private var sessionID: String?
    private var canonicalHistory: [ChatMessage] = []
    private let cache: TranscriptCache?
    private var invalidated = false
    private var needsRefresh = false
    private var transcriptRevision = 0

    private let attachmentPipeline = AttachmentPipeline()
    private let throttle: StreamingThrottle
    private var pendingAssistantMessages: [String: ConversationMessage] = [:]
    private var lastToolSequence: [String: Int] = [:]
    private let connection: GatewayConnection
    private var eventTask: Task<Void, Never>?
    private var activeRunID: String?
    private var runIDsByIdempotencyKey: [String: String] = [:]
    private var assistantEntryIDsByRunID: [String: String] = [:]
    private var runs: [String: RunState] = [:]
    private var outbox: [String: PendingSend] = [:]
    private var isAsking = false
    private var isStarting = false
    private var inFlightKeys: Set<String> = []
    /// Keys the Gateway answered and rejected; manual retry only, never resent automatically.
    private var rejectedKeys: Set<String> = []
    private var startGeneration = 0

    private struct RunState {
        var lastSequence = -1
        var isTerminal = false
    }

    private struct PendingSend {
        let text: String
        let attachments: [PreparedAttachment]
        let messageID: String
    }

    public init(connection: GatewayConnection, sessionKey: String = SessionKey.main.rawValue, cache: TranscriptCache? = nil,
                gatewayURL: URL? = nil, timing: GatewayTiming = .continuous, streamingInterval: Duration = .milliseconds(33)) {
        throttle = StreamingThrottle(timing: timing, interval: streamingInterval)
        self.connection = connection
        gatewayBaseURL = gatewayURL.flatMap { try? ArtifactURLResolver.baseURL(for: $0) }
        self.sessionKey = sessionKey
        self.cache = cache
        do {
            if let page = try cache?.history(sessionKey) { applyPage(page) }
        } catch { errorMessage = "Couldn’t read cached history. \(error.localizedDescription)" }
    }

    /// Fetches a tail snapshot or catches up from the last durable cursor, then resends failed sends the snapshot doesn't confirm.
    public func refreshHistory() async {
        guard await loadSnapshot() else { return }
        await retryFailedSends()
    }

    /// Returns true when a snapshot was applied.
    private func loadSnapshot() async -> Bool {
        guard !invalidated else { return false }
        guard !isLoadingHistory else { needsRefresh = true; return false }
        isLoadingHistory = true
        let revision = transcriptRevision
        defer { finishLoadingHistory() }
        do {
            if let deltaCursor {
                let catchUp: ChatHistoryCatchUp = try await connection.request("chat.history",
                    params: ChatHistoryParams(sessionKey: sessionKey, cursor: deltaCursor), returning: ChatHistoryCatchUp.self)
                guard !invalidated else { return false }
                if case .delta(let delta) = catchUp {
                    let oldCount = canonicalHistory.count
                    canonicalHistory = Self.merging(canonicalHistory, with: delta.messages)
                    if let nextOffset { self.nextOffset = nextOffset + canonicalHistory.count - oldCount }
                    self.deltaCursor = delta.deltaCursor
                    reconcileHistory(canonicalHistory)
                    // A snapshot that raced live events must not overwrite the run state they established.
                    if revision == transcriptRevision { updateRunState(delta.sessionInfo) }
                    errorMessage = nil
                    try persistHistory()
                    scheduleFollowUpIfStale(since: revision)
                    return true
                }
            }
            let page: ChatHistoryPage = try await connection.request("chat.history",
                params: ChatHistoryParams(sessionKey: sessionKey, limit: 100), returning: ChatHistoryPage.self)
            guard !invalidated else { return false }
            errorMessage = nil
            applyPage(page, appliesRunState: revision == transcriptRevision)
            try persistHistory()
            scheduleFollowUpIfStale(since: revision)
            return true
        } catch { errorMessage = "Couldn’t refresh the conversation. \(error.localizedDescription)" }
        return false
    }

    /// Reconcile preserves streaming rows and unconfirmed echoes, so a snapshot that raced events is still applied.
    /// A follow-up is only worth a request once the stream is quiet; terminal events refresh on their own.
    private func scheduleFollowUpIfStale(since revision: Int) {
        if revision != transcriptRevision && !isStreaming { needsRefresh = true }
    }

    public func loadOlderHistory() async {
        guard !invalidated, hasMoreHistory, let offset = nextOffset, !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { finishLoadingHistory() }
        do {
            let page: ChatHistoryPage = try await connection.request("chat.history",
                params: ChatHistoryParams(sessionKey: sessionKey, limit: 100, offset: offset), returning: ChatHistoryPage.self)
            guard !invalidated else { return }
            errorMessage = nil
            // A reset during pagination invalidates the page and its offsets.
            if let old = sessionID, let new = page.sessionId, old != new {
                deltaCursor = nil
                hasMoreHistory = false
                nextOffset = nil
                needsRefresh = true
                return
            } else {
                canonicalHistory = Self.merging(page.messages, with: canonicalHistory)
                reconcileHistory(canonicalHistory)
                hasMoreHistory = page.hasMore == true && page.nextOffset != offset && page.nextOffset != nil
                nextOffset = page.nextOffset
                // An older page must never roll the catch-up cursor backwards.
            }
            try persistHistory()
        } catch { errorMessage = "Couldn’t load older messages. \(error.localizedDescription)" }
    }

    private func finishLoadingHistory() {
        isLoadingHistory = false
        if needsRefresh && !invalidated {
            needsRefresh = false
            Task { [weak self] in await self?.refreshHistory() }
        }
    }

    private func applyPage(_ page: ChatHistoryPage, appliesRunState: Bool = true) {
        if let old = sessionID, let new = page.sessionId, old != new {
            throttle.cancel()
            pendingAssistantMessages.removeAll()
            lastToolSequence.removeAll()
            messages = []
            outbox.removeAll()
            rejectedKeys.removeAll()
            runs.removeAll()
            runIDsByIdempotencyKey.removeAll()
            assistantEntryIDsByRunID.removeAll()
            activeRunID = nil
            isStreaming = false
        }
        sessionID = page.sessionId
        deltaCursor = page.deltaCursor
        hasMoreHistory = page.hasMore == true && page.nextOffset != nil
        nextOffset = page.nextOffset
        reconcileHistory(page.messages)
        if appliesRunState { updateRunState(page.sessionInfo) }
    }

    private func updateRunState(_ info: ChatSessionInfo?) {
        guard let info else { return }
        if let ids = info.activeRunIds { onRunSnapshot?(Set(ids)) }
        else if info.hasActiveRun == false { onRunSnapshot?([]) }
        isStreaming = info.hasActiveRun == true
        activeRunID = info.activeRunIds?.first
        if !isStreaming {
            for index in messages.indices { messages[index].isStreaming = false }
        }
    }

    private func persistHistory() throws {
        try cache?.saveHistory(ChatHistoryPage(sessionKey: sessionKey, sessionId: sessionID,
            messages: canonicalHistory, hasMore: hasMoreHistory, nextOffset: nextOffset, deltaCursor: deltaCursor))
    }

    private static func merging(_ initial: [ChatMessage], with updates: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var positions: [String: Int] = [:]
        for message in initial + updates {
            if let index = positions[message.historyIdentity] { result[index] = message }
            else { positions[message.historyIdentity] = result.count; result.append(message) }
        }
        return result
    }

    /// Registers for Gateway events and consumes them until cancelled.
    public func start() async {
        // `events()` suspends, so claim the slot first or concurrent callers each leak a subscription.
        guard eventTask == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let generation = startGeneration
        let stream = await connection.events()
        // A stop or invalidation during the await cancels this start.
        guard eventTask == nil, generation == startGeneration else { return }
        eventTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { return }
                self?.receive(frame)
            }
        }
    }

    public func invalidate() {
        invalidated = true
        draftAttachments.removeAll()
        stopListening()
    }

    public func stopListening() {
        startGeneration += 1
        flushStreaming()
        throttle.cancel()
        eventTask?.cancel()
        eventTask = nil
    }

    /// Marks the active run as uncertain after a transport loss while keeping its idempotent outbox entry.
    public func connectionDidDisconnect() {
        flushStreaming()
        throttle.cancel()
        interruptTools()
        if isStreaming { errorMessage = "Connection lost. Your message will remain here while the Gateway reconnects." }
        isStreaming = false
        activeRunID = nil
    }

    /// Adds an optimistic user message, then submits it with a stable retry key.
    /// The result means "accepted into the transcript", not "delivered": a failed `chat.send` still returns true
    /// so the composer clears, and the row is flagged `deliveryFailed` for `retry`/`retryFailedSends`.
    @discardableResult
    public func send(_ text: String, attachments: [PreparedAttachment] = []) async -> Bool {
        await submit(text, attachments: attachments, idempotencyKey: UUID().uuidString)
    }

    /// A foreground Shortcut sends through the same outbox and waits only for its own run.
    /// Subscribe before sending so a final that precedes the acknowledgment stays buffered.
    public func ask(_ text: String, timeout: Duration = .seconds(25), timing: GatewayTiming = .continuous) async throws -> String {
        guard !invalidated else { throw ChatActionError.unavailable }
        guard !isStreaming, !isAsking else { throw ChatActionError.busy }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatActionError.emptyMessage }
        isAsking = true
        defer { isAsking = false }
        let events = await connection.events()
        let key = UUID().uuidString
        guard await submit(text, attachments: [], idempotencyKey: key),
              let runID = runIDsByIdempotencyKey[key] else {
            throw ChatActionError.failed(errorMessage ?? "Couldn’t send the message.")
        }
        let sessionKey = sessionKey
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var text = ""
                var sequence = -1
                for await frame in events {
                    try Task.checkCancellation()
                    guard case .chat(let event) = frame.event, event.sessionKey == sessionKey,
                          event.runId == runID || event.runId == key, event.seq > sequence else { continue }
                    sequence = event.seq
                    switch event.state {
                    case .delta(let delta):
                        if let message = delta.message { text = ConversationMessage.markdown(from: message) }
                        else if delta.isReplacement { text = delta.deltaText }
                        else { text += delta.deltaText }
                    case .final(let final):
                        if final.yielded == true {
                            if let message = final.message { text = ConversationMessage.markdown(from: message) }
                            continue
                        }
                        return final.message.map(ConversationMessage.markdown(from:)) ?? text
                    case .aborted: throw ChatActionError.aborted
                    case .error(let failure): throw ChatActionError.failed(failure.errorMessage ?? "The reply failed.")
                    default: break
                    }
                }
                throw ChatActionError.unavailable
            }
            group.addTask {
                try await timing.sleep(timeout)
                try Task.checkCancellation()
                return "Your message was sent. Continue in FancyClaw to check the reply."
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw ChatActionError.unavailable }
            return result.isEmpty ? "The reply finished. Open FancyClaw to view its content." : result
        }
    }

    public func attachmentLimits() async -> HelloOK.AttachmentLimits? {
        await connection.policy?.attachments
    }

    /// Retries a failed outbox entry using the same idempotency key.
    public func retry(idempotencyKey: String) async {
        guard let pending = outbox[idempotencyKey], !inFlightKeys.contains(idempotencyKey) else { return }
        await submit(pending.text, attachments: pending.attachments, idempotencyKey: idempotencyKey, existingMessageID: pending.messageID)
    }

    /// Resubmits every failed outbox entry in transcript order; same-key resends are idempotent on the Gateway.
    public func retryFailedSends() async {
        let keys = messages.filter(\.deliveryFailed).compactMap { row in
            outbox.first(where: { $0.value.messageID == row.id })?.key
        }.filter { !rejectedKeys.contains($0) }
        for key in keys { await retry(idempotencyKey: key) }
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
        flushStreaming()
        canonicalHistory = Self.merging([], with: history)
        var canonical: [ConversationMessage] = []
        var confirmedKeys: Set<String> = []
        for message in canonicalHistory {
            let role: MessageRole
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .toolResult:
                if let callID = message.toolCallId {
                    for row in canonical.indices {
                        if let index = canonical[row].tools.firstIndex(where: { $0.id == callID }) {
                            canonical[row].tools[index].result = .string(ConversationMessage.markdown(from: message))
                            canonical[row].tools[index].status = message.isError == true ? .error : .success
                        }
                    }
                }
                continue
            default: continue
            }
            if role == .assistant, let runID = message.metadata?.runId, let entryID = message.entryId {
                adoptAssistantEntryID(entryID, for: runID)
            }
            var id = message.historyIdentity
            // A run-keyed assistant without an entry ID is the row already streaming for that run.
            if role == .assistant, message.entryId == nil, let runID = message.metadata?.runId,
               message.toolCallId?.isEmpty ?? true {
                let liveID = assistantMessageID(for: runID)
                if messages.contains(where: { $0.id == liveID }) && !canonical.contains(where: { $0.id == liveID }) { id = liveID }
            }
            if let key = message.idempotencyKey { confirmedKeys.insert(key) }
            let currentStreaming = messages.first(where: { $0.id == id || $0.id == assistantMessageID(for: message.metadata?.runId ?? "") })
            canonical.append(ConversationMessage(
                id: id, role: role, text: Self.visibleText(message),
                isStreaming: currentStreaming?.isStreaming ?? false,
                images: ConversationMessage.images(from: message),
                files: ConversationMessage.files(from: message),
                tools: Self.historyTools(message, current: currentStreaming?.tools ?? [])
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
        for key in confirmedKeys { outbox.removeValue(forKey: key); rejectedKeys.remove(key) }
    }

    /// Public for deterministic reducer tests and callers that already own an event stream.
    public func receive(_ frame: GatewayEventFrame) {
        guard !invalidated else { return }
        if case .agent(let event) = frame.event { receiveTool(event); return }
        guard case .chat(let event) = frame.event,
              event.sessionKey == sessionKey,
              !event.runId.isEmpty else { return }

        var run = runs[event.runId, default: RunState()]
        guard !run.isTerminal, event.seq > run.lastSequence else { return }
        run.lastSequence = event.seq
        transcriptRevision += 1

        switch event.state {
        case .status:
            activeRunID = event.runId
            isStreaming = true
        case .delta(let delta):
            activeRunID = event.runId
            isStreaming = true
            errorMessage = nil
            if let entryID = delta.message?.entryId { adoptAssistantEntryID(entryID, for: event.runId) }
            let id = assistantMessageID(for: event.runId)
            var row = pendingAssistantMessages[event.runId]
                ?? messages.first(where: { $0.id == id })
                ?? ConversationMessage(id: id, role: .assistant, text: "")
            row.id = id
            let text = delta.message.map(Self.visibleText) ?? delta.deltaText
            if delta.message != nil || delta.isReplacement { row.text = text }
            else { row.text += text }
            if let message = delta.message {
                row.images = ConversationMessage.images(from: message)
                row.tools = Self.historyTools(message, current: row.tools)
            }
            row.isStreaming = true
            pendingAssistantMessages[event.runId] = row
            throttle.schedule { [weak self] in self?.flushStreaming() }
        case .final(let final) where final.yielded == true:
            // The run continues (for example a tool handoff); show the yielded text and wait for the real final.
            activeRunID = event.runId
            isStreaming = true
            if let message = final.message, message.role == .assistant {
                if let entryID = message.entryId { adoptAssistantEntryID(entryID, for: event.runId) }
                flushStreaming()
                let id = assistantMessageID(for: event.runId)
                var row = messages.first(where: { $0.id == id }) ?? ConversationMessage(id: id, role: .assistant, text: "")
                row.text = Self.visibleText(message)
                row.images = ConversationMessage.images(from: message)
                row.files = ConversationMessage.files(from: message)
                row.tools = Self.historyTools(message, current: row.tools)
                row.isStreaming = true
                if let index = messages.firstIndex(where: { $0.id == id }) { messages[index] = row } else { messages.append(row) }
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
        if run.isTerminal, cache != nil {
            Task { [weak self] in await self?.refreshHistory() }
        }
    }

    @discardableResult
    private func submit(_ text: String, attachments: [PreparedAttachment], idempotencyKey: String, existingMessageID: String? = nil) async -> Bool {
        guard !invalidated, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return false }
        let params = ChatSendParams(sessionKey: sessionKey, message: text, idempotencyKey: idempotencyKey,
                                    attachments: attachments.isEmpty ? nil : attachments.map(\.payload))
        let policy = await connection.policy
        guard !invalidated else { return false }
        do { try await attachmentPipeline.validateSubmission(attachments, params: params, policy: policy) }
        catch { errorMessage = error.localizedDescription; return false }
        guard !invalidated, inFlightKeys.insert(idempotencyKey).inserted else { return false }
        defer { inFlightKeys.remove(idempotencyKey) }
        transcriptRevision += 1
        let messageID = existingMessageID ?? "\(idempotencyKey):user"
        if existingMessageID == nil {
            messages.append(ConversationMessage(id: messageID, role: .user, text: text, attachments: attachments))
        } else { setDeliveryFailed(false, messageID: messageID) }
        outbox[idempotencyKey] = PendingSend(text: text, attachments: attachments, messageID: messageID)
        errorMessage = nil
        isStreaming = true
        activeRunID = runIDsByIdempotencyKey[idempotencyKey] ?? idempotencyKey

        do {
            let response: ChatSendResponse = try await connection.request(
                "chat.send",
                params: params,
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
            if error is GatewayErrorShape { rejectedKeys.insert(idempotencyKey) } else { rejectedKeys.remove(idempotencyKey) }
            setDeliveryFailed(true, messageID: messageID)
            isStreaming = false
            if activeRunID == idempotencyKey { activeRunID = nil }
        }
        return true
    }

    private func setDeliveryFailed(_ failed: Bool, messageID: String) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) { messages[index].deliveryFailed = failed }
    }

    func adopt(_ response: ChatSendResponse, idempotencyKey: String) {
        let previousRunID = runIDsByIdempotencyKey[idempotencyKey] ?? idempotencyKey
        runIDsByIdempotencyKey[idempotencyKey] = response.runId
        if response.runId != previousRunID {
            flushStreaming()
            let oldAssistantID = assistantMessageID(for: previousRunID)
            if let entryID = assistantEntryIDsByRunID.removeValue(forKey: previousRunID) {
                assistantEntryIDsByRunID[response.runId] = entryID
            }
            if let sequence = lastToolSequence.removeValue(forKey: previousRunID) {
                lastToolSequence[response.runId] = max(sequence, lastToolSequence[response.runId, default: -1])
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
        flushStreaming()
        interruptTools(runID: runID)
        if let entryID = message?.entryId, message?.role == .assistant {
            adoptAssistantEntryID(entryID, for: runID)
        }
        if let message, message.role == .assistant {
            let id = message.entryId ?? assistantMessageID(for: runID)
            let text = Self.visibleText(message)
            if let index = messages.firstIndex(where: { $0.id == id || $0.id == assistantMessageID(for: runID) }) {
                messages[index].text = text
                messages[index].images = ConversationMessage.images(from: message)
                messages[index].files = ConversationMessage.files(from: message)
                messages[index].tools = Self.historyTools(message, current: messages[index].tools)
                messages[index].isStreaming = false
                if messages[index].id != id { messages[index].id = id }
            } else {
                messages.append(ConversationMessage(id: id, role: .assistant, text: text,
                    images: ConversationMessage.images(from: message),
                    files: ConversationMessage.files(from: message), tools: Self.historyTools(message, current: [])))
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
        ConversationMessage.markdown(from: message)
    }

    public func imageData(_ media: ContentBlock.Media) async throws -> Data {
        try await connection.imageData(sessionKey: sessionKey, media: media)
    }

    private func flushStreaming() {
        for (runID, var row) in pendingAssistantMessages {
            row.id = assistantMessageID(for: runID)
            if let index = messages.firstIndex(where: { $0.id == row.id }) { messages[index] = row }
            else { messages.append(row) }
        }
        pendingAssistantMessages.removeAll()
    }

    private static func historyTools(_ message: ChatMessage, current: [ConversationTool]) -> [ConversationTool] {
        var tools = current
        for block in message.content {
            guard case .toolCall(let call) = block, let id = call.id else { continue }
            if let index = tools.firstIndex(where: { $0.id == id }) {
                tools[index].name = call.name ?? tools[index].name
                tools[index].arguments = call.arguments ?? tools[index].arguments
            } else {
                tools.append(ConversationTool(id: id, name: call.name ?? "Tool", arguments: call.arguments,
                    status: .interrupted))
            }
        }
        return tools
    }

    private func receiveTool(_ event: AgentEvent) {
        guard event.stream == "tool", !event.runId.isEmpty,
              event.sessionKey == sessionKey || (event.sessionKey == nil && runs[event.runId] != nil),
              let phase = event.data["phase"]?.stringValue,
              ["start", "update", "result"].contains(phase),
              let callID = event.data["toolCallId"]?.stringValue,
              event.seq > lastToolSequence[event.runId, default: -1] else { return }
        lastToolSequence[event.runId] = event.seq
        transcriptRevision += 1
        let id = assistantMessageID(for: event.runId)
        var row = pendingAssistantMessages[event.runId]
            ?? messages.first(where: { $0.id == id })
            ?? ConversationMessage(id: id, role: .assistant, text: "")
        let index = row.tools.firstIndex(where: { $0.id == callID })
        var tool = index.map { row.tools[$0] }
            ?? ConversationTool(id: callID, name: event.data["name"]?.stringValue ?? "Tool")
        guard tool.status != .success && tool.status != .error else { return }
        tool.name = event.data["name"]?.stringValue ?? tool.name
        if phase == "start" { tool.arguments = event.data["args"] }
        if phase == "update" { tool.result = event.data["partialResult"] }
        if phase == "result" {
            tool.result = event.data["result"] ?? event.data["toolErrorSummary"]
            tool.status = event.data["isError"]?.boolValue == true ? .error : .success
        } else {
            tool.status = runs[event.runId]?.isTerminal == true ? .interrupted : .running
        }
        if let index { row.tools[index] = tool } else { row.tools.append(tool) }
        // Tool status changes are infrequent and publish immediately, including buffered text.
        pendingAssistantMessages[event.runId] = row
        flushStreaming()
    }

    private func interruptTools(runID: String? = nil) {
        let messageID = runID.map { assistantMessageID(for: $0) }
        for index in messages.indices where messageID == nil || messages[index].id == messageID {
            for tool in messages[index].tools.indices where messages[index].tools[tool].status == .running {
                messages[index].tools[tool].status = .interrupted
            }
        }
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
