import CryptoKit
import Foundation
import Security
import SGitPeople
import Testing
@testable import VoiceDebrief

/// Sites (R7, tier 1), checked against the formats of the site's own `/send/` page (send.js and keyring.js of
/// Site__Organisation__Chiswick-Cheese-Market at 65002f9). INTERIM: there is no recorded exchange with a keeper yet
/// (no replies/ folder at that commit), so the keys and the reply here are made inside the test, by the algorithm
/// keyring.js states. They are to be replaced by the keeper's recorded demo request and reply when account C sends them.
@Suite("Sites: talking to a site's keeper")
struct SiteSendTests {
    static func b64u(_ d: Data) -> String { PKI.base64url(d) }

    /// A person key link as the keeper's person-key.mjs issues it: `#key=` base64url JSON {p, f, e: [d,x,y], s: [d,x,y]}.
    static func keyLink(enc: P256.KeyAgreement.PrivateKey, sig: P256.Signing.PrivateKey, person: String = "test-person",
                        fingerprint: String = "sha256:00112233aabbccdd", site: String = "https://example.com") -> String {
        func parts(_ d: Data, _ x963: Data) -> [String] { [b64u(d), b64u(x963.dropFirst().prefix(32)), b64u(x963.suffix(32))] }
        let packed: [String: Any] = ["p": person, "f": fingerprint,
                                     "e": parts(enc.rawRepresentation, enc.publicKey.x963Representation),
                                     "s": parts(sig.rawRepresentation, sig.publicKey.x963Representation)]
        let json = try! JSONSerialization.data(withJSONObject: packed)
        return "\(site)/send/#key=\(b64u(json))"
    }

    /// A reply sealed as the keeper seals one: ws-ecies-1.
    static func seal(_ reply: [String: String], to enc: P256.KeyAgreement.PublicKey, key fingerprint: String) throws -> SitePersonKey.Envelope {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: enc)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data("ws-ecies-1".utf8), outputByteCount: 32)
        let box = try AES.GCM.seal(try JSONSerialization.data(withJSONObject: reply), using: key)
        let x963 = ephemeral.publicKey.x963Representation
        return SitePersonKey.Envelope(v: 1, to: "test-person", key: fingerprint, at: reply["at"],
                                      epk: .init(kty: "EC", crv: "P-256", x: b64u(x963.dropFirst().prefix(32)), y: b64u(x963.suffix(32))),
                                      iv: Data(box.nonce).base64EncodedString(), ct: (box.ciphertext + box.tag).base64EncodedString())
    }

    static func rsa() throws -> (SecKey, String) {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
        return (key, LaneCrypto.pem(spki: LaneCrypto.spki(fromPKCS1: pkcs1)))
    }

    static func inbox(pem: String) throws -> SiteInbox {
        let spki = try PKI.publicDER(pem)
        return SiteInbox(agent: "keeper.test", site: "test", endpoint: "https://dev.send.sgraph.ai", vault_id: "testvault",
                         append_token: "not-a-real-token", recipient: .init(fingerprint: LaneCrypto.fingerprint(spki: spki), signing_fingerprint: nil, encrypt: pem))
    }

    @Test func theKindsAreTheSitesOwn() {
        #expect(SiteSend.kinds.map(\.id) == ["words", "look", "link", "picture", "other"])
        #expect(SiteSend.kinds.map(\.id).contains(SiteSend.defaultKind))
    }

    @Test func aKeyLinkIsTakenAndAChangedOneIsNot() throws {
        let enc = P256.KeyAgreement.PrivateKey(), sig = P256.Signing.PrivateKey()
        let link = Self.keyLink(enc: enc, sig: sig)
        let key = try SitePersonKey.from(link: "Scan me: " + link)
        #expect(key.person == "test-person")
        #expect(key.fingerprint == "sha256:00112233aabbccdd")
        #expect(key.signing.publicKey.rawRepresentation == sig.publicKey.rawRepresentation)
        // A link whose public point does not belong to its private key is refused (a key changed on the way).
        let other = Self.keyLink(enc: enc, sig: P256.Signing.PrivateKey())
        let swapped = try #require(other.split(separator: "=").last)
        let mixedData = try #require(PKI.data(base64url: String(swapped)))
        let mixed = try #require(String(data: mixedData, encoding: .utf8))
        var object = try #require(try JSONSerialization.jsonObject(with: Data(mixed.utf8)) as? [String: Any])
        var s = try #require(object["s"] as? [String])
        s[0] = Self.b64u(P256.Signing.PrivateKey().rawRepresentation)
        object["s"] = s
        let bad = Self.b64u(try JSONSerialization.data(withJSONObject: object))
        #expect(throws: SiteSend.Failure.badKey) { try SitePersonKey.from(link: "https://example.com/send/#key=" + bad) }
        #expect(throws: SiteSend.Failure.notAKeyLink) { try SitePersonKey.from(link: "hello") }
    }

    @Test func aRequestIsTheSitesOwnShapeSignedOverItsItems() throws {
        let enc = P256.KeyAgreement.PrivateKey(), sig = P256.Signing.PrivateKey()
        let key = try SitePersonKey.from(link: Self.keyLink(enc: enc, sig: sig))
        let (_, pem) = try Self.rsa()
        let data = try key.request(kind: "words", text: "Make the header green", inbox: try Self.inbox(pem: pem),
                                   site: "https://example.com", at: Date(timeIntervalSince1970: 1_795_000_000))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "ccm.request/v1")
        #expect(object["to"] as? String == "keeper.test")
        #expect(object["from"] as? String == "test-person")
        #expect((object["sent_at"] as? String)?.hasSuffix(".000Z") == true)
        let signed = try #require(object["signed"] as? [String: String])
        #expect(signed["alg"] == "ECDSA-P256-SHA256-P1363")
        #expect(signed["key"] == "sha256:00112233aabbccdd")
        let items = try #require(object["items_json"] as? String)
        let sigText = try #require(signed["sig"])
        let sigData = try #require(Data(base64Encoded: sigText))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: sigData)
        #expect(sig.publicKey.isValidSignature(signature, for: Data(items.utf8)))
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(items.utf8)) as? [String: Any])
        #expect(parsed["kind"] as? String == "words")
        #expect(parsed["text"] as? String == "Make the header green")
        #expect((parsed["images"] as? [Any])?.isEmpty == true)
    }

    @Test func theSealedRequestOpensWithTheKeepersKey() throws {
        let key = try SitePersonKey.from(link: Self.keyLink(enc: P256.KeyAgreement.PrivateKey(), sig: P256.Signing.PrivateKey()))
        let (privateKey, pem) = try Self.rsa()
        let inbox = try Self.inbox(pem: pem)
        let request = try key.request(kind: "words", text: "hello", inbox: inbox, site: "https://example.com", at: Date())
        let lane = try inbox.lane()
        #expect(lane.vault == "testvault")
        // What the lane carries: base64 of the v2 envelope, the same as send.js's btoa(seal(...)).
        let enc = try LaneCrypto.encrypt(request, to: try LaneCrypto.publicKey(pem: lane.publicKeyPEM))
        let payload = LaneCrypto.lanePayload(encText: enc)
        let envelope = try #require(try JSONSerialization.jsonObject(with: Data(base64Encoded: try LaneCrypto.encText(fromLaneContent: payload)) ?? Data()) as? [String: Any])
        #expect(envelope["v"] as? Int == 2)
        #expect(try LaneCrypto.decrypt(try LaneCrypto.encText(fromLaneContent: payload), with: privateKey) == request)
    }

    @Test func aReplySealedToThePersonOpensAndOneForAnotherDoesNot() throws {
        let enc = P256.KeyAgreement.PrivateKey()
        let key = try SitePersonKey.from(link: Self.keyLink(enc: enc, sig: P256.Signing.PrivateKey()))
        let envelope = try Self.seal(["at": "2026-11-26T10:00:00Z", "re": "r1", "text": "Done: the header is green."],
                                     to: enc.publicKey, key: key.fingerprint)
        // As it travels: JSON, in an array, at replies/<person>.json.
        let wire = try JSONEncoder().encode([envelope])
        let back = try JSONDecoder().decode([SitePersonKey.Envelope].self, from: wire)
        let reply = try JSONDecoder().decode(SiteReply.self, from: try key.open(back[0]))
        #expect(reply.text == "Done: the header is green.")
        #expect(reply.re == "r1")
        let forOther = try Self.seal(["text": "x"], to: P256.KeyAgreement.PrivateKey().publicKey, key: "sha256:ffffffffffffffff")
        #expect(throws: SiteSend.Failure.sealedToAnotherKey("sha256:ffffffffffffffff")) { try key.open(forOther) }
        let wrongKeySameName = try Self.seal(["text": "x"], to: P256.KeyAgreement.PrivateKey().publicKey, key: key.fingerprint)
        #expect(throws: SiteSend.Failure.cannotOpen) { try key.open(wrongKeySameName) }
    }

    @MainActor @Test func aSiteIsAddedFromItsQRCodeAndItsAnswersAndChangesAreSeen() async throws {
        let enc = P256.KeyAgreement.PrivateKey()
        let link = Self.keyLink(enc: enc, sig: P256.Signing.PrivateKey(), site: "https://site.example.com")
        let (_, pem) = try Self.rsa()
        let inboxData = try JSONEncoder().encode(try Self.inbox(pem: pem))
        let reply = try JSONEncoder().encode([try Self.seal(["at": "2026-11-26T10:00:00Z", "text": "On it."], to: enc.publicKey, key: "sha256:00112233aabbccdd")])
        let page = Page()
        let desk = SitesDesk(folder: FileManager.default.temporaryDirectory.appending(path: "sites-\(UUID().uuidString)"),
                             keys: IdentityMemoryKeyStore()) { request in
            let path = request.url?.path ?? ""
            let body: Data? = path == "/send/inbox.json" ? inboxData : path == "/send/replies/test-person.json" ? reply : path == "/" ? page.html : nil
            let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
            return (body ?? Data(), response)
        }
        let site = try #require(await desk.add(link: link))
        #expect(site.origin == "https://site.example.com")
        #expect(desk.sites.count == 1)
        #expect(try desk.key(for: site).person == "test-person")
        await desk.check(site)
        #expect(desk.replies[site.origin]?.first?.text == "On it.")
        #expect(desk.unseen[site.origin] == 1)
        #expect(!desk.changed.contains(site.origin))
        page.html = Data("<h1>Green now</h1>".utf8)
        await desk.check(site)
        #expect(desk.changed.contains(site.origin))
        desk.markSeen(site)
        #expect(desk.unseen[site.origin] == 0)
    }

    final class Page: @unchecked Sendable { var html = Data("<h1>Cheese</h1>".utf8) }
}
