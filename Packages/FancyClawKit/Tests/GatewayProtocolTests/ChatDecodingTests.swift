import Foundation
import GatewayProtocol
import Testing
import TestSupport

@Suite("Chat decoding")
struct ChatDecodingTests {
    private func chatEvent(_ fixture: String) throws -> ChatEvent {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: fixture)
        guard case .chat(let event) = frame.event else {
            Issue.record("\(fixture) did not decode as a chat event")
            throw CancellationError()
        }
        return event
    }

    @Test func status() throws {
        let event = try chatEvent("chat-status.event")
        #expect(event.state == .status(ChatEvent.Status(
            phase: .startingModel, retry: ChatEvent.Retry(attempt: 1, maxAttempts: 3, reason: "rate_limit"))))
    }

    @Test func appendingDelta() throws {
        let event = try chatEvent("chat-delta.event")
        #expect(event.seq == 2)
        guard case .delta(let delta) = event.state else { Issue.record("Expected delta"); return }
        #expect(delta.deltaText == "You're using ")
        #expect(!delta.isReplacement)
        #expect(delta.message == nil)
    }

    @Test func replacingDelta() throws {
        guard case .delta(let delta) = try chatEvent("chat-delta-replace.event").state else {
            Issue.record("Expected delta")
            return
        }
        #expect(delta.isReplacement)
        #expect(delta.message?.content == [.text("You are using **160 GB**")])
    }

    @Test func final() throws {
        let event = try chatEvent("chat-final.event")
        guard case .final(let final) = event.state else { Issue.record("Expected final"); return }
        #expect(final.stopReason == "stop")
        #expect(final.message?.entryId == "entry-0004")
        #expect(event.usage?["output"] == 60)
    }

    @Test func aborted() throws {
        #expect(try chatEvent("chat-aborted.event").state == .aborted(ChatEvent.Aborted(
            errorMessage: "Run aborted by operator", stopReason: "aborted")))
    }

    @Test func error() throws {
        guard case .error(let failure) = try chatEvent("chat-error.event").state else {
            Issue.record("Expected error")
            return
        }
        #expect(failure.errorKind == .rateLimit)
        #expect(failure.errorDetail?.httpStatus == 429)
    }

    @Test func unclassifiedErrorKindIsNotUnknown() throws {
        guard case .error(let failure) = try chatEvent("chat-error-unclassified.event").state else {
            Issue.record("Expected error")
            return
        }
        #expect(failure.errorKind == .unclassified)
        #expect(failure.errorKind?.rawValue == "unknown")
    }

    @Test func unknownStateDecodes() throws {
        let event = try decode(
            ChatEvent.self,
            #"{"runId":"r","sessionKey":"s","seq":1,"state":"thinking-harder","somethingNew":true}"#)
        #expect(event.state == .unknown("thinking-harder"))
    }

    @Test func unknownPhaseDecodes() throws {
        let event = try decode(ChatEvent.self, #"{"runId":"r","sessionKey":"s","seq":1,"state":"status","phase":"warming_up"}"#)
        #expect(event.state == .status(ChatEvent.Status(phase: .unknown("warming_up"))))
    }

    @Test func sendAcknowledgment() throws {
        let response = try #require(Fixtures.decode(ResponseFrame<ChatSendResponse>.self, from: "chat-send.res").payload)
        #expect(response == ChatSendResponse(runId: "00000000-0000-4000-8000-000000000001", status: .started))
        let retry = try #require(Fixtures.decode(ResponseFrame<ChatSendResponse>.self, from: "chat-send-in-flight.res").payload)
        #expect(retry.status == .inFlight)
    }

    @Test func historyPage() throws {
        let page = try #require(Fixtures.decode(ResponseFrame<ChatHistoryPage>.self, from: "chat-history.res").payload)
        #expect(page.messages.map(\.role) == [.user, .assistant, .toolResult, .assistant])
        #expect(page.messages.map(\.entryId) == ["entry-0001", "entry-0002", "entry-0003", "entry-0004"])
        #expect(page.hasMore == true)
        #expect(page.nextOffset == 4)
        #expect(page.deltaCursor == "fake-delta-cursor-0001")
        #expect(page.sessionInfo?.activeRunIds == [])

        let assistant = page.messages[1]
        #expect(assistant.content == [
            .thinking("I should run df."),
            .text("Let me check."),
            .toolCall(ContentBlock.ToolCall(id: "call-0001", name: "exec", arguments: ["command": "df -h"])),
        ])
        let toolResult = page.messages[2]
        #expect(toolResult.toolCallId == "call-0001")
        #expect(toolResult.isError == false)

        guard case .media(let image) = page.messages[3].content.last else { Issue.record("Expected image"); return }
        #expect(image.kind == .image)
        #expect(image.url == "/api/chat/media/outgoing/fake-artifact-0001/full")
        #expect(image.width == 640)
    }

    @Test func historyCatchUp() throws {
        let delta = try #require(Fixtures.decode(ResponseFrame<ChatHistoryCatchUp>.self, from: "chat-history-delta.res").payload)
        guard case .delta(let changes) = delta else { Issue.record("Expected delta"); return }
        #expect(changes.deltaCursor == "fake-delta-cursor-0002")
        #expect(changes.messages.count == 1)

        let reset = try Fixtures.decode(ResponseFrame<ChatHistoryCatchUp>.self, from: "chat-history-reset.res").payload
        #expect(reset == .reset)
        #expect(try decode(ChatHistoryCatchUp.self, #"{"kind":"rewound"}"#) == .unknown("rewound"))
    }

    @Test func historyCatchUpUnwrapsSessionMessageEnvelopes() throws {
        let result = try decode(ChatHistoryCatchUp.self, #"{"kind":"delta","deltaCursor":"next","messages":[{"sessionKey":"s","messageId":"entry","runId":"r","message":{"role":"assistant","content":[{"type":"text","text":"Done"}],"__openclaw":{"id":"entry","runId":"r"}}}]}"#)
        guard case .delta(let delta) = result else { Issue.record("Expected delta"); return }
        #expect(delta.messages.map(\.role) == [.assistant])
        #expect(delta.messages.first?.content == [.text("Done")])
        #expect(delta.messages.first?.entryId == "entry")
        #expect(delta.messages.first?.metadata?.runId == "r")
        #expect(delta.deltaCursor == "next")
    }

    @Test func malformedHistoryEnvelopeStillFailsDecoding() {
        #expect(throws: DecodingError.self) {
            try decode(ChatHistoryCatchUp.self, #"{"kind":"delta","deltaCursor":"next","messages":[{"message":{"content":"Missing role"}}]}"#)
        }
    }

    @Test(arguments: ["toolCall", "tool_use", "tooluse", "tool_call"])
    func toolCallSpellings(type: String) throws {
        let block = try decode(ContentBlock.self, #"{"type":"\#(type)","id":"c1","name":"exec","arguments":{}}"#)
        #expect(block == .toolCall(ContentBlock.ToolCall(id: "c1", name: "exec", arguments: [:])))
    }

    @Test func unknownContentBlockRoundTrips() throws {
        let json = #"{"type":"hologram","depth":3}"#
        let block = try decode(ContentBlock.self, json)
        #expect(block == .unknown(type: "hologram", ["type": "hologram", "depth": 3]))
        #expect(try JSONValue(encoding: block) == ["type": "hologram", "depth": 3])
    }

    @Test func stringContentBecomesTextBlock() throws {
        let message = try decode(ChatMessage.self, #"{"role":"user","content":"Hi there"}"#)
        #expect(message.content == [.text("Hi there")])
    }

    @Test func missingContentIsEmpty() throws {
        let message = try decode(ChatMessage.self, #"{"role":"custom-role"}"#)
        #expect(message.role == .unknown("custom-role"))
        #expect(message.content.isEmpty)
    }
}
