import Foundation
import Testing
@testable import SGitPeople

/// Run by `people-interop.yml` only, with `PEOPLE_INTEROP_DIR` set to a folder that pki.sgit.ai's `message.js` and
/// `tools/people/people.py` filled minutes earlier in the same run (`scripts/people-interop/`). Swift opens what they
/// sealed and seals its own, which they then open. Every key in the folder was made for the run and protects nothing.
@Suite("Interop with message.js and people.py", .enabled(if: ProcessInfo.processInfo.environment["PEOPLE_INTEROP_DIR"] != nil))
struct InteropTests {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PEOPLE_INTEROP_DIR"] ?? "/nonexistent")

    func read(_ name: String) throws -> String { try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }
    func write(_ name: String, _ text: String) throws { try Data(text.utf8).write(to: folder.appendingPathComponent(name)) }

    struct KeysJS: Decodable {
        var bundle: PKIBundle
        var encrypt: String
        var sign: String
    }

    func keysJS(_ name: String) throws -> KeysJS { try JSONDecoder().decode(KeysJS.self, from: Data(try read(name).utf8)) }

    /// R: made by keys.js, its private halves (PKCS#8) passed on so that Swift can be R.
    func recipient() throws -> PKIIdentity {
        let r = try keysJS("recipient-r.json")
        let encrypt = try #require(Data(base64Encoded: r.encrypt)), sign = try #require(Data(base64Encoded: r.sign))
        let identity = PKIIdentity(bundle: try PKI.bundle(encryptPKCS8: encrypt, signPKCS8: sign, label: r.bundle.label),
                                   encryptPKCS8: encrypt, signPKCS8: sign, created: Date())
        #expect(identity.bundle.fingerprint == r.bundle.fingerprint)
        return identity
    }

    @Test func swiftOpensWhatMessageJSSealed() throws {
        let r = try recipient()
        let n = try keysJS("msgjs-n.json").bundle
        let envelope = try #require(SealedText.envelope(in: try read("msgjs-to-r.m1")))
        let opened = try PeopleMessage.open(envelope: envelope, me: r, contacts: [n])
        #expect(opened.trust == .contact)
        #expect(opened.message.kind == .text)
        #expect(opened.message.text == "from message.js: é 日本")
        #expect(opened.message.grant == AccessGrant(endpoint: "https://dev.send.sgraph.ai", token: "not-a-real-token", name: "dev"))
    }

    @Test func swiftOpensWhatPeoplePySealedAndReadsItsCard() throws {
        let r = try recipient()
        let card = try ContactCard.parse(try read("people-py-p.card"))
        #expect(card.inbox?.vault == "interop1")
        let envelope = try #require(SealedText.envelope(in: try read("people-py-to-r.m1")))
        let opened = try PeopleMessage.open(envelope: envelope, me: r, contacts: [])
        #expect(opened.trust == .cardInside)
        #expect(opened.card == card)
        #expect(opened.message.text == "from people.py: Zoë")
        #expect(opened.message.replyTo == "note-7")
        #expect(try PeopleMessage.open(envelope: envelope, me: r, contacts: [card.bundle]).trust == .contact)
    }

    @Test func swiftSealsForMessageJSAndPeoplePy() throws {
        let r = try recipient()
        let n = try keysJS("msgjs-n.json").bundle
        let secret = SharedSecret(id: "swift-1", kind: .accessKey, name: "dev", value: "not-a-real-token", server: "https://dev.send.sgraph.ai")
        let toN = PeopleMessage(kind: .secret, from: r.bundle.signingFingerprint, to: n.signingFingerprint, secret: secret)
        try write("swift-to-msgjs.m1", try toN.sealedText(to: n, from: r))

        let myCard = try ContactCard.make(name: "Swift (throwaway)", identity: r,
                                          inbox: InboxAddress(vault: "swiftinbox", append: String(repeating: "ab", count: 24)))
        try write("swift-r.card", try myCard.text())
        let p = try ContactCard.parse(try read("people-py-p.card"))
        let toP = PeopleMessage(kind: .card, from: r.bundle.signingFingerprint, to: p.signingFingerprint, replyTo: "note-7",
                                card: try myCard.text())
        try write("swift-to-p.lane", try toP.lanePayload(to: p.bundle, from: r))
    }
}
