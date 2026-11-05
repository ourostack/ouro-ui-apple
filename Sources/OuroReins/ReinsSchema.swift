import Foundation

/// The shape of an action's input: the subset of JSON Schema an agent needs to build a valid payload.
///
/// `ls` prints it beside each action as JSON Schema, and `do` checks a payload against it before the action runs, so a
/// malformed payload is refused with the path that's wrong and never reaches the view model.
public indirect enum ReinsSchema: Sendable, Hashable {
    case string
    /// A string that must be one of these values.
    case oneOf([String])
    case integer
    case number
    case boolean
    case array(ReinsSchema)
    /// An object with these properties. A key not listed is refused.
    case object(properties: [String: ReinsSchema], required: [String])
    /// The schema couldn't be derived. Every payload is refused with the reason, so the gap shows up on first use.
    case underived(reason: String)

    /// The schema as JSON Schema (draft 2020-12 keywords).
    public var json: ReinsValue {
        switch self {
        case .string: ["type": "string"]
        case .oneOf(let values): ["type": "string", "enum": .array(values.map(ReinsValue.string))]
        case .integer: ["type": "integer"]
        case .number: ["type": "number"]
        case .boolean: ["type": "boolean"]
        case .array(let items): ["type": "array", "items": items.json]
        case .object(let properties, let required):
            [
                "type": "object",
                "properties": .object(properties.mapValues(\.json)),
                "required": .array(required.sorted().map(ReinsValue.string)),
                "additionalProperties": false,
            ]
        case .underived(let reason): ["x-ouro-reins-underived": .string(reason)]
        }
    }

    /// What's wrong with `value`, one line per problem, each starting with its JSON path (`$` is the root).
    public func problems(in value: ReinsValue, at path: String = "$") -> [String] {
        switch (self, value) {
        case (.underived(let reason), _):
            return ["\(path): this action's input schema couldn't be derived (\(reason))"]
        case (.string, .string), (.number, .number), (.boolean, .bool):
            return []
        case (.integer, .number(let n)):
            return n.rounded() == n ? [] : ["\(path): expected an integer, got \(n)"]
        case (.oneOf(let allowed), .string(let s)):
            return allowed.contains(s) ? [] : ["\(path): \"\(s)\" isn't one of \(allowed.map { "\"\($0)\"" }.joined(separator: ", "))"]
        case (.array(let items), .array(let elements)):
            return elements.enumerated().flatMap { items.problems(in: $0.element, at: "\(path)[\($0.offset)]") }
        case (.object(let properties, let required), .object(let members)):
            var found: [String] = []
            for key in required.sorted() where members[key] == nil || members[key] == .null {
                found.append("\(path).\(key): required, missing")
            }
            for key in members.keys.sorted() {
                guard let schema = properties[key] else {
                    found.append("\(path).\(key): not a property of this input (expected \(properties.keys.sorted().joined(separator: ", ")))")
                    continue
                }
                if members[key] == .null, !required.contains(key) { continue }
                found += schema.problems(in: members[key]!, at: "\(path).\(key)")
            }
            return found
        default:
            return ["\(path): expected \(expectedName), got \(value.typeName)"]
        }
    }

    private var expectedName: String {
        switch self {
        case .string, .oneOf: "a string"
        case .integer: "an integer"
        case .number: "a number"
        case .boolean: "a boolean"
        case .array: "an array"
        case .object: "an object"
        case .underived: "anything"
        }
    }
}

/// An action's input: a `Decodable` type whose schema Reins derives by decoding it once with a recording decoder.
///
/// Synthesized `Decodable` conformances derive with no code: non-optional properties become required, optionals become
/// optional, and nested `Decodable` structs, arrays and string enums (conforming to ``ReinsEnumerable``) nest. A type
/// with a hand-written `init(from:)` that rejects placeholder values (empty strings, zeros) declares
/// ``reinsSchema`` itself.
public protocol ReinsInput: Decodable, Sendable {
    static var reinsSchema: ReinsSchema { get }
}

extension ReinsInput {
    public static var reinsSchema: ReinsSchema {
        do {
            return try ReinsSchema.derived(from: Self.self)
        } catch {
            return .underived(reason: "decoding \(Self.self) with placeholder values threw \(error); declare `static var reinsSchema` on it")
        }
    }
}

/// A string enum an action input can hold. `CaseIterable` string enums get it by declaring the conformance.
public protocol ReinsEnumerable: Decodable {
    static var reinsCases: [String] { get }
    static var reinsPlaceholder: Self { get }
}

extension ReinsEnumerable where Self: CaseIterable & RawRepresentable, RawValue == String {
    public static var reinsCases: [String] { allCases.map(\.rawValue) }
    public static var reinsPlaceholder: Self { allCases.first! }
}

extension ReinsSchema {
    /// Derives `T`'s schema by decoding it once from a decoder that records every key and type it's asked for.
    public static func derived<T: Decodable>(from type: T.Type) throws -> ReinsSchema {
        let slot = SchemaSlot()
        _ = try SchemaProbe.decode(T.self, into: slot, codingPath: [])
        return slot.schema ?? .object(properties: [:], required: [])
    }
}

// MARK: - The recording decoder

/// Where one decoded value's schema lands.
private final class SchemaSlot {
    var schema: ReinsSchema?
}

/// A keyed container's properties, filled as `init(from:)` asks for each key.
private final class ObjectRecord {
    var properties: [String: ReinsSchema] = [:]
    var required: [String] = []
}

private struct SchemaProbe: Decoder {
    let slot: SchemaSlot
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    /// Decodes a placeholder `T`, recording its schema in `slot`. Leaf types and enums are recognised here, before
    /// their own `init(from:)` (which would reject a placeholder raw value) runs.
    static func decode<T: Decodable>(_ type: T.Type, into slot: SchemaSlot, codingPath: [any CodingKey]) throws -> T {
        if let leaf = leaf(T.self) {
            slot.schema = leaf.schema
            return leaf.value as! T
        }
        if let enumerable = T.self as? any ReinsEnumerable.Type {
            slot.schema = .oneOf(enumerable.reinsCases)
            return placeholder(of: enumerable) as! T
        }
        return try T(from: SchemaProbe(slot: slot, codingPath: codingPath))
    }

    private static func placeholder<E: ReinsEnumerable>(of type: E.Type) -> E { E.reinsPlaceholder }

    private static func leaf(_ type: Any.Type) -> (schema: ReinsSchema, value: Any)? {
        switch type {
        case is String.Type: (.string, "")
        case is Bool.Type: (.boolean, false)
        case is Int.Type: (.integer, 0)
        case is Int8.Type: (.integer, Int8(0))
        case is Int16.Type: (.integer, Int16(0))
        case is Int32.Type: (.integer, Int32(0))
        case is Int64.Type: (.integer, Int64(0))
        case is UInt.Type: (.integer, UInt(0))
        case is UInt8.Type: (.integer, UInt8(0))
        case is UInt16.Type: (.integer, UInt16(0))
        case is UInt32.Type: (.integer, UInt32(0))
        case is UInt64.Type: (.integer, UInt64(0))
        case is Double.Type: (.number, 0.0)
        case is Float.Type: (.number, Float(0))
        case is Date.Type: (.string, Date(timeIntervalSince1970: 0))
        case is URL.Type: (.string, URL(string: "about:blank")!)
        case is UUID.Type: (.string, UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        default: nil
        }
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        let record = ObjectRecord()
        slot.schema = .object(properties: [:], required: [])
        return KeyedDecodingContainer(KeyedProbe<Key>(record: record, slot: slot, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        UnkeyedProbe(slot: slot, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleProbe(slot: slot, codingPath: codingPath)
    }
}

private struct KeyedProbe<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let record: ObjectRecord
    let slot: SchemaSlot
    var codingPath: [any CodingKey]
    var allKeys: [Key] { [] }

    func contains(_ key: Key) -> Bool { true }

    private func note(_ key: Key, _ schema: ReinsSchema, required: Bool) {
        record.properties[key.stringValue] = schema
        if required, !record.required.contains(key.stringValue) { record.required.append(key.stringValue) }
        slot.schema = .object(properties: record.properties, required: record.required)
    }

    private func probe<T: Decodable>(_ type: T.Type, _ key: Key, required: Bool) throws -> T {
        let child = SchemaSlot()
        let value = try SchemaProbe.decode(T.self, into: child, codingPath: codingPath + [key])
        note(key, child.schema ?? .object(properties: [:], required: []), required: required)
        return value
    }

    func decodeNil(forKey key: Key) throws -> Bool { false }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try probe(T.self, key, required: true) }
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? { try probe(T.self, key, required: false) }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try probe(Bool.self, key, required: true) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try probe(String.self, key, required: true) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try probe(Double.self, key, required: true) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try probe(Int.self, key, required: true) }
    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? { try probe(Bool.self, key, required: false) }
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? { try probe(String.self, key, required: false) }
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? { try probe(Double.self, key, required: false) }
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? { try probe(Int.self, key, required: false) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw ReinsSchemaDerivationError.unsupported("a nested container at \(key.stringValue)")
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw ReinsSchemaDerivationError.unsupported("a nested unkeyed container at \(key.stringValue)")
    }
    func superDecoder() throws -> any Decoder { throw ReinsSchemaDerivationError.unsupported("superDecoder") }
    func superDecoder(forKey key: Key) throws -> any Decoder { throw ReinsSchemaDerivationError.unsupported("superDecoder") }
}

/// An array: reports one element, so its item schema is recorded, then ends.
private struct UnkeyedProbe: UnkeyedDecodingContainer {
    let slot: SchemaSlot
    var codingPath: [any CodingKey]
    var count: Int? { 1 }
    var isAtEnd: Bool { currentIndex >= 1 }
    var currentIndex = 0

    init(slot: SchemaSlot, codingPath: [any CodingKey]) {
        self.slot = slot
        self.codingPath = codingPath
        slot.schema = .array(.object(properties: [:], required: []))
    }

    mutating func decodeNil() throws -> Bool { false }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let child = SchemaSlot()
        let value = try SchemaProbe.decode(T.self, into: child, codingPath: codingPath)
        slot.schema = .array(child.schema ?? .object(properties: [:], required: []))
        currentIndex += 1
        return value
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        throw ReinsSchemaDerivationError.unsupported("a nested container in an array")
    }
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw ReinsSchemaDerivationError.unsupported("a nested array container")
    }
    mutating func superDecoder() throws -> any Decoder { throw ReinsSchemaDerivationError.unsupported("superDecoder") }
}

private struct SingleProbe: SingleValueDecodingContainer {
    let slot: SchemaSlot
    var codingPath: [any CodingKey]
    func decodeNil() -> Bool { false }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try SchemaProbe.decode(T.self, into: slot, codingPath: codingPath) }
    func decode(_ type: Bool.Type) throws -> Bool { try SchemaProbe.decode(Bool.self, into: slot, codingPath: codingPath) }
    func decode(_ type: String.Type) throws -> String { try SchemaProbe.decode(String.self, into: slot, codingPath: codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try SchemaProbe.decode(Double.self, into: slot, codingPath: codingPath) }
    func decode(_ type: Int.Type) throws -> Int { try SchemaProbe.decode(Int.self, into: slot, codingPath: codingPath) }
}

/// Why a schema couldn't be derived.
public enum ReinsSchemaDerivationError: Error, CustomStringConvertible {
    case unsupported(String)
    public var description: String {
        switch self {
        case .unsupported(let what): "the recording decoder doesn't support \(what)"
        }
    }
}
