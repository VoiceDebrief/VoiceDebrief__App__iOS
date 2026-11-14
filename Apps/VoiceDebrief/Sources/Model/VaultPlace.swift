import Foundation

/// Where a vault is, as a kind, for its symbol and colour. The words stay `VaultBook.status(of:)`'s;
/// this follows the same branches in the same order, so the two cannot disagree.
enum VaultPlace: Equatable, Sendable {
    /// Its key arrived from another device that has not pushed it anywhere.
    case anotherDevice
    /// On its server, not kept here.
    case serverOnly
    case thisDeviceOnly
    case pushFailed
    case notYetPushed
    case inStep
    case ahead

    static func of(_ vault: SavedVault) -> VaultPlace {
        guard vault.onDevice else { return vault.remoteId == nil ? .anotherDevice : .serverOnly }
        guard vault.remoteId != nil else { return .thisDeviceOnly }
        if vault.pushProblem != nil { return .pushFailed }
        guard let remoteHead = vault.remoteHead else { return .notYetPushed }
        return remoteHead == vault.localHead ? .inStep : .ahead
    }
}
