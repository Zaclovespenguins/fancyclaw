import Foundation
import GatewayProtocol

/// A minimal JSON Schema (draft-07) checker for the OpenClaw protocol schema.
///
/// It supports the keywords the generated schema uses for the definitions FancyClaw models: `type`, `const`,
/// `enum`, `properties`, `required`, `additionalProperties: false`, `patternProperties` (as "open"), `items`,
/// `anyOf`/`oneOf`, `minLength`/`maxLength` and `minimum`. Unsupported keywords are ignored, so a clean result
/// means "no violation found", not full validation.
public struct ProtocolSchema: Sendable {
    public let release: String?
    public let definitions: [String: JSONValue]

    public init(json: JSONValue) throws {
        release = json["x-fancyclaw"]?["release"]?.stringValue
        definitions = json["definitions"]?.objectValue ?? [:]
    }

    public func definition(_ name: String) -> JSONValue? {
        definitions[name]
    }

    /// Checks `value` against the named definition and returns human-readable violations.
    public func violations(of value: JSONValue, against definitionName: String) -> [String] {
        guard let schema = definitions[definitionName] else {
            return ["No definition named \(definitionName) in the schema subset."]
        }
        return Self.violations(of: value, against: schema, path: "$")
    }

    public static func violations(of value: JSONValue, against schema: JSONValue, path: String) -> [String] {
        guard case .object(let rules) = schema else { return [] }
        var problems: [String] = []

        if let branches = (rules["anyOf"] ?? rules["oneOf"])?.arrayValue {
            let results = branches.map { violations(of: value, against: $0, path: path) }
            if !results.contains(where: \.isEmpty) {
                // Report the closest branch so failures stay readable.
                let closest = results.min { $0.count < $1.count } ?? []
                problems.append("\(path): matches no anyOf branch; closest: \(closest.joined(separator: "; "))")
            }
        }

        if let constant = rules["const"], !value.jsonEquals(constant) {
            problems.append("\(path): expected const \(constant.compactDescription), found \(value.compactDescription)")
        }
        if let allowed = rules["enum"]?.arrayValue, !allowed.contains(where: value.jsonEquals) {
            problems.append("\(path): \(value.compactDescription) is not one of \(allowed.map(\.compactDescription))")
        }

        if let type = rules["type"] {
            let types = type.arrayValue?.compactMap(\.stringValue) ?? [type.stringValue].compactMap { $0 }
            if !types.isEmpty, !types.contains(where: value.isJSONType) {
                problems.append("\(path): expected \(types.joined(separator: "|")), found \(value.jsonTypeName)")
                return problems
            }
        }

        switch value {
        case .string(let string):
            if let minimum = rules["minLength"]?.intValue, string.count < minimum {
                problems.append("\(path): shorter than minLength \(minimum)")
            }
            if let maximum = rules["maxLength"]?.intValue, string.count > maximum {
                problems.append("\(path): longer than maxLength \(maximum)")
            }
        case .integer, .double:
            if let minimum = rules["minimum"]?.doubleValue, let number = value.doubleValue, number < minimum {
                problems.append("\(path): below minimum \(minimum)")
            }
        case .array(let items):
            if let itemSchema = rules["items"] {
                for (index, item) in items.enumerated() {
                    problems += violations(of: item, against: itemSchema, path: "\(path)[\(index)]")
                }
            }
        case .object(let object):
            let properties = rules["properties"]?.objectValue ?? [:]
            for key in rules["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where object[key] == nil {
                problems.append("\(path): missing required key \(key)")
            }
            let isClosed = rules["additionalProperties"] == .bool(false) && rules["patternProperties"] == nil
            for (key, child) in object.sorted(by: { $0.key < $1.key }) {
                if let propertySchema = properties[key] {
                    problems += violations(of: child, against: propertySchema, path: "\(path).\(key)")
                } else if isClosed {
                    problems.append("\(path): unexpected key \(key) in a closed object")
                }
            }
        default:
            break
        }
        return problems
    }
}

extension JSONValue {
    /// Equality that treats `1` and `1.0` as the same number, as JSON does.
    public func jsonEquals(_ other: JSONValue) -> Bool {
        switch (self, other) {
        case (.integer, .double), (.double, .integer): doubleValue == other.doubleValue
        case (.array(let lhs), .array(let rhs)): lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.jsonEquals($1) }
        case (.object(let lhs), .object(let rhs)):
            lhs.count == rhs.count && lhs.allSatisfy { key, value in rhs[key].map(value.jsonEquals) ?? false }
        default: self == other
        }
    }

    /// Whether every key and value in `self` also appears in `other`, recursively. Arrays must match
    /// element-for-element, with each element a subset of its counterpart.
    ///
    /// Used to check that decoding then re-encoding a fixture loses fields but never invents or alters any.
    public func isJSONSubset(of other: JSONValue) -> Bool {
        switch (self, other) {
        case (.object(let lhs), .object(let rhs)):
            lhs.allSatisfy { key, value in rhs[key].map(value.isJSONSubset(of:)) ?? false }
        case (.array(let lhs), .array(let rhs)):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.isJSONSubset(of: $1) }
        default:
            jsonEquals(other)
        }
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    var jsonTypeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .integer: "integer"
        case .double: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    func isJSONType(_ name: String) -> Bool {
        switch (name, self) {
        case ("number", .integer), ("number", .double): true
        case ("integer", .double(let value)): value.rounded() == value
        default: name == jsonTypeName
        }
    }

    var compactDescription: String {
        let data = (try? GatewayCoding.encoder().encode(self)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
