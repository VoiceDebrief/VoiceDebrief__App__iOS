import AVFoundation
import Foundation
import Testing
@testable import VoiceDebrief

/// The fixtures in `Tests/OggFixtures/`: tones made with ffmpeg and libopus (see the README there), no voice.
enum OggFixtureFiles {
    static func url(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: base, withExtension: ext)
                ?? bundle.url(forResource: base, withExtension: ext, subdirectory: "OggFixtures") {
                return url
            }
        }
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("OggFixtures/\(name)")
        guard FileManager.default.fileExists(atPath: beside.path) else { throw CocoaError(.fileNoSuchFile) }
        return beside
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
}

@Suite("Ogg Opus: pages, packets and headers")
struct OggOpusParserTests {
    @Test func aShortSinglePageNoteIsRead() throws {
        let stream = try OggOpus.parse(try OggFixtureFiles.data("oggfixture-tone-440-short.opus"))
        #expect(stream.head == OpusHead(version: 1, channels: 1, preSkip: 312, inputSampleRate: 16_000,
                                        outputGain: 0, mappingFamily: 0))
        #expect(stream.pageCount == 3)
        #expect(stream.packets.count == 31)
        #expect(stream.finalGranule == 29_112)
        #expect(stream.sampleCount == 28_800)          // 0.6 s at 48 kHz: the granule less the pre-skip
        #expect(abs(stream.seconds - 0.6) < 0.0001)
        #expect(!stream.vendor.isEmpty)
        #expect(stream.packets.allSatisfy { OggOpus.samples(inPacket: $0) == 960 })
    }

    @Test func aNoteOverManyPagesIsRead() throws {
        let stream = try OggOpus.parse(try OggFixtureFiles.data("oggfixture-tone-300-pages.ogg"))
        #expect(stream.pageCount == 18)
        #expect(stream.packets.count == 201)
        #expect(stream.finalGranule == 192_312)
        #expect(stream.sampleCount == 192_000)          // 4 s
    }

    @Test func stereoSixtyMillisecondPacketsLongerThanOneSegment() throws {
        let stream = try OggOpus.parse(try OggFixtureFiles.data("oggfixture-tone-500-stereo-60ms.opus"))
        #expect(stream.head.channels == 2)
        #expect(stream.head.inputSampleRate == 48_000)
        #expect(stream.packets.count == 26)
        #expect(stream.packets.contains { $0.count > 255 })   // laced over two segments
        #expect(stream.packets.allSatisfy { OggOpus.samples(inPacket: $0) == 2880 })
        #expect(stream.sampleCount == 72_000)            // 1.5 s
    }

    @Test func aDamagedPageFailsWithAPlainMessage() throws {
        // oggfixture-damaged.ogg is the many-page note with one byte of its fourth page flipped.
        #expect(throws: OggOpusError.damaged(page: 4)) {
            try OggOpus.parse(try OggFixtureFiles.data("oggfixture-damaged.ogg"))
        }
        #expect(OggOpusError.damaged(page: 4).localizedDescription
            == "This voice note is damaged: page 4 of the Ogg file does not match its checksum.")
    }

    @Test func aFileCutShortFailsWithAPlainMessage() throws {
        let whole = try OggFixtureFiles.data("oggfixture-tone-300-pages.ogg")
        let cut = whole.prefix(1_000)                    // inside the fourth page (it starts at byte 656)
        #expect(throws: OggOpusError.truncated(page: 4)) { try OggOpus.parse(cut) }
        #expect(OggOpusError.truncated(page: 4).localizedDescription
            == "This voice note is cut short: page 4 of the Ogg file is incomplete.")
    }

    @Test func somethingElseIsNotOgg() throws {
        let wav = Data("RIFF\u{0}\u{0}\u{0}\u{0}WAVEfmt ".utf8)
        #expect(!OggOpus.looksLikeOgg(wav))
        #expect(throws: OggOpusError.notOgg) { try OggOpus.parse(wav) }
        #expect(OggOpus.looksLikeOgg(try OggFixtureFiles.data("oggfixture-tone-440-short.opus")))
        #expect(OggOpus.looksLikeOgg(fileAt: try OggFixtureFiles.url("oggfixture-tone-440-short.opus")))
    }

    @Test func oggThatIsNotOpusIsRefused() {
        let packets = [Data("\u{1}vorbis-not-opus".utf8), Data("more".utf8), Data([0x08])]
        let ogg = OggOpus.write(packets: packets, granules: [0, 0, 960])
        #expect(throws: OggOpusError.notOpus) { try OggOpus.parse(ogg) }
    }

    @Test func moreThanTwoChannelsIsRefusedPlainly() {
        var head = Data("OpusHead".utf8)
        head.append(contentsOf: [1, 6] as [UInt8])
        head.append(contentsOf: OggOpus.le(312, 2))
        head.append(contentsOf: OggOpus.le(48_000, 4))
        head.append(contentsOf: [0, 0, 1, 4, 2, 0, 4, 1, 2, 3, 5] as [UInt8])     // gain, family 1, its table
        let ogg = OggOpus.write(packets: [head, Self.tags, Data([0x08])], granules: [0, 0, 960])
        #expect(throws: OggOpusError.unsupportedChannels(6)) { try OggOpus.parse(ogg) }
    }

    static let tags: Data = {
        var tags = Data("OpusTags".utf8)
        tags.append(contentsOf: OggOpus.le(4, 4))
        tags.append(contentsOf: Array("test".utf8))
        tags.append(contentsOf: OggOpus.le(1, 4))
        tags.append(contentsOf: OggOpus.le(9, 4))
        tags.append(contentsOf: Array("TITLE=one".utf8))
        return tags
    }()

    static func head(preSkip: Int = 312) -> Data {
        var head = Data("OpusHead".utf8)
        head.append(contentsOf: [1, 1] as [UInt8])
        head.append(contentsOf: OggOpus.le(UInt64(preSkip), 2))
        head.append(contentsOf: OggOpus.le(16_000, 4))
        head.append(contentsOf: [0, 0, 0] as [UInt8])
        return head
    }

    @Test func aPacketSplitAcrossPagesIsJoined() throws {
        // A 700-byte packet, with at most two lacing values a page, goes over two pages.
        let big = Data((0 ..< 700).map { UInt8(truncatingIfNeeded: $0) })
        var bigPacket = Data([0x08])                     // TOC: SILK narrowband 20 ms, one frame
        bigPacket.append(big)
        let small = Data([0x08, 1, 2, 3])
        let ogg = OggOpus.write(packets: [Self.head(), Self.tags, small, bigPacket, small],
                                granules: [0, 0, 960, 1920, 2880], maxSegmentsPerPage: 2)
        let pages = try OggOpus.pages(in: ogg)
        #expect(pages.contains { $0.isContinued })
        #expect(pages.last?.isLast == true)
        let stream = try OggOpus.parse(ogg)
        #expect(stream.packets == [small, bigPacket, small])
        #expect(stream.comments == ["TITLE=one"])
        #expect(stream.vendor == "test")
        #expect(stream.sampleCount == 2880 - 312)
    }

    @Test func aPacketOfExactlyTwoHundredAndFiftyFiveBytesEndsWithAZeroLacingValue() throws {
        var packet = Data([0x08])
        packet.append(Data(repeating: 7, count: 254))
        #expect(packet.count == 255)
        let ogg = OggOpus.write(packets: [Self.head(preSkip: 0), Self.tags, packet], granules: [0, 0, 960])
        let stream = try OggOpus.parse(ogg)
        #expect(stream.packets == [packet])
        #expect(try OggOpus.pages(in: ogg).last?.segments == [255, 0])
    }

    @Test func packetLengthsFromTheTableOfContents() {
        #expect(OggOpus.samples(inPacket: Data([0x00])) == 480)          // SILK 10 ms
        #expect(OggOpus.samples(inPacket: Data([0x08])) == 960)          // SILK 20 ms
        #expect(OggOpus.samples(inPacket: Data([0x18])) == 2880)         // SILK 60 ms
        #expect(OggOpus.samples(inPacket: Data([0x78])) == 960)          // hybrid 20 ms
        #expect(OggOpus.samples(inPacket: Data([0x80])) == 120)          // CELT 2.5 ms
        #expect(OggOpus.samples(inPacket: Data([0xF8])) == 960)          // CELT 20 ms
        #expect(OggOpus.samples(inPacket: Data([0x09])) == 1920)         // two frames, code 1
        #expect(OggOpus.samples(inPacket: Data([0x0B, 0x03])) == 2880)   // three frames, code 3
        #expect(OggOpus.samples(inPacket: Data([0x0B])) == nil)          // code 3 with no count
        #expect(OggOpus.samples(inPacket: Data([0x1B, 0x03])) == nil)    // 180 ms is more than a packet may hold
        #expect(OggOpus.samples(inPacket: Data()) == nil)
    }

    @Test func multiFramePacketsAreSplitIntoSingleFrames() throws {
        // Code 0: as it is.
        #expect(OggOpus.frames(inPacket: Data([0x08, 1, 2])) == [Data([0x08, 1, 2])])
        // Code 1: two frames of equal size.
        #expect(OggOpus.frames(inPacket: Data([0x09, 1, 2, 3, 4])) == [Data([0x08, 1, 2]), Data([0x08, 3, 4])])
        #expect(OggOpus.frames(inPacket: Data([0x09, 1, 2, 3])) == nil)
        // Code 2: the first frame's length, then both.
        #expect(OggOpus.frames(inPacket: Data([0x0A, 1, 7, 8, 9])) == [Data([0x08, 7]), Data([0x08, 8, 9])])
        // Code 3, constant bit rate: three frames of two bytes.
        #expect(OggOpus.frames(inPacket: Data([0x0B, 0x03, 1, 2, 3, 4, 5, 6]))
            == [Data([0x08, 1, 2]), Data([0x08, 3, 4]), Data([0x08, 5, 6])])
        // Code 3, variable, with two bytes of padding: lengths 1 and 2 coded, the last takes the rest.
        #expect(OggOpus.frames(inPacket: Data([0x0B, 0xC3, 2, 1, 2, 9, 8, 7, 6, 5, 0, 0]))
            == [Data([0x08, 9]), Data([0x08, 8, 7]), Data([0x08, 6, 5])])
        // Every packet of a real WhatsApp note splits into 20 ms frames that add up to the packet.
        let stream = try OggOpus.parse(try IntakeFixtureFiles.data("intake-whatsapp-voice-note-2.opus"))
        for packet in stream.packets {
            let frames = try #require(OggOpus.frames(inPacket: packet))
            #expect(frames.allSatisfy { OggOpus.samples(inPacket: $0) == 960 })
            #expect(frames.count * 960 == OggOpus.samples(inPacket: packet))
        }
    }

    @Test func theChecksumIsOggs() {
        // The standard check string under Ogg's CRC (polynomial 0x04C11DB7, not reflected, start and end 0).
        let bytes = Array("123456789".utf8)
        #expect(OggOpus.crc(bytes, 0 ..< bytes.count, skippingChecksumAt: 100) == 0x89A1_897F)
    }
}

@Suite("Ogg Opus: Apple's decoder")
struct OggOpusDecoderTests {
    /// Zero crossings per second of the first channel, a rough measure of a tone's frequency.
    static func frequency(of buffer: AVAudioPCMBuffer, from start: Int = 4800) -> Double {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        var crossings = 0
        for i in max(1, start) ..< count where (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
        return Double(crossings) / 2 / (Double(count - start) / 48_000)
    }

    static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum = 0.0
        for i in 0 ..< Int(buffer.frameLength) { sum += Double(samples[i]) * Double(samples[i]) }
        return (sum / Double(buffer.frameLength)).squareRoot()
    }

    static func decodeAll(_ name: String) throws -> AVAudioPCMBuffer {
        let stream = try OggOpus.parse(try OggFixtureFiles.data(name))
        let format = try #require(OggOpusDecoder.pcmFormat(channels: stream.head.channels))
        let all = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(stream.sampleCount + 48_000)))
        let frames = try OggOpusDecoder.decode(stream) { piece in
            for channel in 0 ..< Int(format.channelCount) {
                (all.floatChannelData![channel] + Int(all.frameLength))
                    .update(from: piece.floatChannelData![channel], count: Int(piece.frameLength))
            }
            all.frameLength += piece.frameLength
        }
        #expect(frames == Int(all.frameLength))
        return all
    }

    @Test func theShortNoteDecodesToItsLengthAndItsTone() throws {
        let pcm = try Self.decodeAll("oggfixture-tone-440-short.opus")
        #expect(pcm.frameLength == 28_800)
        #expect(abs(Self.frequency(of: pcm) - 440) < 25)
        #expect(Self.rms(of: pcm) > 0.05)              // ffmpeg's sine is at 1/8 amplitude: RMS about 0.088
    }

    @Test func theManyPageNoteDecodesToFourSeconds() throws {
        let pcm = try Self.decodeAll("oggfixture-tone-300-pages.ogg")
        #expect(pcm.frameLength == 192_000)
        #expect(abs(Self.frequency(of: pcm) - 300) < 20)
    }

    @Test func stereoSixtyMillisecondPacketsDecode() throws {
        let pcm = try Self.decodeAll("oggfixture-tone-500-stereo-60ms.opus")
        #expect(pcm.format.channelCount == 2)
        #expect(pcm.frameLength == 72_000)
        #expect(abs(Self.frequency(of: pcm) - 500) < 30)
    }

    @Test func transcodedToAWAVThatTheTranscriberReads() throws {
        let wav = FileManager.default.temporaryDirectory.appending(path: "ogg-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let seconds = try OggOpusDecoder.transcode(ogg: try OggFixtureFiles.url("oggfixture-tone-300-pages.ogg"), toWAV: wav)
        #expect(abs(seconds - 4) < 0.001)
        // The same reader the transcriber and the compressor use.
        let file = try AVAudioFile(forReading: wav)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.length == 192_000)
        #expect(abs((SpeechFileTranscriber.audioSeconds(url: wav) ?? 0) - 4) < 0.001)
        #expect(abs((OggOpusDecoder.seconds(ofFileAt: try OggFixtureFiles.url("oggfixture-tone-300-pages.ogg")) ?? 0) - 4) < 0.001)
    }

    @Test func aDamagedFileLeavesNoWAVAndSaysWhy() throws {
        let wav = FileManager.default.temporaryDirectory.appending(path: "ogg-\(UUID().uuidString).wav")
        #expect(throws: OggOpusError.damaged(page: 4)) {
            try OggOpusDecoder.transcode(ogg: try OggFixtureFiles.url("oggfixture-damaged.ogg"), toWAV: wav)
        }
        #expect(!FileManager.default.fileExists(atPath: wav.path))
    }
}
