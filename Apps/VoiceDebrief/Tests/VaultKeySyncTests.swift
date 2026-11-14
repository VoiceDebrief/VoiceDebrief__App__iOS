import Foundation
import Testing
import SGitVault
@testable import VoiceDebrief

/// Vault keys, servers and tokens in iCloud Keychain (issue 017). A `MemoryCloud` stands for iCloud
/// Keychain: two devices given the same one are signed in to the same account. Nothing here can show
/// that Apple's Keychain carries an item between two real devices.
@Suite("Keys in iCloud Keychain")
@MainActor
struct VaultKeySyncTests {
    static let prefixes = [VaultBook.vaultPrefix, VaultBook.serverPrefix, VaultBook.tokenPrefix]

    static func shared(_ store: MemoryStore) -> [String] {
        store.names(.synchronised).sorted()
    }

    @Test func keysAreSharedByDefaultAndTheSigningKeyNeverIs() async throws {
        let device = Device(server: nil)
        let book = device.book
        #expect(book.keysInICloud)
        await book.create(name: "Notes")
        let vault = try #require(book.vaults.first)
        let remote = try #require(book.addRemote(name: "S", address: "https://server.example", token: "secret-token"))
        _ = try book.commitSigner()

        #expect(Self.shared(device.store) == [VaultBook.tokenName(remote.id), VaultBook.serverPrefix + remote.id,
                                              VaultBook.vaultPrefix + vault.id].sorted())
        #expect(device.store.get("commit-signer", .thisDeviceOnly) != nil)
        #expect(device.store.get("commit-signer", .synchronised) == nil)
        #expect(device.store.get(VaultBook.stateName, .synchronised) == nil)
        #expect(device.store.get(SharedSecrets.stateName, .synchronised) == nil)
        // This device keeps its own copy of each, and the two agree.
        for name in Self.shared(device.store) {
            #expect(device.store.get(name, .thisDeviceOnly) == device.store.get(name, .synchronised))
        }
        #expect(book.keyHome(of: vault) == "In iCloud Keychain, on your devices")
        // What travels with the key says nothing about this device's copy of the vault.
        let record = String(decoding: try #require(device.store.get(VaultBook.vaultPrefix + vault.id, .synchronised)), as: UTF8.self)
        #expect(record.contains(vault.keyText))
        #expect(!record.contains("onDevice"))
        #expect(!record.contains("localHead"))
    }

    @Test func aVaultMadeOnOneDeviceAppearsOnAnotherAndIsCopiedThere() async throws {
        let cloud = MemoryCloud()
        let server = Device.folder("server")
        let phone = Device(server: server, cloud: cloud).book
        await phone.create(name: "Notes")
        let vault = try #require(phone.vaults.first)
        _ = try await phone.save(run: VaultBookTests.run(), audioURL: nil, to: vault)

        // A second device, signed in to the same account: the key is there, the vault is not.
        let pad = Device(server: server, cloud: cloud).book
        let arrived = try #require(pad.vaults.first)
        #expect(arrived.id == vault.id)
        #expect(arrived.name == "Notes")
        #expect(arrived.canWrite)
        #expect(!arrived.onDevice)
        #expect(!arrived.createdHere)
        #expect(pad.status(of: arrived) == "On another of your devices only: not yet pushed to a server")
        #expect(pad.remotes.isEmpty)

        // The first device adds a server and pushes. The server, its token and the vault's server arrive too.
        let remote = try #require(phone.addRemote(name: "S", address: "https://server.example", token: "t"))
        phone.setRemote(remote.id, for: vault)
        await phone.push(vault)
        #expect(phone.problem == nil)
        pad.refreshKeys()
        #expect(pad.remotes == [remote])
        #expect(pad.hasToken(remote))
        #expect(pad.status(of: arrived) == "On S only, not kept on this device")
        await pad.pull(arrived)
        #expect(pad.problem == nil)
        #expect(pad.current(arrived).onDevice)
        #expect(try await pad.contents(of: arrived).files.count == 3)

        // Each device signs with its own key, and writes from the second reach the first through the server.
        #expect(try pad.commitSigner().keyId != phone.commitSigner().keyId)
        _ = try await pad.save(run: VaultBookTests.run("From the iPad."), audioURL: nil, to: arrived)
        await pad.push(arrived)
        #expect(pad.current(arrived).pushProblem == nil)
        await phone.pull(vault)
        let both = try await phone.contents(of: vault)
        #expect(both.files.count == 6)
        #expect(both.history.allSatisfy { $0.signature.isVerified })
        // What is true of one device stayed on it.
        #expect(phone.current(vault).createdHere)
        #expect(!pad.current(arrived).createdHere)
    }

    @Test func twoDevicesAddingVaultsAtTheSameTimeBothKeepBoth() async throws {
        let cloud = MemoryCloud()
        let phone = Device(server: nil, cloud: cloud).book
        let pad = Device(server: nil, cloud: cloud).book
        await phone.create(name: "From the phone")
        await pad.create(name: "From the iPad")
        #expect(phone.vaults.count == 1)
        #expect(pad.vaults.count == 1)
        phone.refreshKeys()
        pad.refreshKeys()
        #expect(Set(phone.vaults.map(\.name)) == ["From the phone", "From the iPad"])
        #expect(Set(pad.vaults.map(\.name)) == ["From the phone", "From the iPad"])
        #expect(phone.vaults.filter(\.onDevice).map(\.name) == ["From the phone"])
        #expect(pad.vaults.filter(\.onDevice).map(\.name) == ["From the iPad"])
    }

    @Test func forgettingAVaultOnOneDeviceNeitherTakesItFromAnotherNorBringsItBack() async throws {
        let cloud = MemoryCloud()
        let phone = Device(server: nil, cloud: cloud)
        let pad = Device(server: nil, cloud: cloud)
        await pad.book.create(name: "Notes")
        let vault = try #require(pad.book.vaults.first)
        phone.book.refreshKeys()
        #expect(phone.book.vaults.count == 1)

        phone.book.remove(try #require(phone.book.vaults.first))
        #expect(phone.book.vaults.isEmpty)
        #expect(phone.store.get(VaultBook.vaultPrefix + vault.id, .synchronised) == nil)

        // The device that holds the vault keeps it, on this device only, and does not put the key back.
        pad.book.refreshKeys()
        #expect(pad.book.vaults.count == 1)
        #expect(pad.book.keyHome(of: vault) == "On this device only (removed from iCloud Keychain by another device)")
        #expect(try await pad.book.contents(of: vault).head.signature.isVerified)
        pad.book.refreshKeys()
        _ = try await pad.book.save(run: VaultBookTests.run(), audioURL: nil, to: vault)
        #expect(pad.store.get(VaultBook.vaultPrefix + vault.id, .synchronised) == nil)
        phone.book.refreshKeys()
        #expect(phone.book.vaults.isEmpty)

        // A new launch on either device changes nothing.
        let again = VaultBook(store: pad.store, localRoot: pad.book.localRoot, cacheRoot: pad.book.cacheRoot)
        #expect(again.vaults.count == 1)
        #expect(pad.store.get(VaultBook.vaultPrefix + vault.id, .synchronised) == nil)
    }

    @Test func turningItOffMovesEverythingBackToThisDeviceAndOnPutsItBack() async throws {
        let device = Device(server: nil)
        let book = device.book
        await book.create(name: "First")
        let first = try #require(book.vaults.first)
        let remote = try #require(book.addRemote(name: "S", address: "https://server.example", token: "t"))
        #expect(Self.shared(device.store).count == 3)

        book.setKeysInICloud(false)
        #expect(!book.keysInICloud)
        #expect(Self.shared(device.store).isEmpty)
        #expect(book.vaults.map(\.id) == [first.id])
        #expect(book.remotes == [remote])
        #expect(book.hasToken(remote))
        #expect(book.keyHome(of: first) == "On this device only")
        #expect(try await book.contents(of: first).head.signature.isVerified)

        // What is made while it is off stays here, and a new launch keeps the choice.
        await book.create(name: "Second")
        book.setToken("u", for: remote)
        #expect(Self.shared(device.store).isEmpty)
        let again = VaultBook(store: device.store, localRoot: book.localRoot, cacheRoot: book.cacheRoot)
        #expect(!again.keysInICloud)
        #expect(again.vaults.count == 2)
        #expect(Self.shared(device.store).isEmpty)

        again.setKeysInICloud(true)
        #expect(again.keysInICloud)
        #expect(Self.shared(device.store).count == 4)
        #expect(again.vaults.count == 2)
        #expect(device.store.get(VaultBook.tokenName(remote.id), .synchronised) == Data("u".utf8))
    }

    @Test func turningItOffOnOneDeviceLeavesTheOtherWithItsKeys() async throws {
        let cloud = MemoryCloud()
        let phone = Device(server: nil, cloud: cloud)
        let pad = Device(server: nil, cloud: cloud)
        await phone.book.create(name: "Notes")
        let vault = try #require(phone.book.vaults.first)
        pad.book.refreshKeys()
        #expect(pad.book.vaults.count == 1)

        phone.book.setKeysInICloud(false)
        #expect(cloud === phone.store.cloud)
        #expect(Self.shared(phone.store).isEmpty)
        pad.book.refreshKeys()
        #expect(pad.book.vaults.map(\.id) == [vault.id])
        #expect(pad.store.get(VaultBook.vaultPrefix + vault.id, .thisDeviceOnly) != nil)
        #expect(Self.shared(pad.store).isEmpty)
    }

    @Test func whatAnEarlierBuildKeptInOneListBecomesAnItemEachAndIsShared() async throws {
        // What the first build with servers left: every vault in one item, every server in another, a token.
        let store = MemoryStore()
        let remote = VaultRemote(id: "abcd1234", name: "S", url: try #require(URL(string: "https://server.example")))
        let onDevice = SavedVault(id: "aaaa1111", name: "Here", keyText: VaultCreate.newKeyText(), addedAt: Date(timeIntervalSince1970: 1_000),
                                  createdHere: true, onDevice: true, remoteId: remote.id, localHead: "two", remoteHead: "one",
                                  syncedAt: Date(timeIntervalSince1970: 2_000), pushProblem: "HTTP 401 for batch")
        let onServer = SavedVault(id: "bbbb2222", name: "There", keyText: VaultCreate.newKeyText(), addedAt: Date(timeIntervalSince1970: 3_000),
                                  createdHere: false, onDevice: false, remoteId: remote.id)
        store.set("vaults", try JSONEncoder().encode([onDevice, onServer]))
        store.set("remotes", try JSONEncoder().encode([remote]))
        store.set(VaultBook.tokenName(remote.id), Data("t".utf8))

        let book = VaultBook(store: store, localRoot: Device.folder("a"), cacheRoot: Device.folder("b"))
        #expect(book.vaults == [onDevice, onServer])
        #expect(book.remotes == [remote])
        #expect(book.hasToken(remote))
        #expect(store.get("vaults") == nil)
        #expect(store.get("remotes") == nil)
        #expect(Self.shared(store) == [VaultBook.tokenName(remote.id), VaultBook.serverPrefix + remote.id,
                                       VaultBook.vaultPrefix + "aaaa1111", VaultBook.vaultPrefix + "bbbb2222"].sorted())
        // A second launch reads the same, from the items.
        let again = VaultBook(store: store, localRoot: Device.folder("a"), cacheRoot: Device.folder("b"))
        #expect(again.vaults == [onDevice, onServer])
        #expect(again.remotes == [remote])
    }

    @Test func aChangeMadeOnAnotherDeviceIsTaken() throws {
        let cloud = MemoryCloud()
        let here = SharedSecrets(store: MemoryStore(cloud: cloud), prefixes: ["vault-"])
        let there = SharedSecrets(store: MemoryStore(cloud: cloud), prefixes: ["vault-"])
        here.set("vault-a", Data("one".utf8))
        here.set("other", Data("not ours".utf8))
        #expect(there.reconcile())
        #expect(there.get("vault-a") == Data("one".utf8))
        #expect(there.names("vault-") == ["vault-a"])
        #expect(!there.reconcile())
        there.set("vault-a", Data("two".utf8))
        #expect(here.reconcile())
        #expect(here.get("vault-a") == Data("two".utf8))
        #expect(here.home(of: "vault-a") == .synchronised)
        #expect(here.store.get("other", .synchronised) == nil)
    }

    @Test func theSwitchSaysWhatItDoes() {
        #expect(VaultsView.keysFooter(inICloud: true).contains("Not yet confirmed between two devices"))
        #expect(VaultsView.keysFooter(inICloud: true).contains("never leaves it"))
        #expect(VaultsView.keysFooter(inICloud: false).contains("on this device only"))
    }
}
