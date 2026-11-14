import Foundation
import SGitVault
import Testing
@testable import SGit

@Suite("The same vaults on every device")
@MainActor
struct SyncTests {
    private func shelf(_ cloud: MemoryCloud, server: URL) throws -> VaultShelf {
        let root = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        return VaultShelf(store: MemoryStore(cloud: cloud), transport: FolderVaultTransport(root: server),
                          cacheRoot: root.appending(path: "cache"), localRoot: root.appending(path: "local"))
    }

    @Test func aVaultOnTheServerReachesTheOtherDeviceAndOneOnlyHereDoesNot() async throws {
        UserDefaults.standard.removeObject(forKey: VaultShelf.syncKeysSetting)
        let cloud = MemoryCloud()
        let server = FileManager.default.temporaryDirectory.appending(path: "sync-server-\(UUID().uuidString)")
        let phone = try shelf(cloud, server: server)
        let shared = try #require(await phone.create(name: "Shared"))
        _ = try #require(await phone.create(name: "Only here"))
        #expect(await phone.sendToServer(shared))
        let ipad = try shelf(cloud, server: server)
        #expect(ipad.vaults.map(\.name) == ["Shared"])
        #expect(ipad.vaults.first?.onDevice == false)
    }

    @Test func theAccessKeyTravelsAndForgettingTakesTheKeyOutOfICloud() async throws {
        UserDefaults.standard.removeObject(forKey: VaultShelf.syncKeysSetting)
        let cloud = MemoryCloud()
        let server = FileManager.default.temporaryDirectory.appending(path: "sync-server-\(UUID().uuidString)")
        let phone = try shelf(cloud, server: server)
        phone.setToken("sample-token")
        let shared = try #require(await phone.create(name: "Shared"))
        #expect(await phone.sendToServer(shared))
        let mac = try shelf(cloud, server: server)
        #expect(mac.hasToken)
        phone.remove(phone.current(shared))
        let later = try shelf(cloud, server: server)
        #expect(later.vaults.isEmpty)
        #expect(mac.vaults.count == 1)
    }

    @Test func aVaultAddedElsewhereArrivesWhenTheAppComesToTheFront() async throws {
        UserDefaults.standard.removeObject(forKey: VaultShelf.syncKeysSetting)
        let cloud = MemoryCloud()
        let server = FileManager.default.temporaryDirectory.appending(path: "sync-server-\(UUID().uuidString)")
        let phone = try shelf(cloud, server: server)
        let ipad = try shelf(cloud, server: server)
        let made = try #require(await phone.create(name: "Later"))
        #expect(await phone.sendToServer(made))
        #expect(ipad.vaults.isEmpty)
        await ipad.refreshFromOtherDevices()
        #expect(ipad.vaults.map(\.name) == ["Later"])
    }
}
