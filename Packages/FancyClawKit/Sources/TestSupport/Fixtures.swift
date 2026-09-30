import Foundation
import GatewayProtocol

/// Loads the protocol fixtures bundled with `TestSupport`.
///
/// `Fixtures/frames/*.json` are complete wire frames built from the OpenClaw docs and source, with obviously
/// fake ids and tokens. `Fixtures/protocol.schema.json` is the subset of the official schema they're checked
/// against; regenerate it with `Scripts/refresh-protocol-schema.mjs`.
public enum Fixtures {
    public enum Error: Swift.Error, CustomStringConvertible {
        case missing(String)

        public var description: String {
            switch self {
            case .missing(let name): "No fixture named \(name)"
            }
        }
    }

    /// The names of every frame fixture, without the `.json` extension.
    public static var frameNames: [String] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/frames") ?? []
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// The raw bytes of a frame fixture.
    public static func frameData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/frames")
        else { throw Error.missing(name) }
        return try Data(contentsOf: url)
    }

    /// A frame fixture parsed as untyped JSON.
    public static func frame(_ name: String) throws -> JSONValue {
        try GatewayCoding.decoder().decode(JSONValue.self, from: frameData(name))
    }

    /// A frame fixture decoded as a protocol type.
    public static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try GatewayCoding.decoder().decode(T.self, from: frameData(name))
    }

    /// The bundled schema subset.
    public static func schema() throws -> ProtocolSchema {
        guard let url = Bundle.module.url(forResource: "protocol.schema", withExtension: "json", subdirectory: "Fixtures")
        else { throw Error.missing("protocol.schema") }
        return try ProtocolSchema(json: GatewayCoding.decoder().decode(JSONValue.self, from: Data(contentsOf: url)))
    }
}
