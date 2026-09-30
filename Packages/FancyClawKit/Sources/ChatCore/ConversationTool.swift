import Foundation
import GatewayProtocol

public struct ConversationTool: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable { case running, success, error, interrupted }
    public let id: String
    public var name: String
    public var arguments: JSONValue?
    public var result: JSONValue?
    public var status: Status

    public init(id: String, name: String, arguments: JSONValue? = nil,
                result: JSONValue? = nil, status: Status = .running) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.status = status
    }

    public static func formatted(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        if let text = value.stringValue { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
