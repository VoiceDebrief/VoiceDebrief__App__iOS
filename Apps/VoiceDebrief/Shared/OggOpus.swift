import Foundation

/// WhatsApp's voice notes are Opus audio in an Ogg container (`.opus`, `.ogg`). `AVAudioFile` does not open
/// Ogg, so this reads the container itself: pages (RFC 3533), the packets they carry, and the two Opus headers
/// (RFC 7845). The Opus packets are then decoded by Apple's own Opus decoder (`OggOpusDecoder`).
///
/// Nothing here touches audio: it is plain bytes, so it is tested on its own.
enum OggOpusError: LocalizedError, Equatable {
    case notOgg
    case truncated(page: Int)
    case damaged(page: Int)
    case notOpus
    case badHeader(String)
    case unsupportedChannels(Int)
    case noAudio
    case badPacket(index: Int)
    case decoderUnavailable
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notOgg:
            return "This is not an Ogg file."
        case .truncated(let page):
            return "This voice note is cut short: page \(page) of the Ogg file is incomplete."
        case .damaged(let page):
            return "This voice note is damaged: page \(page) of the Ogg file does not match its checksum."
        case .notOpus:
            return "This Ogg file does not hold Opus audio."
        case .badHeader(let what):
            return "This Opus file's header is not valid (\(what))."
        case .unsupportedChannels(let count):
            return "This Opus file has \(count) channels; only mono and stereo voice notes can be read."
        case .noAudio:
            return "This Opus file holds no audio."
        case .badPacket(let index):
            return "Opus packet \(index) in this file is not valid."
        case .decoderUnavailable:
            return "Apple's Opus decoder is not available on this device."
        case .decodeFailed(let why):
            return "The Opus audio could not be decoded: \(why)"
        }
    }
}

/// The identification header, `OpusHead` (RFC 7845, section 5.1).
struct OpusHead: Equatable {
    var version: Int
    var channels: Int
    /// Samples at 48 kHz to throw away from the start of the decoded audio.
    var preSkip: Int
    /// The rate of the audio before it was encoded; informational only. Opus always decodes at 48 kHz.
    var inputSampleRate: Int
    /// Gain to apply to the decoded audio, in 1/256 dB.
    var outputGain: Int
    var mappingFamily: Int

    /// The output gain as a linear factor.
    var gainFactor: Float { outputGain == 0 ? 1 : Float(pow(10, Double(outputGain) / (20 * 256))) }
}

/// One Ogg page's header fields and where its body lies in the file.
struct OggPage: Equatable {
    var headerType: UInt8
    var granulePosition: Int64
    var serial: UInt32
    var sequence: UInt32
    var segments: [Int]
    var bodyRange: Range<Int>

    var isContinued: Bool { headerType & 0x01 != 0 }
    var isFirst: Bool { headerType & 0x02 != 0 }
    var isLast: Bool { headerType & 0x04 != 0 }
}

/// A whole Ogg Opus file, read into its headers and its audio packets.
struct OggOpusStream {
    /// Opus always decodes at this rate.
    static let sampleRate = 48_000

    var head: OpusHead
    var vendor: String
    var comments: [String]
    /// The audio packets, in order, without the two header packets.
    var packets: [Data]
    /// The granule position of the stream's last page: the 48 kHz sample count up to its end, pre-skip included.
    var finalGranule: Int64
    var pageCount: Int

    /// Samples at 48 kHz once pre-skip and the end's padding are removed.
    var sampleCount: Int {
        let decodable = packets.reduce(0) { $0 + (OggOpus.samples(inPacket: $1) ?? 0) }
        let byGranule = finalGranule > 0 ? Int(finalGranule) : decodable
        return max(0, min(decodable, byGranule) - head.preSkip)
    }

    var seconds: Double { Double(sampleCount) / Double(Self.sampleRate) }
}

enum OggOpus {
    static let capture: [UInt8] = Array("OggS".utf8)

    /// Whether the bytes start like an Ogg file. WhatsApp names its files `.opus`; some apps say `.ogg` or nothing.
    static func looksLikeOgg(_ data: Data) -> Bool {
        data.count >= 4 && Array(data.prefix(4)) == capture
    }

    static func looksLikeOgg(fileAt url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let first = try? handle.read(upToCount: 4) else { return false }
        return looksLikeOgg(first)
    }

    // MARK: Pages

    /// Every page in the file, each checked against its CRC. Page numbers in errors count from 1.
    static func pages(in data: Data) throws -> [OggPage] {
        let bytes = [UInt8](data)
        guard looksLikeOgg(data) else { throw OggOpusError.notOgg }
        var pages: [OggPage] = []
        var offset = 0
        while offset < bytes.count {
            let number = pages.count + 1
            guard bytes.count - offset >= 27 else { throw OggOpusError.truncated(page: number) }
            guard Array(bytes[offset ..< offset + 4]) == capture else {
                // Something that is not a page where a page should begin.
                throw OggOpusError.damaged(page: number)
            }
            guard bytes[offset + 4] == 0 else { throw OggOpusError.damaged(page: number) }
            let headerType = bytes[offset + 5]
            let granule = Int64(bitPattern: readLE(bytes, offset + 6, 8))
            let serial = UInt32(readLE(bytes, offset + 14, 4))
            let sequence = UInt32(readLE(bytes, offset + 18, 4))
            let stored = UInt32(readLE(bytes, offset + 22, 4))
            let count = Int(bytes[offset + 26])
            let headerLength = 27 + count
            guard bytes.count - offset >= headerLength else { throw OggOpusError.truncated(page: number) }
            let segments = bytes[offset + 27 ..< offset + headerLength].map(Int.init)
            let bodyLength = segments.reduce(0, +)
            let end = offset + headerLength + bodyLength
            guard end <= bytes.count else { throw OggOpusError.truncated(page: number) }
            guard crc(bytes, offset ..< end, skippingChecksumAt: offset + 22) == stored else {
                throw OggOpusError.damaged(page: number)
            }
            pages.append(OggPage(headerType: headerType, granulePosition: granule, serial: serial,
                                 sequence: sequence, segments: segments,
                                 bodyRange: offset + headerLength ..< end))
            offset = end
        }
        return pages
    }

    // MARK: The stream

    /// Reads a whole Ogg Opus file. Only the first logical stream that is Opus is read; any other is ignored.
    static func parse(_ data: Data) throws -> OggOpusStream {
        let pages = try pages(in: data)
        let bytes = [UInt8](data)
        guard let first = pages.first(where: \.isFirst) else { throw OggOpusError.notOpus }
        // The Opus stream is the one whose first packet starts with "OpusHead".
        let serial: UInt32 = pages.first { page in
            page.isFirst && page.bodyRange.count >= 8
                && Array(bytes[page.bodyRange.lowerBound ..< page.bodyRange.lowerBound + 8]) == Array("OpusHead".utf8)
        }?.serial ?? first.serial

        var packets: [Data] = []
        var partial: [UInt8]?
        var finalGranule: Int64 = -1
        var count = 0
        for page in pages where page.serial == serial {
            count += 1
            if page.granulePosition >= 0 { finalGranule = page.granulePosition }
            var cursor = page.bodyRange.lowerBound
            var current: [UInt8]? = page.isContinued ? partial : []
            // A continued page with nothing to continue: drop the orphaned piece up to the end of that packet.
            var orphan = page.isContinued && partial == nil
            partial = nil
            for length in page.segments {
                let piece = bytes[cursor ..< cursor + length]
                cursor += length
                if !orphan { current = (current ?? []) + piece }
                if length < 255 {
                    if !orphan, let packet = current { packets.append(Data(packet)) }
                    orphan = false
                    current = []
                }
            }
            // The last lacing value was 255: the packet goes on in the next page.
            if let last = page.segments.last, last == 255, !orphan { partial = current }
        }

        guard packets.count >= 2 else { throw OggOpusError.notOpus }
        let head = try parseHead(packets[0])
        let (vendor, comments) = try parseTags(packets[1])
        let audio = Array(packets.dropFirst(2))
        guard !audio.isEmpty else { throw OggOpusError.noAudio }
        for (index, packet) in audio.enumerated() where samples(inPacket: packet) == nil {
            throw OggOpusError.badPacket(index: index + 1)
        }
        return OggOpusStream(head: head, vendor: vendor, comments: comments, packets: audio,
                             finalGranule: finalGranule, pageCount: count)
    }

    static func parseHead(_ packet: Data) throws -> OpusHead {
        let b = [UInt8](packet)
        guard b.count >= 8, Array(b[0 ..< 8]) == Array("OpusHead".utf8) else { throw OggOpusError.notOpus }
        guard b.count >= 19 else { throw OggOpusError.badHeader("it is too short") }
        let version = Int(b[8])
        guard version >> 4 == 0 else { throw OggOpusError.badHeader("version \(version)") }
        let channels = Int(b[9])
        guard channels > 0 else { throw OggOpusError.badHeader("no channels") }
        let mapping = Int(b[18])
        guard mapping == 0, channels <= 2 else { throw OggOpusError.unsupportedChannels(channels) }
        return OpusHead(version: version, channels: channels, preSkip: Int(readLE(b, 10, 2)),
                        inputSampleRate: Int(readLE(b, 12, 4)),
                        outputGain: Int(Int16(bitPattern: UInt16(readLE(b, 16, 2)))), mappingFamily: mapping)
    }

    static func parseTags(_ packet: Data) throws -> (vendor: String, comments: [String]) {
        let b = [UInt8](packet)
        guard b.count >= 8, Array(b[0 ..< 8]) == Array("OpusTags".utf8) else { throw OggOpusError.badHeader("no OpusTags") }
        var at = 8
        func string() throws -> String {
            guard b.count - at >= 4 else { throw OggOpusError.badHeader("OpusTags is too short") }
            let length = Int(readLE(b, at, 4))
            at += 4
            guard length >= 0, b.count - at >= length else { throw OggOpusError.badHeader("OpusTags is too short") }
            defer { at += length }
            return String(decoding: b[at ..< at + length], as: UTF8.self)
        }
        let vendor = try string()
        guard b.count - at >= 4 else { throw OggOpusError.badHeader("OpusTags is too short") }
        let count = Int(readLE(b, at, 4))
        at += 4
        var comments: [String] = []
        for _ in 0 ..< min(count, 10_000) { comments.append(try string()) }
        return (vendor, comments)
    }

    // MARK: Packets

    /// One Opus packet split into packets of a single frame each (RFC 6716, section 3.2), each with the same
    /// configuration and frame-count code 0. WhatsApp packs six 20 ms frames into one 120 ms packet, which
    /// Apple's decoder refuses; one frame at a time it decodes them. Nil for a packet that is not valid.
    static func frames(inPacket packet: Data) -> [Data]? {
        let b = [UInt8](packet)
        guard let toc = b.first else { return nil }
        let single = toc & 0xFC
        func frame(_ range: Range<Int>) -> Data { Data([single] + b[range]) }
        /// A frame length as coded in a packet: one byte below 252, otherwise two.
        func length(at i: Int) -> (value: Int, size: Int)? {
            guard i < b.count else { return nil }
            if b[i] < 252 { return (Int(b[i]), 1) }
            guard i + 1 < b.count else { return nil }
            return (Int(b[i]) + 4 * Int(b[i + 1]), 2)
        }
        switch toc & 0x03 {
        case 0:
            return [packet]
        case 1:
            let rest = b.count - 1
            guard rest % 2 == 0 else { return nil }
            return [frame(1 ..< 1 + rest / 2), frame(1 + rest / 2 ..< b.count)]
        case 2:
            guard let first = length(at: 1) else { return nil }
            let start = 1 + first.size
            guard start + first.value <= b.count else { return nil }
            return [frame(start ..< start + first.value), frame(start + first.value ..< b.count)]
        default:
            guard b.count >= 2 else { return nil }
            let vbr = b[1] & 0x80 != 0
            let padded = b[1] & 0x40 != 0
            let count = Int(b[1] & 0x3F)
            guard count > 0 else { return nil }
            var at = 2
            var padding = 0
            if padded {
                while true {
                    guard at < b.count else { return nil }
                    let p = Int(b[at])
                    at += 1
                    padding += p == 255 ? 254 : p
                    if p != 255 { break }
                }
            }
            var lengths: [Int] = []
            if vbr {
                for _ in 0 ..< count - 1 {
                    guard let l = length(at: at) else { return nil }
                    at += l.size
                    lengths.append(l.value)
                }
                let last = b.count - padding - at - lengths.reduce(0, +)
                guard last >= 0 else { return nil }
                lengths.append(last)
            } else {
                let data = b.count - padding - at
                guard data >= 0, data % count == 0 else { return nil }
                lengths = Array(repeating: data / count, count: count)
            }
            var frames: [Data] = []
            for l in lengths {
                guard at + l <= b.count - padding else { return nil }
                frames.append(frame(at ..< at + l))
                at += l
            }
            return frames
        }
    }

    /// The number of 48 kHz samples one Opus packet decodes to, from its table-of-contents byte
    /// (RFC 6716, section 3.1). Nil for a packet that is empty or not valid.
    static func samples(inPacket packet: Data) -> Int? {
        guard let toc = packet.first else { return nil }
        let config = Int(toc >> 3)
        let frameSize: Int
        switch config {
        case 0 ..< 12: frameSize = [480, 960, 1920, 2880][config & 3]    // SILK: 10, 20, 40, 60 ms
        case 12 ..< 16: frameSize = [480, 960][config & 1]               // hybrid: 10, 20 ms
        default: frameSize = [120, 240, 480, 960][config & 3]            // CELT: 2.5, 5, 10, 20 ms
        }
        let frames: Int
        switch toc & 0x03 {
        case 0: frames = 1
        case 1, 2: frames = 2
        default:
            guard packet.count >= 2 else { return nil }
            frames = Int(packet[packet.startIndex + 1] & 0x3F)
            guard frames > 0 else { return nil }
        }
        let total = frameSize * frames
        return total <= 5760 ? total : nil     // at most 120 ms in one packet
    }

    // MARK: Writing (for tests, and for anything that must hand Ogg on)

    /// Pages for the given packets (the first two are the headers, each on a page of its own), with at most
    /// `maxSegmentsPerPage` lacing values on a page. A packet longer than a page can hold goes on in the next
    /// page, as the format allows. `granules` gives each packet's granule position.
    static func write(packets: [Data], granules: [Int64], serial: UInt32 = 0x5644_4F47, maxSegmentsPerPage: Int = 255) -> Data {
        precondition(packets.count == granules.count)
        var out = Data()
        var sequence: UInt32 = 0
        var segments: [UInt8] = []
        var body: [UInt8] = []
        var continued = false
        var granule: Int64 = -1
        func flush(last: Bool, nextContinues: Bool) {
            guard !segments.isEmpty else { return }
            var page: [UInt8] = capture + [0]
            var type: UInt8 = continued ? 0x01 : 0
            if sequence == 0 { type |= 0x02 }
            if last { type |= 0x04 }
            page.append(type)
            page += le(UInt64(bitPattern: granule), 8) + le(UInt64(serial), 4) + le(UInt64(sequence), 4) + [0, 0, 0, 0]
            page.append(UInt8(segments.count))
            page += segments
            page += body
            let sum = crc(page, 0 ..< page.count, skippingChecksumAt: 22)
            page.replaceSubrange(22 ..< 26, with: le(UInt64(sum), 4))
            out.append(contentsOf: page)
            sequence += 1
            segments = []
            body = []
            granule = -1
            continued = nextContinues
        }
        for (index, packet) in packets.enumerated() {
            var rest = [UInt8](packet)
            var lacing: [UInt8] = Array(repeating: 255, count: rest.count / 255) + [UInt8(rest.count % 255)]
            var started = false
            while !lacing.isEmpty {
                if segments.count >= maxSegmentsPerPage { flush(last: false, nextContinues: started) }
                let value = Int(lacing.removeFirst())
                segments.append(UInt8(value))
                body += rest.prefix(value)
                rest.removeFirst(value)
                started = true
            }
            granule = granules[index]
            if index < 2 { flush(last: false, nextContinues: false) }
        }
        flush(last: true, nextContinues: false)
        return out
    }

    // MARK: Bytes

    static func readLE(_ b: [UInt8], _ at: Int, _ count: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0 ..< count { value |= UInt64(b[at + i]) << (8 * UInt64(i)) }
        return value
    }

    static func le(_ value: UInt64, _ count: Int) -> [UInt8] {
        (0 ..< count).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    private static let table: [UInt32] = (0 ..< 256).map { i -> UInt32 in
        var r = UInt32(i) << 24
        for _ in 0 ..< 8 { r = r & 0x8000_0000 != 0 ? (r << 1) ^ 0x04C1_1DB7 : r << 1 }
        return r
    }

    /// Ogg's CRC-32 (polynomial 0x04C11DB7, not reflected, starting at zero) over a page, with its checksum
    /// field counted as zeros.
    static func crc(_ b: [UInt8], _ range: Range<Int>, skippingChecksumAt field: Int) -> UInt32 {
        var c: UInt32 = 0
        for i in range {
            let byte: UInt8 = (i >= field && i < field + 4) ? 0 : b[i]
            c = (c << 8) ^ table[Int(((c >> 24) ^ UInt32(byte)) & 0xFF)]
        }
        return c
    }
}
