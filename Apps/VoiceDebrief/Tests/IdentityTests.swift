import CryptoKit
import Foundation
import Security
import Testing
@testable import VoiceDebrief

/// A `UserDefaults` of its own for each test: what a fresh install has.
func freshDefaults() -> UserDefaults {
    let name = "identity-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Identity: the device key")
struct IdentityDeviceKeyTests {
    @Test func itIsMadeOnceAndSigns() throws {
        let store = IdentityMemoryKeyStore()
        let defaults = freshDefaults()
        #expect(IdentityDeviceKey.existing(store: store, defaults: defaults) == nil)
        let first = try IdentityDeviceKey.current(store: store, defaults: defaults, useSecureEnclave: false)
        let second = try IdentityDeviceKey.current(store: store, defaults: defaults, useSecureEnclave: false)
        #expect(first == second)
        #expect(first.keyId.hasPrefix("key-rnd-imm-"))
        #expect(PKI.isFingerprint(first.fingerprint))
        #expect(first.kept == "keychain-this-device")
        let data = Data("a commit".utf8)
        let signature = try first.sign(data)
        #expect(signature.count == 64)
        #expect(PKI.verify(signature: signature, over: data, signPEM: first.publicKeyPEM))
    }

    @Test func itIsKeptForThisDeviceOnly() throws {
        let store = IdentityMemoryKeyStore()
        _ = try IdentityDeviceKey.current(store: store, defaults: freshDefaults(), useSecureEnclave: false)
        #expect(store.names(.thisDeviceOnly) == [IdentityDeviceKey.itemName])
        #expect(store.names(.synchronised).isEmpty)
    }

    /// The Keychain outlives the app; `UserDefaults` does not. A new install finds the old key and no marker.
    @Test func aReinstallWipesIt() throws {
        let store = IdentityMemoryKeyStore()
        let before = try IdentityDeviceKey.current(store: store, defaults: freshDefaults(), useSecureEnclave: false)
        let reinstalled = freshDefaults()
        #expect(IdentityDeviceKey.existing(store: store, defaults: reinstalled) == nil)
        #expect(store.names(.thisDeviceOnly).isEmpty)
        let after = try IdentityDeviceKey.current(store: store, defaults: reinstalled, useSecureEnclave: false)
        #expect(after.fingerprint != before.fingerprint)
        #expect(after.keyId != before.keyId)
        // And an ordinary relaunch, with the marker in place, keeps it.
        #expect(IdentityDeviceKey.existing(store: store, defaults: reinstalled) == after)
        #expect(!IdentityDeviceKey.wipeIfReinstalled(store: store, defaults: reinstalled))
    }
}

@Suite("Identity: vouching")
struct IdentityVouchTests {
    let me = PKIFixtureFiles.identity
    let date = Date(timeIntervalSince1970: 1_794_564_000)           // 13 November 2026, 10:00 UTC

    func device() throws -> IdentityDeviceSigner {
        try IdentityDeviceKey.current(store: IdentityMemoryKeyStore(), defaults: freshDefaults(), useSecureEnclave: false)
    }

    @Test func theStatementSaysWhoseDeviceItIs() throws {
        let device = try device()
        let statement = try IdentityVouch.make(for: device.asVouchDevice, by: me, at: date)
        #expect(statement["type"] == .string("device"))
        #expect(statement["registry"] == .string("voicedebrief.ai/vault"))
        #expect(statement["created_at"] == .string("2026-11-13T10:00:00Z"))
        #expect(statement["signer"] == .string(me.bundle.signingFingerprint))
        #expect(statement["body"]?["from"] == .string("2026-11-13"))
        let checked = try IdentityVouch.check(statement)
        #expect(checked.user == me.bundle)
        #expect(checked.deviceFingerprint == device.fingerprint)
        #expect(checked.keyId == device.keyId)
        #expect(checked.can == ["commit"])
        #expect(IdentityVouch.covers(checked, commitKeyPEM: device.publicKeyPEM))
        #expect(!IdentityVouch.covers(checked, commitKeyPEM: me.bundle.sign))
        #expect(try IdentityVouch.check(file: IdentityVouch.fileData(statement)) == checked)
        #expect(IdentityVouch.path(deviceFingerprint: "sha256:0123456789abcdef") == "identity/devices/sha256-0123456789abcdef.json")
    }

    @Test func aChangedOrBorrowedStatementIsRefused() throws {
        let device = try device()
        let statement = try IdentityVouch.make(for: device.asVouchDevice, by: me, at: date)

        func with(_ change: (inout PKIJSON) -> Void) -> PKIJSON {
            var copy = statement
            change(&copy)
            return copy
        }
        let renamed = with { $0["body"]?["name"] = .string("another device") }
        #expect(throws: IdentityVouch.Failure.badSignature) { try IdentityVouch.check(renamed) }

        // Someone else's bundle put in its place: the signer it names is no longer the key it carries.
        let other = try PKI.generate(label: "other", rsaBits: 2048)
        let borrowed = with { $0["body"]?["bundle"] = other.bundle.asJSON }
        #expect(throws: IdentityVouch.Failure.notTheSigner) { try IdentityVouch.check(borrowed) }

        // Re-signed by the other key, naming itself: it checks, and says it is the other person's.
        var theirs = borrowed
        theirs["record"] = .string(other.bundle.signingFingerprint)
        theirs["signer"] = .string(other.bundle.signingFingerprint)
        let resigned = try PKI.signStatement(theirs, signPKCS8: other.signPKCS8)
        #expect(try IdentityVouch.check(resigned).user == other.bundle)

        let wrongKind = with { $0["type"] = .string("identity") }
        #expect(throws: IdentityVouch.Failure.self) { try IdentityVouch.check(wrongKind) }
        #expect(throws: IdentityVouch.Failure.self) { try IdentityVouch.check(file: Data("{}".utf8)) }
    }
}

@Suite("Identity: the book")
@MainActor
struct IdentityBookTests {
    static func noRegister(_ fingerprint: String) async throws -> PKIBundle { throw PKIError.format("no register in tests") }

    @Test func theUserIdentityIsMadeOnceAndKeptSynchronised() async throws {
        let store = IdentityMemoryKeyStore()
        let book = IdentityBook(store: store, defaults: freshDefaults(), fetchIssuer: Self.noRegister)
        #expect(book.user == nil)
        await book.createUser(label: "  Ada  ", rsaBits: 2048)
        let user = try #require(book.user)
        #expect(book.problem == nil)
        #expect(user.label == "Ada")
        #expect(store.names(.synchronised) == [IdentityBook.userItem])
        #expect(store.names(.thisDeviceOnly).isEmpty)

        await book.createUser(label: "Again", rsaBits: 2048)
        #expect(book.user == user)

        // Another device on the same Apple account: the same synchronised items, its own defaults.
        let elsewhere = IdentityBook(store: store, defaults: freshDefaults(), fetchIssuer: Self.noRegister)
        #expect(elsewhere.user == user)
        #expect(elsewhere.device == nil)

        book.forgetUser()
        #expect(book.user == nil)
        #expect(store.names(.synchronised).isEmpty)
    }

    @Test func vouchingNeedsAUserAndWritesOneCheckedFile() async throws {
        let store = IdentityMemoryKeyStore()
        let book = IdentityBook(store: store, defaults: freshDefaults(), fetchIssuer: Self.noRegister)
        #expect(throws: PKIError.self) { try book.vouchFiles() }
        await book.createUser(label: "Ada", rsaBits: 2048)
        let files = try book.vouchFiles(now: Date(timeIntervalSince1970: 1_794_564_000))
        let device = try #require(book.device)
        #expect(Array(files.keys) == [IdentityVouch.path(deviceFingerprint: device.fingerprint)])
        let checked = try IdentityVouch.check(file: try #require(files.values.first))
        #expect(checked.user == book.user)
        #expect(IdentityVouch.covers(checked, commitKeyPEM: device.publicKeyPEM))
        #expect(store.names(.thisDeviceOnly) == [IdentityDeviceKey.itemName])
    }

    /// The whole optional flow, with a person played by a key made for the test: the app asks, the person
    /// signs a delegation for the app's key, the answer comes back in an address, and the app checks and keeps it.
    @Test func aDelegationFromThePersonIsCheckedAndKept() async throws {
        let person = try PKI.generate(label: "Fixture Person", rsaBits: 2048)
        let store = IdentityMemoryKeyStore()
        let defaults = freshDefaults()
        let book = IdentityBook(store: store, defaults: defaults) { fingerprint in
            guard fingerprint == person.bundle.signingFingerprint else { throw PKIError.format("not in the register") }
            return person.bundle
        }
        await book.createUser(label: "Ada", rsaBits: 2048)
        let now = Date(timeIntervalSince1970: 1_794_564_000)

        let url = try book.beginConnection()
        #expect(url.absoluteString.hasPrefix("https://pki.sgit.ai/authorize/index.html#r="))
        #expect(book.hasPendingRequest)
        let sent = try PKIJSON(parsing: try #require(PKI.data(base64url: String(url.absoluteString.split(separator: "=").last ?? ""))))
        let nonce = try #require(sent["nonce"]?.string)
        let key = try book.delegationKey()
        #expect(sent["key"] == .string(try PKI.keyCode(key)))
        #expect(key.signingFingerprint == book.device?.fingerprint)
        #expect(sent["return"] == .string("https://ios.app.voicedebrief.ai/identity/return/"))

        func answer(_ change: (inout PKIJSON) -> Void = { _ in }, by signer: PKIIdentity) throws -> String {
            var d: PKIJSON = .object([
                "v": .int(1), "kind": .string(PKIDelegation.delegationKind), "iss": .string(person.bundle.signingFingerprint),
                "iss_name": .string("Fixture Person"), "to": .string(key.signingFingerprint), "key": sent["key"] ?? .null,
                "aud": .string(PKIDelegation.client), "can": sent["can"] ?? .null, "from": .string("2026-11-13"), "until": .string("2027-02-11"),
                "check": .string("offline"), "nonce": .string(nonce),
            ])
            change(&d)
            let signed = try PKI.signStatement(d, signPKCS8: signer.signPKCS8)
            let body: PKIJSON = .object(["v": .int(1), "kind": .string(PKIDelegation.authorizedKind), "nonce": .string(nonce), "delegation": signed,
                                         "identity": .object(["fp": .string(person.bundle.signingFingerprint), "name": .string("Fixture Person")])])
            return PKIDelegation.returnAddress + "#pki=" + PKI.base64url(body.data)
        }

        // Signed by somebody who is not the issuer it names.
        await book.finishConnection(try answer(by: PKIFixtureFiles.identity), now: now)
        #expect(book.connection == nil)
        #expect(book.problem?.contains("signature") == true)
        // For another site.
        await book.finishConnection(try answer({ $0["aud"] = .string("https://example.org") }, by: person), now: now)
        #expect(book.connection == nil)
        // An answer nobody asked for.
        await book.finishConnection(try answer({ $0["nonce"] = .string("AAAAAAAAAAAAAAAAAAAAAAAA") }, by: person), now: now)
        #expect(book.connection == nil)
        #expect(book.hasPendingRequest)

        await book.finishConnection(try answer(by: person), now: now)
        #expect(book.problem == nil)
        let checked = try #require(try book.checkedConnection(now: now))
        #expect(checked.issuer == person.bundle.signingFingerprint)
        #expect(checked.to == book.device?.fingerprint)
        #expect(checked.until == "2027-02-11")
        #expect(!checked.issuerIsPinnedRoot)
        #expect(!book.hasPendingRequest)
        #expect(store.names(.synchronised) == [IdentityBook.userItem])           // the delegation stays with the device

        // It is written into a vault beside the vouching statement, and stops checking after its date.
        #expect(try book.vouchFiles(now: now).count == 2)
        #expect(throws: PKIDelegation.Failure.self) { try book.checkedConnection(now: Date(timeIntervalSince1970: 1_900_000_000)) }
        let reopened = IdentityBook(store: store, defaults: defaults, fetchIssuer: Self.noRegister)
        #expect(reopened.connection == book.connection)
        #expect(reopened.connection != nil)
        // A reinstall ends the device key, and the delegation that was for it goes too.
        let reinstalled = IdentityBook(store: store, defaults: freshDefaults(), fetchIssuer: Self.noRegister)
        #expect(reinstalled.connection == nil)
        #expect(reinstalled.device == nil)
        #expect(reinstalled.user == book.user)
    }
}
