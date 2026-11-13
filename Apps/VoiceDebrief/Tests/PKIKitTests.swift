import CryptoKit
import Foundation
import Testing
@testable import VoiceDebrief

/// The fixtures in `Tests/PKIFixtures/`: from the test bundle, or beside this file when they were not copied into it.
enum PKIFixtureFiles {
    static func data(_ name: String) throws -> Data {
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: name, withExtension: "json") ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "PKIFixtures") {
                return try Data(contentsOf: url)
            }
        }
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("PKIFixtures/\(name).json")
        return try Data(contentsOf: beside)
    }

    /// One throwaway identity for the whole test run: RSA 2048, because 4096 takes seconds on a simulator.
    /// `pki-interop.yml` makes and proves a 4096-bit one on every change.
    static let identity: PKIIdentity = {
        // swiftlint:disable:next force_try
        try! PKI.generate(label: "Test “é” 日本", rsaBits: 2048, now: Date(timeIntervalSince1970: 1_794_564_000))
    }()
}

@Suite("PKIKit: keys and the bundle")
struct PKIKeyTests {
    let me = PKIFixtureFiles.identity

    @Test func aNewIdentityIsSoundApartFromItsTestSize() throws {
        #expect(PKI.problems(of: me.bundle) == ["the encryption key is 2048-bit; sgit makes 4096"])
        #expect(PKI.isFingerprint(me.bundle.fingerprint))
        #expect(PKI.isFingerprint(me.bundle.signingFingerprint))
        #expect(me.bundle.fingerprint != me.bundle.signingFingerprint)
        #expect(me.bundle.encrypt.hasPrefix("-----BEGIN PUBLIC KEY-----\n"))
        #expect(me.bundle.encrypt.hasSuffix("\n-----END PUBLIC KEY-----\n"))
        #expect(me.bundle.sign.split(separator: "\n").allSatisfy { $0.count <= 64 })
    }

    @Test func thePublicHalvesAreRecomputedFromThePrivateOnes() throws {
        #expect(try PKI.bundle(encryptPKCS8: me.encryptPKCS8, signPKCS8: me.signPKCS8, label: me.bundle.label) == me.bundle)
    }

    @Test func theRSAPrivateKeyIsPKCS8AroundPKCS1() throws {
        let outer = try PKIDER.one(Array(me.encryptPKCS8)).children()
        #expect(outer.count == 3)
        #expect(outer[0] == PKIDER(tag: 0x02, content: [0]))
        #expect(try outer[1].children().first?.content == [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
        #expect(outer[2].tag == 0x04)
        let inner = try PKIDER.one(outer[2].content).children()
        #expect(inner.count == 9)                                   // RSAPrivateKey: version, n, e, d, p, q, dP, dQ, qInv
        #expect(inner[2].content == [0x01, 0x00, 0x01])             // e = 65537
    }

    @Test func theBundleIsWrittenAsSgitExportsIt() throws {
        let text = me.bundle.json
        #expect(text.hasPrefix("{\n  \"v\": 1,\n  \"encrypt\": \"-----BEGIN PUBLIC KEY-----\\n"))
        let back = try PKIBundle(json: try PKIJSON(parsing: Data(text.utf8)))
        #expect(back == me.bundle)
        let coded = try JSONDecoder().decode(PKIBundle.self, from: Data(text.utf8))
        #expect(coded == me.bundle)
    }

    @Test func aBundleWithTheWrongFingerprintIsNoticed() {
        var wrong = me.bundle
        wrong.fingerprint = "sha256:0000000000000000"
        #expect(PKI.problems(of: wrong).contains("fingerprint is not the encryption key's"))
        var swapped = me.bundle
        swapped.sign = me.bundle.encrypt
        #expect(PKI.problems(of: swapped) == ["the signing key is not an ECDSA P-256 public key"])
        var old = me.bundle
        old.v = 2
        #expect(PKI.problems(of: old) == ["not a v1 public-key bundle"])
    }

    @Test func fingerprintsHaveOneShape() {
        #expect(PKI.isFingerprint("sha256:db7f79fdd87e030a"))
        #expect(!PKI.isFingerprint("sha256:DB7F79FDD87E030A"))
        #expect(!PKI.isFingerprint("sha256:db7f79fdd87e030"))
        #expect(!PKI.isFingerprint("db7f79fdd87e030a"))
        #expect(!PKI.isFingerprint("sha256:db7f79fdd87e030g"))
    }

    @Test func theKeyCodeGoesThereAndBack() throws {
        let code = try PKI.keyCode(me.bundle)
        #expect(code.hasPrefix("k1.MII"))
        #expect(!code.contains("=") && !code.contains("+") && !code.contains("/"))
        #expect(PKI.parseKeyCode(code) == me.bundle)
        #expect(PKI.parseKeyCode("see https://pki.sgit.ai/send/#\(code) please") == me.bundle)
        #expect(PKI.parseKeyCode("k1.abc.def.ghi") == nil)
        #expect(PKI.parseKeyCode("nothing here") == nil)
        var unnamed = me.bundle
        unnamed.label = ""
        #expect(PKI.parseKeyCode(try PKI.keyCode(unnamed)) == unnamed)
    }

    @Test func base64urlHasNoPaddingAndRefusesOtherCharacters() {
        for n in 0..<40 {
            let bytes = Data((0..<n).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 251) })
            let text = PKI.base64url(bytes)
            #expect(!text.contains("="))
            #expect(PKI.data(base64url: text) == bytes)
        }
        #expect(PKI.data(base64url: "ab+/") == nil)
        #expect(PKI.data(base64url: "ab cd") == nil)
    }

    /// The register's root, as pki.sgit.ai publishes it: a real key this code did not make.
    @Test func theRegistersRootIsTheOnePinned() throws {
        let file = try PKIFixtureFiles.data("pki-fixture-root")
        let bundle = try IdentityBook.issuerBundle(inRegisterFile: file, fingerprint: PKIDelegation.pinnedRoot)
        #expect(bundle.signingFingerprint == "sha256:db7f79fdd87e030a")
        #expect(bundle.fingerprint == "sha256:d642edaf9176db9f")
        #expect(PKI.problems(of: bundle).isEmpty)
        let code = try #require(try PKIJSON(parsing: file)["key"]?.string)
        #expect(PKI.parseKeyCode(code) == bundle)
        #expect(throws: PKIError.self) { try IdentityBook.issuerBundle(inRegisterFile: file, fingerprint: "sha256:0000000000000000") }
    }
}

@Suite("PKIKit: DER")
struct PKIDERTests {
    @Test func lengthsAreCheckedAgainstTheBytesThatAreThere() throws {
        #expect(try PKIDER.one([0x04, 0x02, 0xAA, 0xBB]) == PKIDER(tag: 0x04, content: [0xAA, 0xBB]))
        #expect(try PKIDER.one([0x30, 0x00]).children().isEmpty)
        #expect(throws: PKIError.self) { try PKIDER.one([0x04, 0x03, 0xAA, 0xBB]) }          // says three, holds two
        #expect(throws: PKIError.self) { try PKIDER.one([0x04, 0x01, 0xAA, 0xBB]) }          // a byte left over
        #expect(throws: PKIError.self) { try PKIDER.one([0x04]) }
        #expect(throws: PKIError.self) { try PKIDER.one([]) }
        #expect(throws: PKIError.self) { try PKIDER.one([0x04, 0x80]) }                      // indefinite length
        #expect(throws: PKIError.self) { try PKIDER.one([0x04, 0x85, 1, 1, 1, 1, 1]) }       // a length of five bytes
        #expect(throws: PKIError.self) { try PKIDER.one([0x1F, 0x01, 0x00]) }                // a long tag
        #expect(throws: PKIError.self) { try PKIDER.one([0x04, 0x00]).children() }           // not constructed
    }

    @Test func longLengthsRead() throws {
        let body = [UInt8](repeating: 7, count: 300)
        let encoded = DERReader.encode(tag: 0x04, body)
        #expect(Array(encoded.prefix(4)) == [0x04, 0x82, 0x01, 0x2C])
        #expect(try PKIDER.one(encoded).content == body)
    }

    /// No cut-off or changed key may crash the reader: it throws, or reads something else.
    @Test func aDamagedKeyNeverCrashes() {
        let me = PKIFixtureFiles.identity
        for key in [me.signPKCS8, me.encryptPKCS8.prefix(200)] {
            let bytes = Array(key)
            for cut in 0..<min(bytes.count, 140) {
                _ = try? PKIDER.one(Array(bytes.prefix(cut)))
                _ = try? PKI.signingKey(pkcs8: Data(bytes.prefix(cut)))
                var flipped = bytes
                flipped[cut] ^= 0xFF
                _ = try? PKIDER.one(flipped).children()
                _ = try? LaneCrypto.privateKey(pkcs8: Data(flipped))
            }
        }
        #expect(throws: PKIError.self) { try PKI.rsaSPKI(fromPKCS8: me.signPKCS8) }
        #expect(throws: PKIError.self) { try PKI.signingKey(pkcs8: me.encryptPKCS8) }
    }
}

@Suite("PKIKit: signatures and statements")
struct PKISignatureTests {
    let me = PKIFixtureFiles.identity

    @Test func aSignatureIsSixtyFourBytesAndVerifies() throws {
        let data = Data("a note".utf8)
        let signature = try PKI.sign(data, signPKCS8: me.signPKCS8)
        #expect(signature.count == 64)
        #expect(PKI.verify(signature: signature, over: data, signPEM: me.bundle.sign))
        #expect(!PKI.verify(signature: signature, over: Data("a note.".utf8), signPEM: me.bundle.sign))
        #expect(!PKI.verify(signature: signature.dropLast(), over: data, signPEM: me.bundle.sign))
        #expect(!PKI.verify(signature: signature, over: data, signPEM: me.bundle.encrypt))
    }

    @Test func aDetachedSignatureIsSgitsFile() throws {
        let data = Data("report".utf8)
        let sig = try PKI.detachedSignature(over: data, by: me)
        #expect(sig.hasPrefix("{\n  \"signature\": \""))
        #expect(sig.hasSuffix("\",\n  \"fingerprint\": \"\(me.bundle.signingFingerprint)\"\n}"))
        #expect(PKI.verifyDetached(sig, over: data, by: me.bundle))
        #expect(!PKI.verifyDetached(sig, over: Data("reports".utf8), by: me.bundle))
        var other = me.bundle
        other.signingFingerprint = "sha256:0000000000000000"
        #expect(!PKI.verifyDetached(sig, over: data, by: other))
        #expect(!PKI.verifyDetached("not json", over: data, by: me.bundle))
    }

    @Test func canonicalFormIsSortedCompactAndEscapedAsJavaScriptDoes() throws {
        let value = try PKIJSON(parsing: Data(#"{"b": 1, "a": [true, null, "x\ny", {"z": -3, "é": "\u0001"}], "": "/"}"#.utf8))
        #expect(value.canonical == #"{"":"/","a":[true,null,"x\ny",{"z":-3,"é":"\u0001"}],"b":1}"#)
        #expect(PKIJSON.quote("a\"b\\c\u{08}\u{0C}\t\r\u{1F}\u{7F}\u{2028}") == #""a\"b\\c\b\f\t\r\u001f"# + "\u{7F}\u{2028}\"")
        #expect(throws: PKIError.self) { try PKIJSON(parsing: Data("{\"n\": 1.5}".utf8)) }
        #expect(throws: PKIError.self) { try PKIJSON(parsing: Data("{".utf8)) }
        #expect(try PKIJSON(parsing: Data("{\"t\": true, \"n\": 1}".utf8)) == .object(["t": .bool(true), "n": .int(1)]))
    }

    @Test func aStatementIsSignedWithoutItsSigAndChecked() throws {
        let statement: PKIJSON = .object(["v": .int(1), "type": .string("note"), "body": .object(["text": .string("hello")]), "sig": .string("stale")])
        #expect(String(decoding: PKI.canonicalBytes(statement), as: UTF8.self) == "{\"body\":{\"text\":\"hello\"},\"type\":\"note\",\"v\":1}\n")
        let signed = try PKI.signStatement(statement, signPKCS8: me.signPKCS8)
        #expect(PKI.verifyStatement(signed, signPEM: me.bundle.sign))
        #expect(!PKI.verifyStatement(statement, signPEM: me.bundle.sign))
        var changed = signed
        changed["type"] = .string("other")
        #expect(!PKI.verifyStatement(changed, signPEM: me.bundle.sign))
        #expect(PKI.statementId(signed).hasPrefix("sha256:") && PKI.statementId(signed).count == 71)
        #expect(PKI.statementId(signed) != PKI.statementId(changed))
    }
}

@Suite("PKIKit: the envelope and private keys at rest")
struct PKIEnvelopeTests {
    let me = PKIFixtureFiles.identity

    @Test func aSignedEnvelopeOpensAndNamesItsSigner() throws {
        let text = Data("for your eyes".utf8)
        let enc = try PKI.seal(text, to: me.bundle, signedBy: me)
        let json = try #require(Data(base64Encoded: enc))
        #expect(String(decoding: json, as: UTF8.self).hasPrefix("{\"v\": 2, \"w\": \""))
        let known = try PKI.unseal(enc, encryptPKCS8: me.encryptPKCS8, signers: [me.bundle])
        #expect(known == PKIOpened(bytes: text, signed: true, signer: me.bundle.signingFingerprint, verified: true))
        let unknown = try PKI.unseal(enc, encryptPKCS8: me.encryptPKCS8)
        #expect(unknown.signed && unknown.verified == nil)                  // not checked is not forged
        let plain = try PKI.unseal(try PKI.seal(text, to: me.bundle), encryptPKCS8: me.encryptPKCS8, signers: [me.bundle])
        #expect(plain == PKIOpened(bytes: text, signed: false, signer: nil, verified: nil))
        #expect(try LaneCrypto.decrypt(enc, with: LaneCrypto.privateKey(pkcs8: me.encryptPKCS8)) == text)
    }

    @Test func anEnvelopeForSomeoneElseDoesNotOpen() throws {
        let other = try PKI.generate(label: "other", rsaBits: 2048)
        let enc = try PKI.seal(Data("x".utf8), to: other.bundle)
        #expect(throws: PKIError.self) { try PKI.unseal(enc, encryptPKCS8: me.encryptPKCS8) }
        #expect(throws: PKIError.self) { try PKI.unseal("not an envelope", encryptPKCS8: me.encryptPKCS8) }
        #expect(throws: PKIError.self) { try PKI.unseal(enc, encryptPKCS8: me.signPKCS8) }
    }

    @Test func aPrivateKeyUnderAPassphraseComesBack() throws {
        for key in [me.signPKCS8, me.encryptPKCS8] {
            let pem = try PKI.encryptPrivate(key, passphrase: "correct horse", iterations: 1000)
            #expect(pem.hasPrefix("-----BEGIN ENCRYPTED " + "PRIVATE KEY-----\n"))
            #expect(try PKI.decryptPrivate(pem, passphrase: "correct horse") == key)
            #expect(throws: PKIError.self) { try PKI.decryptPrivate(pem, passphrase: "correct horse ") }
            #expect(throws: PKIError.self) { try PKI.decryptPrivate(pem, passphrase: "") }
        }
        #expect(throws: PKIError.self) { try PKI.encryptPrivate(me.signPKCS8, passphrase: "") }
        #expect(try PKI.decryptPrivate(PKI.pem(me.signPKCS8, label: "PRIVATE " + "KEY"), passphrase: "") == me.signPKCS8)
        #expect(throws: PKIError.self) { try PKI.decryptPrivate(me.bundle.sign, passphrase: "x") }
    }

    @Test func aKeyStoreIsFiveFilesThatReadBack() throws {
        let store = try PKI.keystoreFiles(me, passphrase: "pass")
        #expect(store.folder == me.bundle.fingerprint.replacingOccurrences(of: ":", with: "_"))
        #expect(Set(store.files.keys) == ["metadata.json", "private_key.pem", "public_key.pem", "signing_private.pem", "signing_public.pem"])
        let back = try PKI.importKeystore(privateKeyPEM: try #require(store.files["private_key.pem"]),
                                          signingPrivatePEM: try #require(store.files["signing_private.pem"]), passphrase: "pass", label: me.bundle.label)
        #expect(back.bundle == me.bundle)
        #expect(back.signPKCS8 == me.signPKCS8)
        let metadata = try PKIJSON(parsing: Data(try #require(store.files["metadata.json"]).utf8))
        #expect(metadata["encryption_fingerprint"] == .string(me.bundle.fingerprint))
        #expect(metadata["signing_fingerprint"] == .string(me.bundle.signingFingerprint))
    }
}

/// What sgit and pki.sgit.ai's keys.js made, read by Swift. The same checks `pki-interop.yml` runs against
/// files made in the run; here against the public halves committed in `Tests/PKIFixtures/`, so the checks
/// that need a private key (opening an envelope, a key under a passphrase) are the workflow's alone.
@Suite("PKIKit: fixtures made by sgit and by keys.js")
struct PKIFixtureTests {
    @Test func whatKeysJSMadeReads() throws {
        let fixture = try PKIFixtureChecks.load(try PKIFixtureFiles.data("pki-fixture-keysjs"))
        let done = try PKIFixtureChecks.keysjs(fixture)
        #expect(done.count == 5)
    }

    @Test func whatSgitMadeReads() throws {
        let fixture = try PKIFixtureChecks.load(try PKIFixtureFiles.data("pki-fixture-sgit"))
        let done = try PKIFixtureChecks.sgit(fixture)
        #expect(done.count == 3)
    }
}
