import Foundation
import Testing
@testable import SGit

@Suite("What happened in the app, and the report of it")
@MainActor
struct UsageTests {
    private func log() -> UsageLog {
        UsageLog(file: FileManager.default.temporaryDirectory.appending(path: "usage-\(UUID().uuidString).json"))
    }

    @Test func eventsAreKeptCountedAndReadBack() {
        let log = log()
        log.screen("vault", seconds: 12)
        log.screen("vault", seconds: 3)
        log.action("files.add")
        #expect(log.screens.first?.name == "vault")
        #expect(log.screens.first?.count == 2)
        #expect(log.screens.first?.seconds == 15)
        #expect(log.actions.first?.name == "files.add")
        #expect(UsageLog(file: log.file).events.map(\.name) == log.events.map(\.name))
        log.clear()
        #expect(UsageLog(file: log.file).events.isEmpty)
    }

    @Test func theReportIsOneLaneMessageWithTheSgitKindAndNoContent() throws {
        let log = log()
        log.action("vault.create")
        let message = try log.laneMessage(app: "sgit 0.0.0 (0)", at: Date(timeIntervalSince1970: 1_800_000_000))
        let newline = try #require(message.firstIndex(of: 0x0A))
        let header = try JSONDecoder().decode(DeveloperLane.Header.self, from: message[..<newline])
        let body = Data(message[message.index(after: newline)...])
        #expect(header.kind == "sgit/usage/v1")
        #expect(header.note == "usage-1800000000")
        #expect(header.size == body.count)
        #expect(header.sha256 == DeveloperLane.sha256Hex(body))
        let report = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(report.keys) == ["app", "device", "events", "made"])
        let events = try #require(report["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events[0]["name"] as? String == "vault.create")
    }

    @Test func theBuiltInLaneIsReadAndTimesAreSaidPlainly() {
        #expect(DeveloperLane.builtIn?.fingerprint == DeveloperLane.builtInFingerprint)
        #expect(ActivityView.duration(45) == "45 s")
        #expect(ActivityView.duration(185) == "3 min 05 s")
        #expect(ActivityView.duration(3_720) == "1 h 02 min")
    }

    @Test func theWebVaultIsGivenItsKeyByMessageAndKeptToItsOwnHost() {
        #expect(WebVault.address.query() == "embed=1")
        #expect(WebVault.address.fragment() == nil)
        #expect(WebVault.open.contains("vault-open"))
        #expect(!WebVault.open.contains("sgit_"))
        #expect(WebVault.staysInside(URL(string: "https://dev.vault.sgraph.ai/en-gb/vault/?embed=1")))
        #expect(!WebVault.staysInside(URL(string: "https://example.com/")))
        #expect(!WebVault.staysInside(URL(string: "http://dev.vault.sgraph.ai/")))
        #expect(WebVault.standing(sg: "vault-embed-ready", name: "", files: 0, message: "") == .waitingForKey)
        #expect(WebVault.standing(sg: "vault-ready", name: "x", files: 4, message: "") == .open(files: 4))
        #expect(WebVault.standing(sg: "vault-error", name: "", files: 0, message: "") == .failed("The web Vault could not open this vault."))
        #expect(WebVault.standing(sg: "vault-open", name: "", files: 0, message: "") == nil)
    }
}
