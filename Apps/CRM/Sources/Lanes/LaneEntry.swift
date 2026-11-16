import CryptoKit
import Foundation

// lane.entry/1, the append-lane entry the email AgenticCell (AgentiCCells__Cell__Email, docs/plan/lanes.md)
// and the CRM agreed on 16 November 2026: canonical JSON, Ed25519, a hash chain per author and lane.
// The CRM proposes on the actions lane (propose.reply, propose.send, propose.label) and reads the outbox;
// it never sends anything itself.

/// A JSON value with only what lane entries use: integers, never floats.
indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var int: Int? { if case .int(let i) = self { return i } else { return nil } }

    enum ParseError: Error { case notJSON, unsupported(String) }

    static func parse(_ data: Data) throws -> JSONValue {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { throw ParseError.notJSON }
        return try from(any)
    }

    static func from(_ any: Any) throws -> JSONValue {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            guard n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 9e15 else { throw ParseError.unsupported("a number that is not an integer") }
            return .int(n.intValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(try a.map(from))
        case let o as [String: Any]: return .object(try o.mapValues(from))
        default: throw ParseError.unsupported("\(type(of: any))")
        }
    }
}

/// Canonical JSON as the lane's JavaScript writes it: keys sorted by UTF-16 code unit, no whitespace,
/// strings escaped as JSON.stringify does (quote, backslash and control characters only; slash and
/// non-ASCII left as they are), integers only.
enum CanonicalLaneJSON {
    static func data(_ value: JSONValue) -> Data { Data(text(value).utf8) }

    static func text(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .string(let s): quote(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                write(v, into: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, key) in o.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }).enumerated() {
                if i > 0 { out += "," }
                quote(key, into: &out)
                out += ":"
                write(o[key]!, into: &out)
            }
            out += "}"
        }
    }

    private static func quote(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
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

enum LaneEntry {
    static let schema = "lane.entry/1"
    /// The DER prefix of an Ed25519 SubjectPublicKeyInfo; the 32 key bytes follow it.
    static let spkiPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])

    enum Problem: Error, Equatable {
        case notAnEntry, badSignature, keyMismatch, badChain(String)
    }

    /// `ed25519:` and the hex SHA-256 of the key's SPKI DER.
    static func keyID(_ key: Curve25519.Signing.PublicKey) -> String {
        "ed25519:" + hex(SHA256.hash(data: spkiPrefix + key.rawRepresentation))
    }

    /// The bytes that are signed: the canonical JSON of the entry without `sig`.
    static func signedBytes(_ entry: [String: JSONValue]) -> Data {
        var unsigned = entry
        unsigned["sig"] = nil
        return CanonicalLaneJSON.data(.object(unsigned))
    }

    /// `sha256:` and the hex SHA-256 of the canonical JSON of the whole entry, `sig` included.
    static func hash(_ entry: [String: JSONValue]) -> String {
        "sha256:" + hex(SHA256.hash(data: CanonicalLaneJSON.data(.object(entry))))
    }

    /// Checks the signature with `key`, and that the entry names that key.
    static func verify(_ entry: [String: JSONValue], with key: Curve25519.Signing.PublicKey) throws {
        guard entry["schema"]?.string == schema, let sig = entry["sig"]?.string, let signature = base64URLDecode(sig) else {
            throw Problem.notAnEntry
        }
        guard entry["key"]?.string == keyID(key) else { throw Problem.keyMismatch }
        guard key.isValidSignature(signature, for: signedBytes(entry)) else { throw Problem.badSignature }
    }

    /// Checks that entries by one author on one lane run 1, 2, 3 with each `prev` the hash before it.
    static func checkChain(_ entries: [[String: JSONValue]]) throws {
        var previous: [String: JSONValue]?
        for (i, entry) in entries.enumerated() {
            guard entry["seq"]?.int == i + 1 else { throw Problem.badChain("entry \(i + 1) has seq \(entry["seq"]?.int ?? -1)") }
            let expected: JSONValue = previous.map { JSONValue.string(hash($0)) } ?? JSONValue.null
            guard entry["prev"] == expected else { throw Problem.badChain("entry \(i + 1) does not follow the one before") }
            previous = entry
        }
    }

    /// A new signed entry. `previous` is this author's last entry on this lane, or nil for the first.
    static func make(lane: String, author: String, type: String, body: JSONValue, refs: [JSONValue] = [],
                     previous: [String: JSONValue]?, at: Date, signer: Curve25519.Signing.PrivateKey) throws -> [String: JSONValue] {
        var entry: [String: JSONValue] = [
            "schema": .string(schema), "lane": .string(lane), "author": .string(author),
            "seq": .int((previous?["seq"]?.int ?? 0) + 1),
            "prev": previous.map { JSONValue.string(hash($0)) } ?? JSONValue.null,
            "at": .string(ISO8601DateFormatter().string(from: at)),
            "key": .string(keyID(signer.publicKey)), "type": .string(type), "body": body, "refs": .array(refs),
        ]
        let signature = try signer.signature(for: signedBytes(entry))
        entry["sig"] = .string(base64URLEncode(signature))
        return entry
    }

    static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
