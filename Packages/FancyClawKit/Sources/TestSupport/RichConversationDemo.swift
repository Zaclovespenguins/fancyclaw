import GatewayProtocol

/// Rich output and deliberately incomplete Markdown for simulator-only checks.
public enum RichConversationDemo {
    public static var history: [ChatMessage] {
        [ChatMessage(role: .user, content: [.text("Show me rich output")], metadata: .init(id: "demo-user")),
         ChatMessage(role: .assistant, content: [.text(#"""
         ## Gateway report
         Here is **rich output**, with `inline code` and a [documentation link](https://docs.openclaw.ai).

         > Everything is ready for your next request.

         | Feature | State |
         | --- | --- |
         | Markdown | Ready |
         | Tools | Connected |

         - A nested checklist
           - Read the plan
           - Verify the result
         - Keep the conversation moving

         ```swift
         let gateway = "FancyClaw"
         print("Hello, \(gateway)")
         // A long line should scroll horizontally without widening the transcript.
         ```

         The energy relation is $E = mc^2$.

         $$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$
         """#)], metadata: .init(id: "demo-rich"))]
    }

    public static func partialStream(sessionKey: String) -> GatewayEventFrame {
        .init(event: .chat(.init(runId: "demo-partial", sessionKey: sessionKey, seq: 1,
            state: .delta(.init(deltaText: """
            ### Still streaming
            | Task | State |
            | --- | --- |
            | Render | In progress

            ```swift
            let partial = "Waiting for the next chunk
            """)))))
    }

    public static func toolEvents(sessionKey: String) -> [GatewayEventFrame] {
        [
            .init(event: .agent(.init(runId: "demo-partial", seq: 1, stream: "tool", sessionKey: sessionKey,
                data: ["phase": "start", "name": "exec", "toolCallId": "demo-exec", "args": ["command": "swift --version"]]))),
            .init(event: .agent(.init(runId: "demo-partial", seq: 2, stream: "tool", sessionKey: sessionKey,
                data: ["phase": "result", "name": "exec", "toolCallId": "demo-exec", "result": "Swift 6.4", "isError": false]))),
            .init(event: .agent(.init(runId: "demo-partial", seq: 3, stream: "tool", sessionKey: sessionKey,
                data: ["phase": "start", "name": "read", "toolCallId": "demo-read", "args": ["path": "report.md"]]))),
            .init(event: .agent(.init(runId: "demo-partial", seq: 4, stream: "tool", sessionKey: sessionKey,
                data: ["phase": "result", "name": "read", "toolCallId": "demo-read", "result": "File unavailable", "isError": true]))),
            .init(event: .agent(.init(runId: "demo-partial", seq: 5, stream: "tool", sessionKey: sessionKey,
                data: ["phase": "start", "name": "search", "toolCallId": "demo-search", "args": ["query": "Gateway status"]])))
        ]
    }
}
