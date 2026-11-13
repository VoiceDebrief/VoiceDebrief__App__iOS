import Foundation

/// JSON with ordered members, printed as Python's `json.dumps(obj)` prints it by default:
/// `", "` and `": "` separators, `ensure_ascii=True` (non-ASCII as `\uXXXX`, lowercase hex).
/// sgit stores trees, commits, refs and keys this way. Matching it byte for byte keeps tree ids
/// identical to the ones sgit computes, so unchanged folders deduplicate across both writers.
public indirect enum PythonJSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case string(String)
    case array([PythonJSON])
    case object([(String, PythonJSON)])

    public static func == (a: PythonJSON, b: PythonJSON) -> Bool { a.dumps() == b.dumps() }
    public func hash(into hasher: inout Hasher) { hasher.combine(dumps()) }

    public static func str(_ s: String?) -> PythonJSON { s.map { .string($0) } ?? .null }

    public func dumps() -> String {
        var out = ""
        write(into: &out)
        return out
    }

    public var data: Data { Data(dumps().utf8) }

    private func write(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .string(let s): Self.writeString(s, into: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += ", " }
                item.write(into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, (key, value)) in members.enumerated() {
                if i > 0 { out += ", " }
                Self.writeString(key, into: &out)
                out += ": "
                value.write(into: &out)
            }
            out += "}"
        }
    }

    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for unit in s.utf16 {
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            default: out += String(format: "\\u%04x", unit)
            }
        }
        out += "\""
    }

    /// From a decoded JSON value. Member order: `order` first (when present), then the rest by key.
    public init(_ value: JSONValue, order: [String] = []) {
        switch value {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .int(let i): self = .int(i)
        case .double(let d): self = .string(String(d))      // sgit's index and commits hold no floats
        case .string(let s): self = .string(s)
        case .array(let a): self = .array(a.map { PythonJSON($0, order: order) })
        case .object(let o):
            let first = order.filter { o[$0] != nil }
            let rest = o.keys.filter { !order.contains($0) }.sorted()
            self = .object((first + rest).map { ($0, PythonJSON(o[$0]!, order: order)) })
        }
    }
}
