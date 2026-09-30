import CoreGraphics
import Foundation
import GatewayClient
import GatewayProtocol
import ImageIO
import TestSupport
import Testing
import UniformTypeIdentifiers
@testable import ChatCore

@Suite("Attachments", .serialized)
struct AttachmentTests {
    private let limits = HelloOK.AttachmentLimits(maxBytes: 10_000, maxImageBytes: 3_000)

    @Test(arguments: [("report.PDF", "application/pdf"), ("notes.txt", "text/plain"),
                      ("photo.heic", "image/heic"), ("photo.png", "image/png"),
                      ("photo.jpeg", "image/jpeg"), ("unknown.fancyclaw", "application/octet-stream")])
    func detectsMIMEType(example: (String, String)) {
        #expect(AttachmentPipeline.mimeType(for: example.0) == example.1)
    }

    @Test func acceptsExactFileLimitRejectsOversizeAndEmpty() async throws {
        let pipeline = AttachmentPipeline()
        let bytes = Data(repeating: 42, count: 10_000)
        let accepted = try await pipeline.prepare(data: bytes, fileName: "data.bin", limits: limits)
        #expect(accepted.data == bytes)
        #expect(accepted.payload.type == "file")
        await #expect(throws: AttachmentError.tooLarge(fileName: "data.bin", limit: 10_000)) {
            try await pipeline.prepare(data: bytes + Data([1]), fileName: "data.bin", limits: limits)
        }
        await #expect(throws: AttachmentError.emptyFile) {
            try await pipeline.prepare(data: Data(), fileName: "empty.txt", limits: limits)
        }
    }

    @Test func fileImporterReadsAndEnforcesLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: url)
        let pipeline = AttachmentPipeline()
        let prepared = try await pipeline.prepareFile(at: url, limits: limits)
        #expect(prepared.fileName == "notes.txt")
        #expect(prepared.mimeType == "text/plain")
        try Data(repeating: 1, count: 10_001).write(to: url)
        await #expect(throws: AttachmentError.tooLarge(fileName: "notes.txt", limit: 10_000)) {
            try await pipeline.prepareFile(at: url, limits: limits)
        }
    }

    @Test func rejectsUnreadableImage() async throws {
        let pipeline = AttachmentPipeline()
        await #expect(throws: AttachmentError.invalidImage) {
            try await pipeline.prepare(data: Data([1, 2, 3]), fileName: "bad.heic", limits: limits)
        }
        await #expect(throws: AttachmentError.invalidImage) {
            try await pipeline.prepare(data: Data([1, 2, 3]), fileName: "Photo.jpg", imageRequired: true, limits: limits)
        }
    }

    @Test func convertsHEICDownscalesAndAppliesOrientation() async throws {
        let source = try imageData(type: .heic, width: 3000, height: 1500, orientation: 6)
        let pipeline = AttachmentPipeline()
        let prepared = try await pipeline.prepare(data: source, fileName: "Photo.heic", limits: limits)
        #expect(prepared.mimeType == "image/jpeg")
        #expect(prepared.fileName == "Photo.jpg")
        #expect(prepared.data.count <= limits.maxImageBytes)
        #expect(try #require(prepared.height) <= 2048)
        #expect(try #require(prepared.width) < #require(prepared.height))
        let encoded = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        #expect(CGImageSourceGetType(encoded) as String? == UTType.jpeg.identifier)
        #expect(prepared.thumbnail != nil)
        await #expect(throws: AttachmentError.tooLarge(fileName: "Photo.heic", limit: 1)) {
            try await pipeline.prepare(data: source, fileName: "Photo.heic", limits: .init(maxBytes: 1, maxImageBytes: 1))
        }
    }

    @Test func imageLimitAlsoHonorsGeneralFileLimit() async throws {
        let pipeline = AttachmentPipeline()
        let source = try imageData(type: .png, width: 400, height: 200)
        let prepared = try await pipeline.prepare(data: source, fileName: "a.png", limits: .init(maxBytes: 1500, maxImageBytes: 5000))
        #expect(prepared.data.count <= 1500)
        #expect(prepared.payload.sizeBytes == prepared.data.count)
    }

    @Test func generatedPayloadMatchesFixtureAndClosedSchema() async throws {
        let prepared = try await AttachmentPipeline().prepare(data: Data("hello".utf8), fileName: "notes.txt", limits: limits)
        let params = ChatSendParams(sessionKey: "agent:main:main", message: "", idempotencyKey: "attachment-key",
                                    attachments: [prepared.payload])
        let value = try JSONValue(encoding: params)
        let fixture: RequestFrame<ChatSendParams> = try Fixtures.decode(RequestFrame<ChatSendParams>.self, from: "chat-send-attachment.req")
        #expect(params == fixture.params)
        #expect(try Fixtures.schema().violations(of: value, against: "ChatSendParams") == [])
        let attachment = try #require(value["attachments"]?.arrayValue?.first)
        #expect(attachment.objectValue?.keys.sorted() == ["content", "fileName", "mimeType", "origin", "sizeBytes", "type"])
        #expect(Data(base64Encoded: try #require(attachment["content"]?.stringValue)) == Data("hello".utf8))
    }

    @Test func fullFrameLimitIncludesBase64TextAndEnvelope() async throws {
        let prepared = try await AttachmentPipeline().prepare(data: Data(repeating: 255, count: 300), fileName: "a.bin", limits: limits)
        let params = ChatSendParams(sessionKey: "agent:main:main", message: "A \"quoted\" message 🦀", attachments: [prepared.payload])
        let frame = RequestFrame(id: "00000000-0000-0000-0000-000000000000", method: "chat.send", params: params)
        let size = try GatewayCoding.encoder().encode(frame).count
        let policy = HelloOK.Policy(maxPayload: size, maxBufferedBytes: size, tickIntervalMs: 15_000, attachments: limits)
        #expect(size > 400)
        try AttachmentPipeline.validate([prepared], params: params, policy: policy)
        var smaller = policy
        smaller.maxPayload -= 1
        #expect(throws: AttachmentError.frameTooLarge) { try AttachmentPipeline.validate([prepared], params: params, policy: smaller) }
        smaller = policy
        smaller.attachments?.maxBytes = 299
        #expect(throws: AttachmentError.tooLarge(fileName: "a.bin", limit: 299)) {
            try AttachmentPipeline.validate([prepared], params: params, policy: smaller)
        }
    }

    @Test @MainActor func fakeGatewayReceivesAttachmentOnlyMessageAndRetryKeepsBytesAndKey() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello), .hello(hello)])
        fake.streamChatReply("attachment received")
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let store = ConversationStore(connection: connection)
        let prepared = try await AttachmentPipeline().prepare(data: Data("hello".utf8), fileName: "notes.txt", limits: limits)
        await connection.disconnect()
        #expect(await store.send("", attachments: [prepared]))
        #expect(store.errorMessage != nil)
        let key = String(try #require(store.messages.first?.id).dropLast(5))
        #expect(store.messages.first?.attachments == [prepared])
        _ = try await connection.connect(to: url, token: "test-token")
        await store.retry(idempotencyKey: key)
        let request = try #require(fake.receivedRequests.first { $0.method == "chat.send" })
        let params = try #require(request.params).decode(as: ChatSendParams.self)
        #expect(params.message.isEmpty)
        #expect(params.idempotencyKey == key)
        #expect(params.attachments == [prepared.payload])
        #expect(store.messages.count == 1)
        store.reconcileHistory([ChatMessage(role: .user, content: [.media(.init(kind: .file, fileName: "notes.txt"))],
                                            idempotencyKey: key, metadata: .init(id: "canonical"))])
        #expect(store.messages.first?.attachments.isEmpty == true)
        let requestCount = fake.receivedRequests.count
        await store.retry(idempotencyKey: key)
        #expect(fake.receivedRequests.count == requestCount)
        await connection.disconnect()
    }

    @Test @MainActor func rejectsChangedPolicyWithoutEchoOrNetworkSend() async throws {
        var hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        hello.policy.attachments = .init(maxBytes: 4, maxImageBytes: 4)
        let fake = FakeGateway(replies: [.hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let store = ConversationStore(connection: connection)
        let prepared = try await AttachmentPipeline().prepare(data: Data("hello".utf8), fileName: "notes.txt", limits: limits)
        store.draftAttachments = [prepared]
        #expect(await store.send("", attachments: store.draftAttachments) == false)
        #expect(store.messages.isEmpty)
        #expect(!store.isStreaming)
        #expect(store.draftAttachments == [prepared])
        #expect(store.errorMessage != nil)
        #expect(!fake.receivedRequests.contains { $0.method == "chat.send" })
        await connection.disconnect()
    }

    private func imageData(type: UTType, width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
