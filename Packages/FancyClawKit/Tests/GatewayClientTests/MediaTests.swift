import Foundation
import GatewayProtocol
import os
import TestSupport
import Testing
@testable import GatewayClient

@Suite("Gateway images", .serialized)
struct MediaTests {
    @Test(arguments: [
        ("/api/chat/media/outgoing/a/full", "https://gateway.ts.net/proxy/api/chat/media/outgoing/a/full"),
        ("/api/artifacts/download/connection/ticket", "https://gateway.ts.net/proxy/api/artifacts/download/connection/ticket"),
        ("https://gateway.ts.net/api/chat/media/outgoing/a/full", "https://gateway.ts.net/proxy/api/chat/media/outgoing/a/full"),
        ("images/a.png", "https://gateway.ts.net/proxy/images/a.png"),
        ("https://cdn.example/image.png", "https://cdn.example/image.png")
    ])
    func resolvesRelativeReferences(pair: (String, String)) throws {
        let gateway = try #require(URL(string: "wss://gateway.ts.net/proxy/"))
        #expect(try ArtifactURLResolver.resolve(pair.0, gateway: gateway).absoluteString == pair.1)
    }

    @Test(arguments: ["file:///tmp/photo.png", "data:image/png;base64,AAAA", "http://public.example/image.png", "https://user:password@example.com/a"])
    func rejectsUnsupportedReferences(_ reference: String) throws {
        let gateway = try #require(URL(string: "wss://gateway.ts.net/"))
        #expect(throws: (any Error).self) { try ArtifactURLResolver.resolve(reference, gateway: gateway) }
    }

    @Test func credentialsAreOriginBoundIncludingPortAndScheme() throws {
        let gateway = try #require(URL(string: "wss://gateway.ts.net/"))
        #expect(ArtifactURLResolver.isSameOrigin(try #require(URL(string: "https://gateway.ts.net:443/image")), gateway: gateway))
        for value in ["https://gateway.ts.net:8443/image", "http://gateway.ts.net/image", "https://cdn.example/image"] {
            #expect(!ArtifactURLResolver.isSameOrigin(try #require(URL(string: value)), gateway: gateway))
        }
    }

    @Test func artifactDownloadUsesSessionAndClosedParameters() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let expected = Data([1, 2, 3])
        fake.reply(to: "artifacts.download", with: ["encoding": "base64", "data": .string(expected.base64EncodedString())])
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        defer { fake.stop() }
        let data = try await connection.imageData(sessionKey: "agent:main:main", media: .init(kind: .image, artifactId: "image-id", url: "/expired"))
        #expect(data == expected)
        let request = try #require(fake.receivedRequests.first { $0.method == "artifacts.download" })
        #expect(request.params == ["sessionKey": "agent:main:main", "artifactId": "image-id"])
        await connection.disconnect()
    }

    @Test func imageRequestsAuthenticateGatewayOnlyAndSkipPersistentCache() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageRequestProtocol.self]
        let connection = GatewayConnection(identity: .generate(), session: URLSession(configuration: configuration))
        let gateway = try await fake.start()
        defer { fake.stop() }
        _ = try await connection.connect(to: gateway, token: "test-token")
        ImageRequestProtocol.requests.withLock { $0 = [] }
        _ = try await connection.imageData(sessionKey: "main", media: .init(kind: .image, url: "/api/chat/media/outgoing/id/full"))
        _ = try await connection.imageData(sessionKey: "main", media: .init(kind: .image, url: "https://cdn.example/photo.png"))
        let requests = ImageRequestProtocol.requests.withLock { $0 }
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        await connection.disconnect()
        await #expect(throws: ConnectionError.self) {
            try await connection.imageData(sessionKey: "main", media: .init(kind: .image, url: "/image"))
        }
    }

    @Test func mediaRedirectsAreRefused() throws {
        let session = URLSession(configuration: .ephemeral)
        let url = try #require(URL(string: "https://gateway.ts.net/image"))
        let task = session.dataTask(with: url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let redirect = URLRequest(url: try #require(URL(string: "https://other.example/image")))
        let accepted = OSAllocatedUnfairLock(initialState: true)
        MediaRedirectDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirect) { request in
            accepted.withLock { $0 = request != nil }
        }
        #expect(!accepted.withLock { $0 })
        session.invalidateAndCancel()
    }
}

private final class ImageRequestProtocol: URLProtocol, @unchecked Sendable {
    static let requests = OSAllocatedUnfairLock(initialState: [URLRequest]())
    override class func canInit(with request: URLRequest) -> Bool { request.value(forHTTPHeaderField: "Accept") == "image/*" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
