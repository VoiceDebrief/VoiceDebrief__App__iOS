import Foundation

/// A JSON value that keeps integers, booleans and null apart, so a decrypted commit
/// can be re-serialised byte-for-byte as sgit signs it.
public indirect enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        self = .object(try c.decode([String: JSONValue].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

/// sgit's commit signing input (`Vault__Commit.signing_bytes`): the stored commit JSON
/// without `signature` and `user_signature`, keys sorted, no whitespace, UTF-8, non-ASCII
/// unescaped. For the value types a commit holds this equals RFC 8785 (JCS) and Python's
/// `json.dumps(sort_keys=True, separators=(',', ':'), ensure_ascii=False)`.
public enum CanonicalJSON {
    public static let signatureMembers: Set<String> = ["signature", "user_signature"]

    public static func signingBytes(commitJSON: Data) throws -> Data {
        let value = try JSONDecoder().decode(JSONValue.self, from: commitJSON)
        guard case .object(var members) = value else {
            throw VaultError.malformed(path: "commit", detail: "not a JSON object")
        }
        for name in signatureMembers { members.removeValue(forKey: name) }
        return Data(serialize(.object(members)).utf8)
    }

    public static func serialize(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if d == d.rounded(), abs(d) < 1e15 { out += String(Int64(d)) + ".0" } else { out += String(d) }
        case .string(let s): writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, item) in a.enumerated() {
                if i > 0 { out += "," }
                write(item, into: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            // Python sorts str keys by code point; compare unicode scalar values the same way.
            let keys = o.keys.sorted { a, b in
                a.unicodeScalars.map(\.value).lexicographicallyPrecedes(b.unicodeScalars.map(\.value))
            }
            for (i, key) in keys.enumerated() {
                if i > 0 { out += "," }
                writeString(key, into: &out)
                out += ":"
                write(o[key]!, into: &out)
            }
            out += "}"
        }
    }

    /// Python's json string escaping with ensure_ascii=False.
    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
