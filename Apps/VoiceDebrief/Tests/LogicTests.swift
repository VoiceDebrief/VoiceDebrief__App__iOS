import Foundation
import Testing
import SGitVault
@testable import VoiceDebrief

@Suite("Roadmap")
struct RoadmapTests {
    @Test func everyStageHasItsOwnId() {
        let ids = Roadmap.stages.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func builtAndProposedTogetherAreEverything() {
        #expect(Roadmap.stages(.built).count + Roadmap.stages(.proposed).count == Roadmap.stages.count)
    }

    @Test func nothingClaimsATranscriptYet() {
        // The status screen must not say the app transcribes before it does.
        let built = Roadmap.stages(.built).map(\.id)
        #expect(!built.contains("transcript"))
        #expect(!built.contains("debrief"))
    }
}

@Suite("App info")
struct AppInfoTests {
    @Test func versionLineReadsTheBundleKeys() {
        let line = AppInfo.versionLine(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "12"])
        #expect(line == "0.1.0 (12)")
    }

    @Test func versionLineHasAFallback() {
        #expect(AppInfo.versionLine(info: [:]) == "0.0.0 (0)")
    }

    @Test func thePasskeySiteIsTheRegister() {
        #expect(AppInfo.passkeySite == "pki.sgit.ai")
    }
}

@Suite("Vault engine, linked into the app")
struct VaultEngineTests {
    @Test func aDoorOnThePasskeySiteHasAVaultId() {
        let door = VaultDoor.door(fromSecret: Data(repeating: 7, count: 32), site: AppInfo.passkeySite)
        #expect(door.vaultId.count == 8)
        #expect(door.vaultId.allSatisfy { $0.isLowercase || $0.isNumber })
    }

    @Test func theSameBytesGiveTheSameDoor() {
        let bytes = Data(repeating: 7, count: 32)
        let a = VaultDoor.door(fromSecret: bytes, site: AppInfo.passkeySite)
        let b = VaultDoor.door(fromSecret: bytes, site: AppInfo.passkeySite)
        #expect(a.vaultId == b.vaultId)
    }
}
