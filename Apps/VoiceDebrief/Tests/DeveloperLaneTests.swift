import Foundation
import Security
import Testing
@testable import VoiceDebrief

@Suite("Developer lane")
struct DeveloperLaneTests {
    /// A throwaway RSA key made for one test, and the lane link that carries its public half.
    static func keyAndLink(vault: String = "abcd1234", token: String = "0123456789abcdef0123") throws -> (SecKey, String) {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
        let spki = LaneCrypto.spki(fromPKCS1: pkcs1)
        let encoded = spki.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return (privateKey, "sgi1.\(vault).\(token).\(encoded)")
    }

    @Test func aLinkIsReadAloneOrInsideOtherText() throws {
        let (_, link) = try Self.keyAndLink()
        let lane = try #require(DeveloperLane.parse(link))
        #expect(lane.vault == "abcd1234")
        #expect(lane.token == "0123456789abcdef0123")
        #expect(lane.fingerprint.hasPrefix("sha256:"))
        #expect(lane.fingerprint.count == 23)
        #expect(lane.writeURL.absoluteString == "https://dev.send.sgraph.ai/api/vault/append/write/abcd1234")
        #expect(DeveloperLane.parse("paste this: \(link) thanks") == lane)
    }

    @Test func theBuiltInLaneIsTheOneItSaysItIs() throws {
        let lane = try #require(DeveloperLane.builtIn)
        #expect(lane.fingerprint == DeveloperLane.builtInFingerprint)
        #expect(lane.vault == "fjq2ekcw")
    }

    @Test func aPastedLinkTakesTheBuiltInLanesPlace() throws {
        let (_, link) = try Self.keyAndLink()
        #expect(DeveloperLane.current(pasted: link)?.vault == "abcd1234")
        #expect(DeveloperLane.current(pasted: "") == DeveloperLane.builtIn)
        #expect(DeveloperLane.current(pasted: "nonsense") == DeveloperLane.builtIn)
    }

    @Test func whatIsNotALinkIsRefused() {
        #expect(DeveloperLane.parse("") == nil)
        #expect(DeveloperLane.parse("sgi1.abcd1234.0123456789abcdef.notakey") == nil)
        #expect(DeveloperLane.parse("https://example.com") == nil)
    }

    @Test func aMessageSealedToTheLaneOpensWithItsPrivateKey() throws {
        let (privateKey, link) = try Self.keyAndLink()
        let lane = try #require(DeveloperLane.parse(link))
        let message = Data("a voice note".utf8)
        let sealed = try LaneCrypto.encrypt(message, to: LaneCrypto.publicKey(pem: lane.publicKeyPEM))
        #expect(try LaneCrypto.decrypt(sealed, with: privateKey) == message)
        // The lane stores the text encoded once more.
        let stored = LaneCrypto.lanePayload(encText: sealed)
        #expect(try LaneCrypto.encText(fromLaneContent: stored) == sealed)
    }

    @Test func aFileIsCutIntoPartsAndNothingIsLost() {
        let data = Data((0..<2500).map { UInt8($0 % 251) })
        let parts = DeveloperLane.parts(of: data, size: 1000)
        #expect(parts.map(\.count) == [1000, 1000, 500])
        #expect(parts.reduce(Data(), +) == data)
        #expect(DeveloperLane.parts(of: Data(), size: 1000).isEmpty)
        #expect(DeveloperLane.parts(of: data, size: 5000).count == 1)
    }

    @Test func aNoteBecomesItsAudioPartsAndThenItsRun() throws {
        var run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 900, text: "Hello.")])
        let audio = Data(repeating: 7, count: DeveloperLane.partSize + 10)
        let messages = try DeveloperLane.messages(audio: audio, audioName: "note.m4a", run: run, noteId: "n1",
                                                  app: "0.1.3 (1)", at: Date(timeIntervalSince1970: 0))
        #expect(messages.count == 3)

        func split(_ message: Data) throws -> (DeveloperLane.Header, Data) {
            let newline = try #require(message.firstIndex(of: 0x0A))
            let header = try JSONDecoder().decode(DeveloperLane.Header.self, from: message[message.startIndex..<newline])
            return (header, Data(message[message.index(after: newline)...]))
        }
        let (first, firstBody) = try split(messages[0])
        let (second, secondBody) = try split(messages[1])
        let (last, lastBody) = try split(messages[2])
        #expect(first.kind == DeveloperLane.Header.audioKind)
        #expect(first.part == 1 && first.of == 2 && second.part == 2)
        #expect(first.size == audio.count)
        #expect(first.sha256 == DeveloperLane.sha256Hex(audio))
        #expect(firstBody + secondBody == audio)
        #expect(last.kind == DeveloperLane.Header.runKind)
        #expect(try JSONDecoder().decode(DebriefRun.self, from: lastBody) == run)
        #expect(first.note == "n1" && last.note == "n1")
    }
}

@Suite("Recording level")
struct RecordingLevelTests {
    @Test func decibelsBecomeZeroToOne() {
        #expect(VoiceRecorder.level(decibels: 0) == 1)
        #expect(VoiceRecorder.level(decibels: -50) == 0)
        #expect(VoiceRecorder.level(decibels: -160) == 0)
        #expect(VoiceRecorder.level(decibels: -25) == 0.5)
        #expect(VoiceRecorder.level(decibels: 6) == 1)
        #expect(VoiceRecorder.level(decibels: -.infinity) == 0)
    }
}
