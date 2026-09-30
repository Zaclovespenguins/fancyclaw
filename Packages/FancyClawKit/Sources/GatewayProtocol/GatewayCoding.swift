import Foundation

/// Factory for the JSON coders used on the Gateway wire.
///
/// Timestamps travel as integer milliseconds, so no date strategy is configured; models expose `Date`
/// conveniences where useful.
public enum GatewayCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}

extension Date {
    /// Creates a date from a Gateway millisecond timestamp.
    public init(gatewayMilliseconds milliseconds: Int) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    /// Creates a date from a Gateway millisecond timestamp.
    public init(gatewayMilliseconds milliseconds: Double) {
        self.init(timeIntervalSince1970: milliseconds / 1000)
    }
}
