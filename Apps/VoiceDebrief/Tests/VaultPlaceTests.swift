import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Where a vault is, as a kind")
struct VaultPlaceTests {
    /// The same states, in the same order, as VaultBookTests' status line test.
    @Test func followsTheStatusLine() {
        var vault = SavedVault(id: "abcd1234", name: "a", keyText: "k", addedAt: Date(), createdHere: true)
        #expect(VaultPlace.of(vault) == .anotherDevice)
        vault.remoteId = "r"
        #expect(VaultPlace.of(vault) == .serverOnly)
        vault.remoteId = nil
        vault.onDevice = true
        #expect(VaultPlace.of(vault) == .thisDeviceOnly)
        vault.remoteId = "r"
        vault.localHead = "one"
        #expect(VaultPlace.of(vault) == .notYetPushed)
        vault.remoteHead = "one"
        #expect(VaultPlace.of(vault) == .inStep)
        vault.localHead = "two"
        #expect(VaultPlace.of(vault) == .ahead)
        vault.pushProblem = "HTTP 401 for batch"
        #expect(VaultPlace.of(vault) == .pushFailed)
    }
}
