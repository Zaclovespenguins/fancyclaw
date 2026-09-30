import Foundation
import GatewayClient
import GatewayProtocol
import os
import Testing
@testable import ChatCore

@Suite("Rich output", .serialized)
struct RichOutputTests {
    @Test func markdownMappingExcludesThinkingAndSeparatesBlocks() {
        let message = ChatMessage(role: .assistant, content: [.thinking("private"), .text("# Title"),
            .media(.init(kind: .image, url: "/image")), .text("Next paragraph"), .toolCall(.init(id: "call"))])
        #expect(ConversationMessage.markdown(from: message) == "# Title\n\nNext paragraph")
        #expect(ConversationMessage.images(from: message).map(\.url) == ["/image"])
    }

    @Test @MainActor func toolsReduceIndependentlyFromChatTextAndIgnoreOtherSessions() {
        let store = makeStore()
        store.receive(tool(1, "start", extra: ["args": ["command": "ls"]]))
        store.receive(tool(2, "update", extra: ["partialResult": "working"]))
        store.receive(tool(3, "result", extra: ["result": "done", "isError": false]))
        store.receive(tool(3, "result", extra: ["result": "duplicate", "isError": true]))
        store.receive(tool(4, "start"))
        store.receive(.init(event: .agent(.init(runId: "run", seq: 5, stream: "assistant", sessionKey: store.sessionKey,
            data: ["text": "duplicate assistant text"]))))
        store.receive(.init(event: .agent(.init(runId: "other", seq: 1, stream: "tool", sessionKey: "agent:other:main",
            data: ["phase": "start", "toolCallId": "wrong", "name": "exec"]))))
        #expect(store.messages.count == 1)
        #expect(store.messages[0].text.isEmpty)
        #expect(store.messages[0].tools == [ConversationTool(id: "call", name: "exec", arguments: ["command": "ls"],
            result: "done", status: .success)])
    }

    @Test @MainActor func resultWithoutStartAndLateResultAfterChatFinal() {
        let store = makeStore()
        store.receive(tool(1, "start"))
        store.receive(chat(1, .final(.init(message: .init(role: .assistant, content: [.text("finished")], metadata: .init(id: "entry"))))))
        #expect(store.messages[0].tools[0].status == .interrupted)
        store.receive(tool(2, "result", extra: ["result": "failed", "isError": true]))
        #expect(store.messages[0].id == "entry")
        #expect(store.messages[0].tools[0].status == .error)
        #expect(store.messages[0].tools[0].result == "failed")
        let other = makeStore()
        other.receive(tool(1, "result", extra: ["result": "complete"]))
        #expect(other.messages[0].tools[0].status == .success)
    }

    @Test @MainActor func toolProgressAfterDisconnectReturnsToRunning() {
        let store = makeStore()
        store.receive(tool(1, "start", extra: ["args": ["command": "ls"]]))
        store.connectionDidDisconnect()
        #expect(store.messages[0].tools[0].status == .interrupted)
        store.receive(tool(2, "update", extra: ["partialResult": "resumed"]))
        #expect(store.messages[0].tools[0].status == .running)
        #expect(store.messages[0].tools[0].arguments == ["command": "ls"])
        #expect(store.messages[0].tools[0].result == "resumed")
        store.receive(tool(3, "result", extra: ["result": "complete"]))
        #expect(store.messages[0].tools[0].status == .success)
    }

    @Test @MainActor func historyRestoresToolsAndMediaAndExcludesRawToolMessages() {
        let store = makeStore()
        store.reconcileHistory([
            .init(role: .assistant, content: [.toolCall(.init(id: "call", name: "exec", arguments: ["command": "ls"])),
                .media(.init(kind: .image, artifactId: "image-id")), .text("report")], metadata: .init(id: "entry")),
            .init(role: .toolResult, content: [.text("result")], toolCallId: "call", isError: true)
        ])
        #expect(store.messages.count == 1)
        #expect(store.messages[0].images.first?.artifactId == "image-id")
        #expect(store.messages[0].tools.first?.result == "result")
        #expect(store.messages[0].tools.first?.status == .error)
    }

    @Test @MainActor func clockThrottlesBurstsAndTerminalEventsFlushImmediately() async {
        let time = StreamTestClock()
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), timing: time.timing)
        store.receive(chat(1, .delta(.init(deltaText: "A"))))
        store.receive(chat(2, .delta(.init(deltaText: "B"))))
        store.receive(chat(3, .delta(.init(deltaText: "C"))))
        #expect(store.messages[0].text == "A")
        for _ in 0..<100 where !time.hasSleeper { await Task.yield() }
        time.advance(.milliseconds(32))
        await Task.yield()
        #expect(store.messages[0].text == "A")
        time.advance(.milliseconds(1))
        for _ in 0..<100 where store.messages[0].text != "ABC" { await Task.yield() }
        #expect(store.messages[0].text == "ABC")
        store.receive(chat(4, .delta(.init(deltaText: "replacement", replace: true))))
        #expect(store.messages[0].text == "ABC")
        store.receive(chat(5, .aborted(.init())))
        #expect(store.messages[0].text == "replacement")
        #expect(!store.messages[0].isStreaming)
        store.stopListening()
        time.advance(.seconds(1))
        await Task.yield()
        #expect(store.messages[0].text == "replacement")
    }

    @Test @MainActor func bufferedSnapshotKeepsImagesAndDisconnectSettlesTools() {
        let time = StreamTestClock()
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), timing: time.timing)
        store.receive(chat(1, .delta(.init(deltaText: "old"))))
        store.receive(chat(2, .delta(.init(deltaText: "", message: .init(role: .assistant,
            content: [.text("new"), .media(.init(kind: .image, url: "/image"))])))))
        store.receive(tool(1, "start"))
        store.connectionDidDisconnect()
        #expect(store.messages[0].text == "new")
        #expect(store.messages[0].images.first?.url == "/image")
        #expect(store.messages[0].tools.first?.status == .interrupted)
        store.stopListening()
    }

    @MainActor private func makeStore() -> ConversationStore {
        ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
    }
    private func chat(_ seq: Int, _ state: ChatEvent.State) -> GatewayEventFrame {
        .init(event: .chat(.init(runId: "run", sessionKey: SessionKey.main.rawValue, seq: seq, state: state)))
    }
    private func tool(_ seq: Int, _ phase: String, extra: [String: JSONValue] = [:]) -> GatewayEventFrame {
        var data: [String: JSONValue] = ["phase": .string(phase), "toolCallId": "call", "name": "exec"]
        data.merge(extra) { _, new in new }
        return .init(event: .agent(.init(runId: "run", seq: seq, stream: "tool", sessionKey: SessionKey.main.rawValue, data: .object(data))))
    }
}

private final class StreamTestClock: Sendable {
    private struct Sleeper { let deadline: Duration; let continuation: CheckedContinuation<Void, Never> }
    private struct State { var now: Duration = .zero; var sleepers: [Sleeper] = [] }
    private let storage = OSAllocatedUnfairLock(initialState: State())
    var hasSleeper: Bool { storage.withLock { !$0.sleepers.isEmpty } }
    var timing: GatewayTiming {
        GatewayTiming(now: { self.storage.withLock { $0.now } }, sleep: { delay in
            await withCheckedContinuation { continuation in
                self.storage.withLock { state in
                    state.sleepers.append(Sleeper(deadline: state.now + delay, continuation: continuation))
                }
            }
        })
    }
    func advance(_ amount: Duration) {
        let ready = storage.withLock { state in
            state.now += amount
            let ready = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return ready
        }
        for sleeper in ready { sleeper.continuation.resume() }
    }
}
