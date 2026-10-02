import Foundation
import GatewayProtocol
import Testing
@testable import ChatCore

@Suite struct ChatPresentationTests {
    private func tool(_ name: String, _ status: ConversationTool.Status, id: String = UUID().uuidString) -> ConversationTool {
        ConversationTool(id: id, name: name, status: status)
    }

    @Test func noToolsHasNoSummary() {
        #expect(ToolSummary.make(for: []) == nil)
    }

    @Test func singleToolShowsNameAndStatus() {
        #expect(ToolSummary.make(for: [tool("read_file", .success)]) == .init(text: "Ran read_file", state: .done))
        #expect(ToolSummary.make(for: [tool("exec", .running)]) == .init(text: "Running exec", state: .running))
        #expect(ToolSummary.make(for: [tool("exec", .error)]) == .init(text: "exec failed", state: .failed))
        #expect(ToolSummary.make(for: [tool("exec", .interrupted)]) == .init(text: "exec ended", state: .done))
    }

    @Test func severalToolsShowACountAndState() {
        let done = [tool("a", .success), tool("b", .success), tool("c", .interrupted)]
        #expect(ToolSummary.make(for: done) == .init(text: "Used 3 tools", state: .done))
        let failed = [tool("a", .success), tool("b", .error)]
        #expect(ToolSummary.make(for: failed) == .init(text: "Used 2 tools · 1 failed", state: .failed))
        let running = [tool("a", .success), tool("b", .error), tool("c", .running)]
        #expect(ToolSummary.make(for: running) == .init(text: "Using 3 tools · 1 running · 1 failed", state: .running))
    }

    private func approval(_ details: ExecApprovalRequest.Details, status: ConversationApproval.Status = .pending) -> ConversationApproval {
        var value = ConversationApproval(request: .init(id: "a1", createdAtMs: 0, expiresAtMs: 60_000, request: details),
                                         sessionKey: "agent:main:main")
        value.status = status
        return value
    }

    @Test func approvalTitleRule() {
        #expect(approval(.init(command: "ls -la", commandPreview: "List files", warningText: "Careful")).displayTitle == "List files")
        #expect(approval(.init(command: "ls -la", commandPreview: "  ", warningText: "Careful")).displayTitle == "Careful")
        #expect(approval(.init(command: "ls -la")).displayTitle == "Run a command")
    }

    @Test func approvalReceipts() {
        let details = ExecApprovalRequest.Details(command: "pwd")
        #expect(approval(details).receipt == nil)
        #expect(approval(details, status: .resolving).receipt == nil)
        #expect(approval(details, status: .resolved(.allowOnce)).receipt == "Approved · pwd")
        #expect(approval(details, status: .resolved(.allowAlways)).receipt == "Always allowed · pwd")
        #expect(approval(details, status: .resolved(.deny)).receipt == "Denied · pwd")
        #expect(approval(details, status: .alreadyHandled).receipt == "Handled elsewhere · pwd")
        #expect(approval(details, status: .expired).receipt == "Expired · pwd")
    }

    @Test func fileDetailLine() {
        let full = ContentBlock.Media(kind: .file, mimeType: "text/plain", fileName: "notes.txt", sizeBytes: 2048)
        #expect(full.fileDetail.hasSuffix(" · TXT"))
        #expect(full.fileDetail.count > 6)
        #expect(ContentBlock.Media(kind: .file, mimeType: "application/pdf").fileDetail == "PDF")
        #expect(ContentBlock.Media(kind: .file, fileName: "Makefile").fileDetail == "")
        #expect(ContentBlock.Media(kind: .file, mimeType: "application/vnd.api+json", fileName: "x").fileTypeLabel == "VND.API")
    }

    @Test func downloadFileNamesAreSanitized() {
        #expect(ContentBlock.Media(kind: .file, fileName: "report.pdf").safeFileName == "report.pdf")
        #expect(ContentBlock.Media(kind: .file, fileName: "../../etc/passwd").safeFileName == "passwd")
        #expect(ContentBlock.Media(kind: .file, fileName: "a\\b\\c.txt").safeFileName == "c.txt")
        #expect(ContentBlock.Media(kind: .file, fileName: "..").safeFileName == "Download")
        #expect(ContentBlock.Media(kind: .file, fileName: nil).safeFileName == "Download")
        #expect(ContentBlock.Media(kind: .file, fileName: "dir/").safeFileName == "dir")
    }
}
