import Foundation

/// What a file is, decided from its first bytes alone, never from its name or the type it was labelled with:
/// WhatsApp's voice notes arrive as `.opus`, `.ogg`, `audio/ogg`, `application/ogg` or `video/ogg`, and the web
/// app learnt that trusting the label can produce a confident, invented transcript (its issue 025).
enum AudioContainer: Equatable, Sendable {
    case oggOpus
    case oggVorbis
    case oggOther
    /// ISO base media (MP4, M4A, MOV, 3GP), with its major brand ("M4A ", "qt  ", "isom", "3gp6").
    case isoMedia(brand: String)
    case wave
    case mp3
    case flac
    case aiff
    case caf
    /// WebM or Matroska.
    case ebml
    case amr
    case unknown

    /// How the format is named to a person.
    var name: String {
        switch self {
        case .oggOpus: return "Ogg Opus"
        case .oggVorbis: return "Ogg Vorbis"
        case .oggOther: return "Ogg"
        case .isoMedia(let brand):
            switch AudioContainer.brandKind(brand) {
            case .audio: return "MPEG-4 audio"
            case .quickTime: return "QuickTime movie"
            case .threeGP: return "3GP"
            case .mp4: return "MPEG-4"
            }
        case .wave: return "WAV"
        case .mp3: return "MP3"
        case .flac: return "FLAC"
        case .aiff: return "AIFF"
        case .caf: return "Core Audio"
        case .ebml: return "WebM or Matroska"
        case .amr: return "AMR"
        case .unknown: return "unknown"
        }
    }

    /// A container that usually carries video, whose soundtrack is what we want.
    var mayHoldVideo: Bool {
        switch self {
        case .isoMedia(let brand): return AudioContainer.brandKind(brand) != .audio
        case .ebml: return true
        default: return false
        }
    }

    enum BrandKind { case audio, quickTime, threeGP, mp4 }

    static func brandKind(_ brand: String) -> BrandKind {
        let b = brand.trimmingCharacters(in: .whitespaces).lowercased()
        if ["m4a", "m4b", "m4p", "f4a"].contains(b) { return .audio }
        if b == "qt" { return .quickTime }
        if b.hasPrefix("3g") { return .threeGP }
        return .mp4
    }
}

enum AudioSniffer {
    /// How many bytes `sniff` wants: the Ogg first page and its first packet fit well inside this.
    static let headLength = 64

    static func sniff(_ data: Data) -> AudioContainer {
        let b = [UInt8](data.prefix(headLength))
        func ascii(_ at: Int, _ text: String) -> Bool {
            let t = Array(text.utf8)
            return b.count >= at + t.count && Array(b[at ..< at + t.count]) == t
        }
        if ascii(0, "OggS") {
            // The first page's first packet: after the 27-byte header and its lacing values.
            guard b.count > 27 else { return .oggOther }
            let body = 27 + Int(b[26])
            if ascii(body, "OpusHead") { return .oggOpus }
            if b.count > body, b[body] == 1, ascii(body + 1, "vorbis") { return .oggVorbis }
            return .oggOther
        }
        if ascii(4, "ftyp") {
            let brand = b.count >= 12 ? String(decoding: b[8 ..< 12], as: UTF8.self) : ""
            return .isoMedia(brand: brand)
        }
        if ascii(0, "RIFF"), ascii(8, "WAVE") { return .wave }
        if ascii(0, "fLaC") { return .flac }
        if ascii(0, "FORM"), ascii(8, "AIFF") || ascii(8, "AIFC") { return .aiff }
        if ascii(0, "caff") { return .caf }
        if b.count >= 4, b[0] == 0x1A, b[1] == 0x45, b[2] == 0xDF, b[3] == 0xA3 { return .ebml }
        if ascii(0, "#!AMR") { return .amr }
        if ascii(0, "ID3") { return .mp3 }
        // An MPEG audio frame: eleven sync bits, a layer that is not "reserved".
        if b.count >= 2, b[0] == 0xFF, b[1] & 0xE0 == 0xE0, b[1] & 0x06 != 0 { return .mp3 }
        return .unknown
    }

    static func sniff(fileAt url: URL) -> AudioContainer {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headLength) else { return .unknown }
        return sniff(head)
    }

    /// The line a note shows for where its audio came from: "Shared: PTT-20261117-WA0003.opus (Ogg Opus)",
    /// "Video: soundtrack of IMG_0042.MOV".
    static func sourceLine(name: String, container: AudioContainer, prefix: String = "") -> String {
        // A video container named as a video. (A .3gp or .mp4 can also be a voice memo with no picture.)
        let videoNames = ["mov", "mp4", "m4v", "3gp", "3g2", "webm", "mkv"]
        if container.mayHoldVideo, videoNames.contains((name as NSString).pathExtension.lowercased()) {
            return prefix + "Video: soundtrack of \(name)"
        }
        switch container {
        case .unknown: return prefix + name
        default: return prefix + "\(name) (\(container.name))"
        }
    }
}
