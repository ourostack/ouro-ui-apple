import Foundation

/// A JSON value that keeps its objects' key order, so what this package writes matches what core's reference resolver
/// writes (JavaScript's `JSON.stringify`) byte for byte, which is how the conformance cases are checked.
public enum A2UIJSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([A2UIJSON])
    case object(A2UIObject)

    /// Reads JSON text. Throws ``A2UIJSONError`` on anything that isn't one JSON value.
    public static func parse(_ data: Data) throws -> A2UIJSON {
        var p = Parser(bytes: Array(data))
        p.space()
        let v = try p.value()
        p.space()
        guard p.i == p.bytes.count else { throw A2UIJSONError(offset: p.i, reason: "text after the value") }
        return v
    }

    public static func parse(_ text: String) throws -> A2UIJSON { try parse(Data(text.utf8)) }

    /// Compact JSON, as JavaScript's `JSON.stringify(value)` writes it.
    public var serialized: String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += A2UIJSON.numberText(n)
        case .string(let s): A2UIJSON.quote(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, (k, v)) in o.pairs.enumerated() {
                if i > 0 { out += "," }
                A2UIJSON.quote(k, into: &out)
                out += ":"
                v.write(to: &out)
            }
            out += "}"
        }
    }

    /// JavaScript's `String(n)`: 4, not 4.0; 0.5; 1e-7; 1e+21.
    public static func numberText(_ n: Double) -> String {
        if n.isNaN || n.isInfinite { return "null" }
        if n == 0 { return "0" }
        if n.rounded() == n, abs(n) < 1e21 { return String(format: "%.0f", n) }
        let d = "\(n)"
        guard let e = d.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return d }
        var mantissa = String(d[..<e])
        if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
        var exp = String(d[d.index(after: e)...])
        let negative = exp.hasPrefix("-")
        exp = String(exp.drop(while: { $0 == "-" || $0 == "+" }).drop(while: { $0 == "0" }))
        return "\(mantissa)e\(negative ? "-" : "+")\(exp.isEmpty ? "0" : exp)"
    }

    private static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    // MARK: Reading values

    public subscript(key: String) -> A2UIJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; return nil }
    public var array: [A2UIJSON]? { if case .array(let a) = self { return a }; return nil }
    public var object: A2UIObject? { if case .object(let o) = self { return o }; return nil }
    public var isObject: Bool { object != nil }
}

/// A JSON object's members in the order they were written; setting an existing key keeps its place, as in JavaScript.
public struct A2UIObject: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    public private(set) var pairs: [(String, A2UIJSON)] = []

    public init() {}
    public init(dictionaryLiteral elements: (String, A2UIJSON)...) { for (k, v) in elements { self[k] = v } }

    public var keys: [String] { pairs.map(\.0) }
    public var count: Int { pairs.count }
    public var isEmpty: Bool { pairs.isEmpty }

    public subscript(key: String) -> A2UIJSON? {
        get { pairs.first(where: { $0.0 == key })?.1 }
        set {
            if let i = pairs.firstIndex(where: { $0.0 == key }) {
                if let newValue { pairs[i].1 = newValue } else { pairs.remove(at: i) }
            } else if let newValue {
                pairs.append((key, newValue))
            }
        }
    }

    public static func == (a: A2UIObject, b: A2UIObject) -> Bool {
        a.pairs.count == b.pairs.count && zip(a.pairs, b.pairs).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

public struct A2UIJSONError: Error, Sendable, CustomStringConvertible {
    public let offset: Int
    public let reason: String
    public var description: String { "not JSON at byte \(offset): \(reason)" }
}

private struct Parser {
    let bytes: [UInt8]
    var i = 0

    mutating func space() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    func fail(_ reason: String) -> A2UIJSONError { A2UIJSONError(offset: i, reason: reason) }

    mutating func literal(_ word: String, _ v: A2UIJSON) throws -> A2UIJSON {
        let w = Array(word.utf8)
        guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { throw fail("expected \(word)") }
        i += w.count
        return v
    }

    mutating func value() throws -> A2UIJSON {
        guard i < bytes.count else { throw fail("unexpected end") }
        switch bytes[i] {
        case UInt8(ascii: "{"):
            i += 1
            var o = A2UIObject()
            space()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(o) }
            while true {
                space()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
                let k = try string()
                space()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected :") }
                i += 1
                space()
                o[k] = try value()
                space()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(o) }
                throw fail("expected , or }")
            }
        case UInt8(ascii: "["):
            i += 1
            var a: [A2UIJSON] = []
            space()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
            while true {
                space()
                a.append(try value())
                space()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                throw fail("expected , or ]")
            }
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): return try literal("true", .bool(true))
        case UInt8(ascii: "f"): return try literal("false", .bool(false))
        case UInt8(ascii: "n"): return try literal("null", .null)
        default:
            let start = i
            while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
            guard i > start, let n = Double(String(decoding: bytes[start..<i], as: UTF8.self)) else { throw fail("expected a value") }
            return .number(n)
        }
    }

    mutating func string() throws -> String {
        i += 1
        var units: [UInt16] = []
        var raw: [UInt8] = []
        func flush() { units.append(contentsOf: String(decoding: raw, as: UTF8.self).utf16); raw.removeAll() }
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "\"") {
                i += 1
                flush()
                return String(decoding: units, as: UTF16.self)
            }
            if b == UInt8(ascii: "\\") {
                flush()
                i += 1
                guard i < bytes.count else { break }
                let e = bytes[i]
                i += 1
                switch e {
                case UInt8(ascii: "n"): units.append(0x0A)
                case UInt8(ascii: "r"): units.append(0x0D)
                case UInt8(ascii: "t"): units.append(0x09)
                case UInt8(ascii: "b"): units.append(0x08)
                case UInt8(ascii: "f"): units.append(0x0C)
                case UInt8(ascii: "u"):
                    guard i + 4 <= bytes.count, let u = UInt16(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16) else { throw fail("bad \\u escape") }
                    units.append(u)
                    i += 4
                default: units.append(UInt16(e))
                }
                continue
            }
            raw.append(b)
            i += 1
        }
        throw fail("unterminated string")
    }
}
