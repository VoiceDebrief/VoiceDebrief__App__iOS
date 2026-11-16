import CryptoKit
import Foundation
import Testing
@testable import CRM

/// lane.entry/1 against the email AgenticCell's test vector (invented; its private key was thrown away),
/// checked here and, before it was committed, with Python's json and cryptography.
struct LaneEntryTests {
    static let publicKeyDER = "MCowBQYDK2VwAyEAQrdQ7whieyBEgYjg7+uMqEPpSee0Xu37DXV8JrrDWto="
    static let vector = #"{"schema":"lane.entry/1","lane":"actions","author":"person:example","seq":1,"prev":null,"at":"2026-11-16T10:00:00Z","key":"ed25519:4ecda7bc316f574fc1dea607eb167d69c7d1748b81fe0e3c19b1f4688fbdc9b4","type":"propose.reply","body":{"client_ref":"crm-draft-1","email":{"in_reply_to":"m-0012","to":["rui@example.com"],"cc":[],"bcc":[],"subject":"Re: Reunião","text":"Olá Rui,\n\nAté quinta.","language":"pt","attachments":[]}},"refs":[],"sig":"NWKFZVR_UiyM8t4mF4zus10GdmAK0zVzc4V-bTTctwZMZg1HwSBDmsKrSl3nRbLY1ZgNNv0XxCKp7OqrPtwXDA"}"#

    func entry() throws -> [String: JSONValue] {
        guard case .object(let o) = try JSONValue.parse(Data(Self.vector.utf8)) else { throw LaneEntry.Problem.notAnEntry }
        return o
    }

    func publicKey() throws -> Curve25519.Signing.PublicKey {
        let der = try #require(Data(base64Encoded: Self.publicKeyDER))
        #expect(der.prefix(12) == LaneEntry.spkiPrefix)
        return try Curve25519.Signing.PublicKey(rawRepresentation: der.dropFirst(12))
    }

    @Test func theSignedBytesMatchTheVector() throws {
        let bytes = LaneEntry.signedBytes(try entry())
        #expect(LaneEntry.hex(SHA256.hash(data: bytes)) == "2b147c0da087ca4c981d652b5aa56104402dcd4be1fb04dfe52114b4c777bacd")
        // Non-ASCII stays raw and the newline is \n.
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains(#""text":"Olá Rui,\n\nAté quinta.""#))
        #expect(!text.contains("\"sig\""))
    }

    @Test func theKeyTheHashAndTheSignature() throws {
        let e = try entry()
        let key = try publicKey()
        #expect(LaneEntry.keyID(key) == "ed25519:4ecda7bc316f574fc1dea607eb167d69c7d1748b81fe0e3c19b1f4688fbdc9b4")
        #expect(LaneEntry.hash(e) == "sha256:870bb0cc18abc7f4fd27dd645a93978f43d5b1bdee354efe81bbb61863ff20f4")
        try LaneEntry.verify(e, with: key)
    }

    @Test func aChangedEntryFailsItsSignature() throws {
        var e = try entry()
        e["type"] = .string("propose.send")
        #expect(throws: LaneEntry.Problem.badSignature) { try LaneEntry.verify(e, with: try publicKey()) }
        let other = Curve25519.Signing.PrivateKey().publicKey
        #expect(throws: LaneEntry.Problem.keyMismatch) { try LaneEntry.verify(try entry(), with: other) }
    }

    @Test func escapingAsJSONStringifyDoes() {
        #expect(CanonicalLaneJSON.text(.string("a/b \"q\" \\ \u{01} \t é")) == #""a/b \"q\" \\ \u0001 \t é""#)
        #expect(CanonicalLaneJSON.text(.object(["b": .int(2), "a": .null, "B": .bool(true)])) == #"{"B":true,"a":null,"b":2}"#)
    }

    @Test func entriesWeMakeVerifyAndChain() throws {
        let signer = Curve25519.Signing.PrivateKey()
        let body: JSONValue = .object(["client_ref": .string("crm-draft-2"), "email": .object(["to": .array([.string("ana@example.org")]), "subject": .string("Hello")])])
        let first = try LaneEntry.make(lane: "actions", author: "person:owner", type: "propose.send", body: body,
                                       previous: nil, at: Invented.summit, signer: signer)
        let second = try LaneEntry.make(lane: "actions", author: "person:owner", type: "propose.label", body: .object([:]),
                                        previous: first, at: Invented.later, signer: signer)
        try LaneEntry.verify(first, with: signer.publicKey)
        try LaneEntry.verify(second, with: signer.publicKey)
        #expect(second["seq"] == .int(2))
        #expect(second["prev"] == .string(LaneEntry.hash(first)))
        try LaneEntry.checkChain([first, second])
        #expect(throws: LaneEntry.Problem.self) { try LaneEntry.checkChain([second, first]) }
        // What is written reads back the same.
        let reread = try JSONValue.parse(CanonicalLaneJSON.data(.object(second)))
        #expect(reread == .object(second))
    }
}
