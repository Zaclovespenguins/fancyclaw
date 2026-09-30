/// A string enumeration that tolerates values introduced by newer Gateways.
///
/// Conforming enums list the values FancyClaw understands plus an `unknown(String)` case, so decoding never
/// fails on a new value and the original string round-trips unchanged. Construct values with
/// ``init(rawValue:)`` rather than `.unknown(_:)` so known strings map to their named case.
public protocol OpenEnum: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
where RawValue == String {
    /// Every named case, used to map raw strings back to cases.
    static var knownCases: [Self] { get }

    /// Wraps a raw value that no named case matches.
    static func unknown(_ rawValue: String) -> Self
}

extension OpenEnum {
    public init(rawValue: String) {
        self = Self.resolve(rawValue)
    }

    public init(from decoder: any Decoder) throws {
        self = Self.resolve(try decoder.singleValueContainer().decode(String.self))
    }

    private static func resolve(_ rawValue: String) -> Self {
        knownCases.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Whether the value is one FancyClaw has a named case for.
    public var isKnown: Bool { Self.knownCases.contains(self) }
}
