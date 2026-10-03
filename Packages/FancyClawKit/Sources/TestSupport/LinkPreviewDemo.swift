import GatewayProtocol

public enum LinkPreviewDemo {
    public static var history: [ChatMessage] {
        [ChatMessage(role: .assistant, content: [.text("[SwiftUI](https://developer.apple.com/documentation/swiftui) can help shape the interface.")],
                     metadata: .init(id: "demo-link-final")),
         ChatMessage(role: .assistant, content: [.text("This site is unavailable: https://offline.example.com/report")],
                     metadata: .init(id: "demo-link-offline"))]
    }

    public static func partialStream(sessionKey: String) -> GatewayEventFrame {
        .init(event: .chat(.init(runId: "demo-link-stream", sessionKey: sessionKey, seq: 1,
                                state: .delta(.init(deltaText: "Still drafting a link: https://streaming.example.com")))))
    }
}
