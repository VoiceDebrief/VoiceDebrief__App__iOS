import AVFoundation
import Foundation
import Testing
@testable import VoiceDebrief

/// The fixtures in `Tests/IntakeFixtures/` (see `intakefixtures.md` there).
enum IntakeFixtureFiles {
    static func url(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: base, withExtension: ext)
                ?? bundle.url(forResource: base, withExtension: ext, subdirectory: "IntakeFixtures") {
                return url
            }
        }
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("IntakeFixtures/\(name)")
        guard FileManager.default.fileExists(atPath: beside.path) else { throw CocoaError(.fileNoSuchFile) }
        return beside
    }

    /// A copy under another name, in a folder of its own: how a mislabelled file arrives.
    static func copy(_ name: String, as newName: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "intake-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: newName)
        try FileManager.default.copyItem(at: try url(name), to: target)
        return target
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

    static func temporaryWAV() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "intake-\(UUID().uuidString).wav")
    }
}

@Suite("Audio intake: what a file is, from its bytes")
struct AudioSnifferTests {
    @Test(arguments: [
        ("intake-whatsapp-voice-note-1.opus", AudioContainer.oggOpus),
        ("intake-whatsapp-voice-note-2.opus", .oggOpus),
        ("intake-tone-vorbis.ogg", .oggVorbis),
        ("intake-tone.mp3", .mp3),
        ("intake-tone-bare.mp3", .mp3),
        ("intake-tone.m4a", .isoMedia(brand: "M4A ")),
        ("intake-tone.wav", .wave),
        ("intake-tone.flac", .flac),
        ("intake-tone.aiff", .aiff),
        ("intake-tone.caf", .caf),
        ("intake-video.mp4", .isoMedia(brand: "isom")),
        ("intake-video.mov", .isoMedia(brand: "qt  ")),
        ("intake-video.3gp", .isoMedia(brand: "3gp6")),
        ("intake-video.webm", .ebml),
    ])
    func eachFixtureIsKnownByItsBytes(name: String, expected: AudioContainer) throws {
        #expect(AudioSniffer.sniff(fileAt: try IntakeFixtureFiles.url(name)) == expected)
    }

    @Test func theNameDoesNotDecide() throws {
        let opusCalledMP3 = try IntakeFixtureFiles.copy("intake-whatsapp-voice-note-1.opus", as: "voice.mp3")
        #expect(AudioSniffer.sniff(fileAt: opusCalledMP3) == .oggOpus)
        let mp3CalledOpus = try IntakeFixtureFiles.copy("intake-tone.mp3", as: "voice.opus")
        #expect(AudioSniffer.sniff(fileAt: mp3CalledOpus) == .mp3)
    }

    @Test func otherSignatures() {
        #expect(AudioSniffer.sniff(Data("#!AMR\n".utf8) + Data(count: 20)) == .amr)
        #expect(AudioSniffer.sniff(Data("hello, this is text".utf8)) == .unknown)
        #expect(AudioSniffer.sniff(Data()) == .unknown)
        #expect(AudioSniffer.sniff(Data([0xFF, 0xF9, 0x50, 0x80])) == .unknown)   // ADTS AAC: layer bits 00, not MP3
    }

    @Test func sourceLines() {
        #expect(AudioSniffer.sourceLine(name: "PTT-20261117-WA0003.opus", container: .oggOpus, prefix: "Shared: ")
            == "Shared: PTT-20261117-WA0003.opus (Ogg Opus)")
        #expect(AudioSniffer.sourceLine(name: "IMG_0042.MOV", container: .isoMedia(brand: "qt  "))
            == "Video: soundtrack of IMG_0042.MOV")
        #expect(AudioSniffer.sourceLine(name: "memo.m4a", container: .isoMedia(brand: "M4A ")) == "memo.m4a (MPEG-4 audio)")
        #expect(AudioSniffer.sourceLine(name: "thing", container: .unknown) == "thing")
    }
}

@Suite("Audio intake: every format to audio the pipeline reads")
struct AudioIntakeTests {
    static func prepare(_ url: URL) async throws -> (AudioIntake.Prepared, URL) {
        let wav = IntakeFixtureFiles.temporaryWAV()
        let prepared = try await AudioIntake.prepare(url, wav: wav)
        return (prepared, prepared.wav ?? url)
    }

    /// Whatever comes out must open with `AVAudioFile`, the reader the transcriber and the compressor use.
    static func readableSeconds(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    @Test(arguments: ["intake-tone.mp3", "intake-tone-bare.mp3", "intake-tone.m4a", "intake-tone.wav",
                      "intake-tone.flac", "intake-tone.aiff", "intake-tone.caf"])
    func plainAudioIsReadAsItIs(name: String) async throws {
        let (prepared, out) = try await Self.prepare(try IntakeFixtureFiles.url(name))
        #expect(!prepared.hadVideo)
        #expect(abs(try Self.readableSeconds(out) - 1) < 0.2)
    }

    @Test(arguments: ["intake-video.mp4", "intake-video.mov", "intake-video.3gp"])
    func aVideosSoundtrackIsTakenOut(name: String) async throws {
        let (prepared, out) = try await Self.prepare(try IntakeFixtureFiles.url(name))
        #expect(prepared.hadVideo)
        let wav = try #require(prepared.wav)
        #expect(out == wav)
        let file = try AVAudioFile(forReading: wav)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(abs(try Self.readableSeconds(wav) - 1) < 0.2)
        #expect(prepared.summary.hasPrefix("Soundtrack taken from the"))
    }

    @Test func extractionReportsProgress() async throws {
        let seen = ProgressBox()
        let wav = IntakeFixtureFiles.temporaryWAV()
        _ = try await AudioIntake.prepare(try IntakeFixtureFiles.url("intake-video.mov"), wav: wav) { seen.add($0) }
        #expect(seen.values.last ?? 0 > 0.9)
    }

    @Test(arguments: [("intake-whatsapp-voice-note-1.opus", 564_480), ("intake-whatsapp-voice-note-2.opus", 274_560)])
    func realWhatsAppVoiceNotesDecode(name: String, samples: Int) async throws {
        let (prepared, out) = try await Self.prepare(try IntakeFixtureFiles.url(name))
        #expect(prepared.container == .oggOpus)
        let file = try AVAudioFile(forReading: out)
        // The granule position less the pre-skip, at 48 kHz, to within one 20 ms frame: on WhatsApp's hybrid
        // packets Apple's decoder gives back 432 samples (9 ms) fewer (runs 425 on); Opus tones are exact.
        #expect(Int(file.length) <= samples)
        #expect(samples - Int(file.length) <= 960)
        #expect(abs((prepared.seconds ?? 0) - Double(samples) / 48_000) < 0.021)
    }

    @Test func opusNamedMP3StillDecodes() async throws {
        let mislabelled = try IntakeFixtureFiles.copy("intake-whatsapp-voice-note-2.opus", as: "voice-note.mp3")
        let (prepared, out) = try await Self.prepare(mislabelled)
        #expect(prepared.container == .oggOpus)
        let length = Int(try AVAudioFile(forReading: out).length)
        #expect(length <= 274_560 && 274_560 - length <= 960)
    }

    @Test func vorbisAndWebMSayPlainlyTheyAreNotSupported() async throws {
        await #expect(throws: AudioIntakeError.vorbis) {
            _ = try await AudioIntake.prepare(try IntakeFixtureFiles.url("intake-tone-vorbis.ogg"), wav: IntakeFixtureFiles.temporaryWAV())
        }
        await #expect(throws: AudioIntakeError.webm) {
            _ = try await AudioIntake.prepare(try IntakeFixtureFiles.url("intake-video.webm"), wav: IntakeFixtureFiles.temporaryWAV())
        }
    }

    @Test func aDamagedVideoSaysSoAndLeavesNothing() async throws {
        let whole = try Data(contentsOf: try IntakeFixtureFiles.url("intake-video.mp4"))
        let folder = FileManager.default.temporaryDirectory.appending(path: "intake-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let damaged = folder.appending(path: "IMG_0042.mp4")
        var bytes = whole.prefix(200)                       // the header, and nothing it points to
        bytes.append(Data(repeating: 0, count: 64))
        try bytes.write(to: damaged)
        let wav = IntakeFixtureFiles.temporaryWAV()
        await #expect(throws: AudioIntakeError.unreadable("IMG_0042.mp4")) {
            _ = try await AudioIntake.prepare(damaged, wav: wav)
        }
        #expect(!FileManager.default.fileExists(atPath: wav.path))
        #expect(AudioIntakeError.unreadable("IMG_0042.mp4").localizedDescription
            == "IMG_0042.mp4 could not be read as audio or video. It may be damaged, or in a format this device does not know.")
    }

    @Test func textIsNotAudio() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "intake-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = folder.appending(path: "notes.m4a")
        try Data("These are not sounds.".utf8).write(to: text)
        await #expect(throws: AudioIntakeError.unreadable("notes.m4a")) {
            _ = try await AudioIntake.prepare(text, wav: IntakeFixtureFiles.temporaryWAV())
        }
    }
}

/// Progress values from a callback, for the test above.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func add(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
}
