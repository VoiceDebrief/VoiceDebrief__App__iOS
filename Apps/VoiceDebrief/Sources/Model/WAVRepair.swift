import Foundation

/// Makes a recording readable after the app died while it was being written.
///
/// A WAV file states its length in two places in its header, and a recorder fills them in when it
/// closes the file. If the app is killed first, the audio is on disk but the header still says
/// there is none. The fix is to write the real lengths in. This is why recordings are made as WAV
/// and only compressed afterwards: a compressed .m4a that was never closed cannot be recovered.
enum WAVRepair {
    struct Fix: Equatable {
        /// Value for bytes 4..<8: the file's length minus 8.
        let riffSize: UInt32
        /// Where the data chunk's size field is, and what it should hold.
        let dataSizeOffset: Int
        let dataSize: UInt32
    }

    /// What the header should say for a file of this length, or nil if this is not a WAV file
    /// with a data chunk in its first bytes. `prefix` is the start of the file (a few kilobytes).
    static func fix(prefix: Data, fileLength: Int) -> Fix? {
        let bytes = [UInt8](prefix)
        guard bytes.count >= 12, fileLength >= 12,
              bytes[0..<4].elementsEqual("RIFF".utf8), bytes[8..<12].elementsEqual("WAVE".utf8) else { return nil }
        var offset = 12
        while offset + 8 <= bytes.count {
            let size = Int(UInt32(bytes[offset + 4]) | UInt32(bytes[offset + 5]) << 8
                           | UInt32(bytes[offset + 6]) << 16 | UInt32(bytes[offset + 7]) << 24)
            if bytes[offset..<(offset + 4)].elementsEqual("data".utf8) {
                let dataStart = offset + 8
                guard fileLength >= dataStart else { return nil }
                return Fix(riffSize: clamp(fileLength - 8), dataSizeOffset: offset + 4, dataSize: clamp(fileLength - dataStart))
            }
            offset += 8 + size + (size & 1)
        }
        return nil
    }

    static func clamp(_ value: Int) -> UInt32 {
        UInt32(min(max(value, 0), Int(UInt32.max)))
    }

    static func littleEndian(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    /// Repairs the file in place if its header is behind its length. Returns true if it changed anything.
    @discardableResult
    static func repair(fileAt url: URL) -> Bool {
        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd(), (try? handle.seek(toOffset: 0)) != nil,
              let prefix = try? handle.read(upToCount: 8192),
              let fix = fix(prefix: prefix, fileLength: Int(length)) else { return false }
        let bytes = [UInt8](prefix)
        let current = Data(bytes[fix.dataSizeOffset..<(fix.dataSizeOffset + 4)])
        let currentRiff = Data(bytes[4..<8])
        if current == littleEndian(fix.dataSize), currentRiff == littleEndian(fix.riffSize) { return false }
        do {
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: littleEndian(fix.riffSize))
            try handle.seek(toOffset: UInt64(fix.dataSizeOffset))
            try handle.write(contentsOf: littleEndian(fix.dataSize))
            return true
        } catch {
            return false
        }
    }
}
