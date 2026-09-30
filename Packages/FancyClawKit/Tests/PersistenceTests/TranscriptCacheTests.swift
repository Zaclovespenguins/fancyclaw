import Foundation
import GatewayProtocol
import Persistence
import SwiftData
import Testing

@Suite("Transcript cache") @MainActor
struct TranscriptCacheTests {
    @Test func upsertReconcileAndNamespaceIsolation() throws {
        let container = try TranscriptCache.makeContainer(inMemory: true)
        let cache = TranscriptCache(container: container, gateway: "one")
        let other = TranscriptCache(container: container, gateway: "two")
        try cache.saveSessions([SessionSummary(key: "a", label: "Old"), SessionSummary(key: "b")])
        try other.saveSessions([SessionSummary(key: "a", label: "Other")])
        try cache.saveSessions([SessionSummary(key: "a", label: "Renamed")])
        #expect(try cache.sessions().count == 2)
        #expect(try cache.sessions().first { $0.key == "a" }?.label == "Renamed")
        try cache.saveSessions([SessionSummary(key: "a", label: "Final")], reconcile: true)
        #expect(try cache.sessions().map(\.key) == ["a"])
        #expect(try other.sessions().first?.label == "Other")
    }

    @Test func historyReopensInCanonicalOrderAndRemovesObsoleteEntries() throws {
        let container = try TranscriptCache.makeContainer(inMemory: true)
        let cache = TranscriptCache(container: container, gateway: "gateway")
        let a = ChatMessage(role: .user, content: [.text("a")], metadata: .init(id: "a"))
        let b = ChatMessage(role: .assistant, content: [.text("b")], metadata: .init(id: "b"))
        try cache.saveHistory(.init(sessionKey: "chat", sessionId: "session", messages: [a, b], hasMore: true, nextOffset: 2, deltaCursor: "c1"))
        let reopened = TranscriptCache(container: container, gateway: "gateway")
        let page = try #require(try reopened.history("chat"))
        #expect(page.messages == [a, b])
        #expect(page.deltaCursor == "c1")
        #expect(page.nextOffset == 2)
        var changed = b
        changed.content = [.text("changed")]
        try reopened.saveHistory(.init(sessionKey: "chat", messages: [changed], deltaCursor: "c2"))
        #expect(try reopened.history("chat")?.messages == [changed])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<CachedMessage>()) == 1)
    }

    @Test func deletingSessionClearsHistoryButPreservesOtherGateway() throws {
        let container = try TranscriptCache.makeContainer(inMemory: true)
        let first = TranscriptCache(container: container, gateway: "one")
        let second = TranscriptCache(container: container, gateway: "two")
        for cache in [first, second] {
            try cache.saveSessions([SessionSummary(key: "same")])
            try cache.saveHistory(.init(sessionKey: "same", messages: [ChatMessage(role: .user, content: [.text("saved")])]))
        }
        try first.deleteSession("same")
        #expect(try first.sessions().isEmpty)
        #expect(try first.history("same") == nil)
        #expect(try second.history("same")?.messages.count == 1)
    }

    @Test func cacheKeepsMediaReferencesAndDropsInlineBytes() throws {
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        let input: JSONValue = ["role": "assistant", "content": [
            ["type": "image", "url": "data:image/png;base64,secret", "artifactId": "artifact"],
            ["type": "future", "bytes": "secret"]
        ], "__openclaw": ["id": "image"]]
        try cache.saveHistory(.init(sessionKey: "s", messages: [try input.decode(as: ChatMessage.self)]))
        let message = try #require(try cache.history("s")?.messages.first)
        #expect(message.content.count == 1)
        guard case .media(let media) = message.content[0] else { Issue.record("Expected media reference"); return }
        #expect(media.artifactId == "artifact")
        #expect(media.url == nil)
    }
}
