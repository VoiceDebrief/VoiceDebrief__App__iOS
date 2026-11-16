import Foundation
import SGitVault
import Testing
@testable import CRM

/// Vault apps and the per-section switch: keys only in the secret store, never in settings.
@MainActor
struct VaultAppsTests {
    func fresh() -> (VaultApps, MemoryStore, UserDefaults) {
        let name = "crm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = MemoryStore()
        return (VaultApps(store: store, defaults: defaults), store, defaults)
    }

    @Test func addSwitchAndRemove() async throws {
        let (apps, store, defaults) = fresh()
        let keyText = VaultCreate.newKeyText()   // a random key made for this test, never used
        let app = try await apps.add(keyText: keyText, name: "Follow-ups lab")
        #expect(app.canWrite)
        #expect(apps.keyText(for: app) == keyText)

        // Settings hold the name and id, never the key.
        let settings = String(decoding: try JSONSerialization.data(withJSONObject: defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("crm.") }.mapValues { "\($0)" }), as: UTF8.self)
        #expect(!settings.contains(keyText))
        #expect(store.get(VaultApps.secretName(app.id)) != nil)

        apps.set(.followUps, to: app)
        #expect(apps.app(for: .followUps) == app)
        #expect(apps.app(for: .people) == nil)

        // Read back as the app would after a restart.
        let again = VaultApps(store: store, defaults: defaults)
        #expect(again.apps == [app])
        #expect(again.app(for: .followUps) == app)

        apps.remove(app)
        #expect(apps.apps.isEmpty)
        #expect(apps.app(for: .followUps) == nil)
        #expect(store.get(VaultApps.secretName(app.id)) == nil)
    }

    @Test func theQRShowsTheReadKeyUnlessAsked() async throws {
        let (apps, _, _) = fresh()
        let keyText = VaultCreate.newKeyText()
        let app = try await apps.add(keyText: keyText, name: "")
        #expect(app.name == "Vault \(app.id)")
        let read = try #require(await apps.shareText(for: app, full: false))
        #expect(read.hasPrefix("sgit_private_read_"))
        #expect(read.hasSuffix(":\(app.id)"))
        #expect(await apps.shareText(for: app, full: true) == keyText)
    }

    @Test func notAKeyAndTwiceAreRefused() async throws {
        let (apps, _, _) = fresh()
        await #expect(throws: VaultApps.Problem.notAKey) { try await apps.add(keyText: "hello", name: "") }
        let keyText = VaultCreate.newKeyText()
        _ = try await apps.add(keyText: keyText, name: "")
        await #expect(throws: VaultApps.Problem.alreadyThere) { try await apps.add(keyText: keyText, name: "") }
    }
}
