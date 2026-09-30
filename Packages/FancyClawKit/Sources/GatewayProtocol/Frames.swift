import Foundation

/// The discriminant every Gateway frame carries in its `type` field.
public enum FrameType: OpenEnum {
    case request
    case response
    case event
    case unknown(String)

    public static let knownCases: [FrameType] = [.request, .response, .event]

    public var rawValue: String {
        switch self {
        case .request: "req"
        case .response: "res"
        case .event: "event"
        case .unknown(let value): value
        }
    }
}

/// The routing fields of any frame, decoded before the payload so the connection can pick a concrete type.
public struct FrameHeader: Decodable, Hashable, Sendable {
    public var type: FrameType
    /// The correlation id of a request or response.
    public var id: String?
    /// The event name of an event frame.
    public var event: String?
    /// Whether a response succeeded.
    public var ok: Bool?
}

/// A client-to-Gateway RPC call: `{type:"req", id, method, params?}`.
public struct RequestFrame<Params: Codable & Sendable>: Codable, Sendable {
    public var id: String
    public var method: String
    public var params: Params?

    public init(id: String = UUID().uuidString, method: String, params: Params?) {
        self.id = id
        self.method = method
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, method, params
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.expectFrameType(.request)
        id = try container.decode(String.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(Params.self, forKey: .params)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(FrameType.request, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

extension RequestFrame: Equatable where Params: Equatable {}
extension RequestFrame: Hashable where Params: Hashable {}

/// The Gateway's reply to a request: `{type:"res", id, ok, payload?, error?}`.
public struct ResponseFrame<Payload: Codable & Sendable>: Codable, Sendable {
    public var id: String
    public var ok: Bool
    public var payload: Payload?
    public var error: GatewayErrorShape?

    public init(id: String, ok: Bool, payload: Payload? = nil, error: GatewayErrorShape? = nil) {
        self.id = id
        self.ok = ok
        self.payload = payload
        self.error = error
    }

    /// The payload of a successful response, or the Gateway's error.
    public var result: Result<Payload?, GatewayErrorShape> {
        if ok { return .success(payload) }
        return .failure(error ?? GatewayErrorShape(code: .unknown(""), message: "The Gateway reported an error without details."))
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, ok, payload, error
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.expectFrameType(.response)
        id = try container.decode(String.self, forKey: .id)
        ok = try container.decode(Bool.self, forKey: .ok)
        // A failed response's payload is never meaningful; skip it so a typed payload can't fail decoding.
        payload = ok ? try container.decodeIfPresent(Payload.self, forKey: .payload) : nil
        error = try container.decodeIfPresent(GatewayErrorShape.self, forKey: .error)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(FrameType.response, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

extension ResponseFrame: Equatable where Payload: Equatable {}
extension ResponseFrame: Hashable where Payload: Hashable {}

/// Per-connection counters for the presence and health snapshots, carried on some events.
public struct StateVersion: Codable, Hashable, Sendable {
    public var presence: Int
    public var health: Int

    public init(presence: Int, health: Int) {
        self.presence = presence
        self.health = health
    }
}

/// A Gateway push: `{type:"event", event, payload?, seq?, stateVersion?}`.
///
/// Use ``GatewayEventFrame`` to decode the payload based on the event name.
public struct EventFrame<Payload: Codable & Sendable>: Codable, Sendable {
    public var event: String
    public var payload: Payload?
    public var seq: Int?
    public var stateVersion: StateVersion?

    public init(event: String, payload: Payload?, seq: Int? = nil, stateVersion: StateVersion? = nil) {
        self.event = event
        self.payload = payload
        self.seq = seq
        self.stateVersion = stateVersion
    }

    private enum CodingKeys: String, CodingKey {
        case type, event, payload, seq, stateVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.expectFrameType(.event)
        event = try container.decode(String.self, forKey: .event)
        payload = try container.decodeIfPresent(Payload.self, forKey: .payload)
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        stateVersion = try container.decodeIfPresent(StateVersion.self, forKey: .stateVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(FrameType.event, forKey: .type)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(seq, forKey: .seq)
        try container.encodeIfPresent(stateVersion, forKey: .stateVersion)
    }
}

extension EventFrame: Equatable where Payload: Equatable {}
extension EventFrame: Hashable where Payload: Hashable {}

extension KeyedDecodingContainer {
    func expectFrameType(_ expected: FrameType) throws {
        let key = Key(stringValue: "type")!
        let type = try decode(FrameType.self, forKey: key)
        guard type == expected else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self,
                debugDescription: "Expected a \(expected.rawValue) frame but found \(type.rawValue).")
        }
    }
}
