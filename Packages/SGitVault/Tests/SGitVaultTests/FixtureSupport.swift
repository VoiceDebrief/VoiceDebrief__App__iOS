import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// The fixture vaults in Tests/Fixtures, made by generate_fixtures.py with sgit-ai 0.27.0.
/// Their keys are THROWAWAY test keys: these vaults exist on no server.
struct Fixture: Sendable {
    struct FileExpectation: Decodable, Sendable {
        let size: Int
        let sha256: String
        let text: String?
    }
    struct BranchExpectation: Decodable, Sendable {
        let messages: [String]
        let files: [String: FileExpectation]
    }
    struct Expected: Decodable, Sendable {
        let vault_id: String
        let vault_key: String
        let read_key: String
        let read_key_hex: String
        let write_key_hex: String
        let branch_index_file_id: String
        let ref_file_id: String
        let deflate: Bool
        let objects_on_server: Int
        let branches: [String: BranchExpectation]
    }

    let name: String
    let expected: Expected
    /// The folder laid out as the server holds the vault (bare/…).
    let server: URL

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // SGitVaultTests
        .deletingLastPathComponent()      // Tests
        .appending(path: "Fixtures", directoryHint: .isDirectory)

    static let plain = Fixture(named: "plain")
    static let deflate = Fixture(named: "deflate")
    static let all = [plain, deflate]

    init(named name: String) {
        self.name = name
        let dir = Self.root.appending(path: name, directoryHint: .isDirectory)
        let data = try! Data(contentsOf: dir.appending(path: "expected.json"))
        self.expected = try! JSONDecoder().decode(Expected.self, from: data)
        self.server = dir.appending(path: "server", directoryHint: .isDirectory)
    }

    var readKey: SymmetricKey { SymmetricKey(data: Data(hexString: expected.read_key_hex)!) }
    var address: VaultAddress { VaultAddress(vaultId: expected.vault_id) }

    /// A writable copy of the server folder, for tamper tests.
    func copyOfServer() throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appending(path: "sgitvault-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: server, to: dest)
        return dest
    }

    func objects(in server: URL? = nil) throws -> [URL] {
        let dir = (server ?? self.server).appending(path: "bare/data", directoryHint: .isDirectory)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    }
}

func temporaryCache() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "sgitvault-cache-\(UUID().uuidString)",
                                                      directoryHint: .isDirectory)
}

@MainActor
func openVault(_ fixture: Fixture, branch: String = "current", server: URL? = nil, cache: URL? = nil,
               readKey: SymmetricKey? = nil, log: VaultTrafficLog = VaultTrafficLog(),
               requireSignatures: Bool = false, trust: VaultTrust? = nil) -> SGitVault {
    SGitVault(address: fixture.address, readKey: readKey ?? fixture.readKey, cache: cache ?? temporaryCache(),
              log: log, transport: FolderVaultTransport(root: server ?? fixture.server), branch: branch,
              requireSignatures: requireSignatures, trust: trust)
}

func sha256Hex(_ data: Data) -> String { Data(SHA256.hash(data: data)).hexString }

func flipByte(at url: URL, offset: Int) throws {
    var data = try Data(contentsOf: url)
    let i = min(offset, data.count - 1)
    data[i] ^= 0x01
    try data.write(to: url)
}
