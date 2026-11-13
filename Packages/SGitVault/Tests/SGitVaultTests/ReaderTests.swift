import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

@MainActor
final class ReaderTests: XCTestCase {

    func testReadsEveryFileOfEveryBranch() async throws {
        for fixture in Fixture.all {
            for (branch, want) in fixture.expected.branches {
                let vault = openVault(fixture, branch: branch)
                try await vault.pull()
                let files = try await vault.files()
                XCTAssertEqual(Set(files.map(\.path)), Set(want.files.keys), "\(fixture.name)/\(branch)")
                for file in files {
                    let expected = try XCTUnwrap(want.files[file.path])
                    XCTAssertEqual(file.size, expected.size, file.path)
                    let data = try await vault.read(file.path)
                    XCTAssertEqual(data.count, expected.size, file.path)
                    XCTAssertEqual(sha256Hex(data), expected.sha256, "\(fixture.name)/\(branch)/\(file.path)")
                    if let text = expected.text {
                        XCTAssertEqual(String(decoding: data, as: UTF8.self), text, file.path)
                    }
                }
            }
        }
    }

    func testTreeWalkNestedFoldersAndUnicodeNames() async throws {
        let vault = openVault(.plain)
        let maybeRoot = try await vault.tree()
        let root = try XCTUnwrap(maybeRoot)
        XCTAssertEqual(root.children.filter(\.isFolder).map(\.name), ["docs", "notes"])
        let docs = try XCTUnwrap(root.children.first { $0.name == "docs" })
        let deep = try XCTUnwrap(docs.children.first { $0.name == "deep" })
        XCTAssertEqual(deep.children.map(\.path), ["docs/deep/note.txt"])
        XCTAssertEqual(docs.size, 11_400 + 10)
        let text = try await vault.readText("notes/ünïcode name.md")
        XCTAssertEqual(text, "Olá, Lisboa.\n")
        let total = Fixture.plain.expected.branches["current"]!.files.values.reduce(0) { $0 + $1.size }
        XCTAssertEqual(root.size, total)
    }

    func testHistoryMessagesAndSignatures() async throws {
        for fixture in Fixture.all {
            for (branch, want) in fixture.expected.branches {
                let vault = openVault(fixture, branch: branch)
                let history = try await vault.history(limit: 50)
                XCTAssertEqual(history.map(\.message), want.messages, "\(fixture.name)/\(branch)")
                for commit in history {
                    XCTAssertTrue(commit.signature.isVerified, "\(commit.message): \(commit.signature)")
                }
                let limited = try await vault.history(limit: 1)
                XCTAssertEqual(limited.map(\.message), [want.messages[0]])
            }
        }
    }

    func testMultiBranchIndex() async throws {
        let vault = openVault(.plain)
        try await vault.pull()
        let branches = await vault.branches
        XCTAssertEqual(branches.count, 4)
        XCTAssertEqual(Set(branches.filter { $0.type == .named }.map(\.name)), ["current", "device-ipad"])
        XCTAssertEqual(branches.filter { $0.type == .clone }.count, 2)

        let missing = openVault(.plain, branch: "no-such-branch")
        do {
            try await missing.pull()
            XCTFail("expected branchNotFound")
        } catch VaultError.branchNotFound(let name) {
            XCTAssertEqual(name, "no-such-branch")
        }
    }

    func testDeflatedBlobAnd32HexIds() async throws {
        let fixture = Fixture.deflate
        let deflated = try fixture.objects().filter { url in
            (try? Data(contentsOf: url))?.prefix(5) == VaultCrypto.deflateMagic
        }
        XCTAssertEqual(deflated.count, 1, "the fixture holds one deflated blob (docs/big.txt)")

        let log = VaultTrafficLog()
        let vault = openVault(fixture, log: log)
        let head = try await vault.pull()
        XCTAssertEqual(VaultCrypto.objectIdWidth(head.commitId), 32)
        let format = await vault.format
        XCTAssertEqual(format?.format, 2)
        XCTAssertEqual(format?.features.contains("blob-deflate"), true)

        let bigFiles = try await vault.files()

        let big = try XCTUnwrap(bigFiles.first { $0.path == "docs/big.txt" })
        XCTAssertEqual(big.blobId, deflated.first?.lastPathComponent)
        let data = try await vault.read("docs/big.txt")
        XCTAssertEqual(sha256Hex(data), fixture.expected.branches["current"]!.files["docs/big.txt"]!.sha256)
        XCTAssertTrue(log.events.contains { $0.kind == .decrypt && $0.detail.contains("deflate") })

        // The plain vault is format 1 with 12-hex ids and no deflated blobs.
        let plain = openVault(.plain)
        let plainHead = try await plain.pull()
        XCTAssertEqual(VaultCrypto.objectIdWidth(plainHead.commitId), 12)
    }

    func testCacheServesObjectsButNeverRefs() async throws {
        let cache = temporaryCache()
        let firstLog = VaultTrafficLog()
        let first = openVault(.plain, cache: cache, log: firstLog)
        try await first.pull()
        _ = try await first.read("README.md")
        let firstObjectRequests = firstLog.events.filter { $0.kind == .request && $0.path.hasPrefix("bare/data/") }
        XCTAssertGreaterThan(firstObjectRequests.count, 0)

        let secondLog = VaultTrafficLog()
        let second = openVault(.plain, cache: cache, log: secondLog)
        try await second.pull()
        _ = try await second.read("README.md")
        let requests = secondLog.events.filter { $0.kind == .request }
        XCTAssertTrue(requests.allSatisfy { !$0.path.hasPrefix("bare/data/") }, "objects come from the cache")
        XCTAssertTrue(requests.contains { $0.path.hasPrefix("bare/refs/") }, "the ref is always fetched")
        XCTAssertTrue(requests.contains { $0.path.hasPrefix("bare/indexes/") }, "the index is always fetched")
        XCTAssertGreaterThan(secondLog.events.filter { $0.kind == .cacheHit }.count, 0)

        let stats = await second.cacheStats()
        XCTAssertGreaterThan(stats.objects, 0)
        XCTAssertGreaterThan(stats.hitRate, 0)
        let cached = try FileManager.default.contentsOfDirectory(atPath: cache.appending(path: "fixtplain1").path)
        XCTAssertFalse(cached.contains { $0.hasPrefix("ref-") || $0.hasPrefix("idx-") })
    }

    func testIncrementalPullFetchesOnlyNewObjects() async throws {
        let log = VaultTrafficLog()
        let vault = openVault(.plain, log: log)
        try await vault.pull()
        let unchanged = log.events.count
        try await vault.pull()                                 // same head: ref only
        let second = log.events.prefix(log.events.count - unchanged)
        XCTAssertEqual(second.filter { $0.kind == .request && $0.path.hasPrefix("bare/data/") }.count, 0)

        await vault.switchBranch("device-ipad")
        let before = log.events.count
        try await vault.pull()
        let third = log.events.prefix(log.events.count - before)
        let objectRequests = third.filter { $0.kind == .request && $0.path.hasPrefix("bare/data/") }
        // The new commit and its new root tree; docs/ and notes/ are the same subtrees.
        XCTAssertEqual(objectRequests.count, 2, objectRequests.map(\.path).joined(separator: ", "))
    }

    func testTrafficLogNeverContainsKeyMaterial() async throws {
        for fixture in Fixture.all {
            let log = VaultTrafficLog()
            let vault = openVault(fixture, log: log)
            _ = try await vault.inspect()
            for file in try await vault.files() { _ = try await vault.read(file.path) }
            _ = try await SGitVault.deriveKey(from: fixture.expected.vault_key, log: log)
            XCTAssertGreaterThan(log.events.count, 20)
            let passphrase = fixture.expected.vault_key
                .replacingOccurrences(of: "sgit_private_vault_", with: "")
                .components(separatedBy: ":")[0]
            for event in log.events {
                let text = event.path + " " + event.detail
                XCTAssertFalse(text.contains(fixture.expected.read_key_hex), text)
                XCTAssertFalse(text.contains(fixture.expected.write_key_hex), text)
                XCTAssertFalse(text.contains(passphrase), text)
            }
            for kind in [VaultTrafficEvent.Kind.request, .decrypt, .verify, .keyDerivation] {
                XCTAssertTrue(log.events.contains { $0.kind == kind }, "\(kind) events are logged")
            }
        }
    }

    func testInspectorSnapshot() async throws {
        let vault = openVault(.plain)
        let snapshot = try await vault.inspect(historyLimit: 10)
        XCTAssertEqual(snapshot.vaultId, "fixtplain1")
        XCTAssertEqual(snapshot.branch, "current")
        XCTAssertEqual(snapshot.fileCount, 5)
        XCTAssertEqual(snapshot.history.count, 3)
        XCTAssertEqual(snapshot.head?.message, "Fixture commit two: docs")
        XCTAssertEqual(snapshot.branches.count, 4)
        XCTAssertNotNil(snapshot.tree)
    }
}
