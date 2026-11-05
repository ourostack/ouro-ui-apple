import Foundation

/// A JSON value: what a node's state, an action's input and every wire message are made of.
///
/// It encodes with sorted keys, so the same state always prints the same bytes and an agent (or a test) can diff two
/// `ls` replies line by line.
public enum ReinsValue: Sendable, Hashable, Codable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ReinsValue])
    case object([String: ReinsValue])

    /// Encodes any `Encodable` value through `JSONEncoder`. Dates encode as ISO 8601.
    public init(encoding value: some Encodable) throws {
        let data = try Self.encoder.encode(value)
        self = try JSONDecoder().decode(ReinsValue.self, from: data)
    }

    /// Parses JSON text.
    public init(json: String) throws {
        self = try JSONDecoder().decode(ReinsValue.self, from: Data(json.utf8))
    }

    /// Decodes this value as `T`.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    /// Compact JSON with sorted keys.
    public var json: String {
        // Encoding a ReinsValue cannot fail: every case is plain JSON.
        String(decoding: (try? Self.encoder.encode(self)) ?? Data("null".utf8), as: UTF8.self)
    }

    public var description: String { json }

    /// The member `key` of an object, or nil.
    public subscript(key: String) -> ReinsValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    /// The element at `index` of an array, or nil.
    public subscript(index: Int) -> ReinsValue? {
        if case .array(let elements) = self, elements.indices.contains(index) { return elements[index] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
    public var intValue: Int? { numberValue.flatMap { $0.rounded() == $0 ? Int(exactly: $0) : nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var arrayValue: [ReinsValue]? { if case .array(let a) = self { a } else { nil } }
    public var objectValue: [String: ReinsValue]? { if case .object(let o) = self { o } else { nil } }

    /// The JSON type name, as JSON Schema spells it (`integer` for whole numbers).
    var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number(let n): n.rounded() == n ? "integer" : "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ReinsValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: ReinsValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n):
            if n.rounded() == n, let whole = Int(exactly: n) { try container.encode(whole) } else { try container.encode(n) }
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

extension ReinsValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: ReinsValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, ReinsValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
