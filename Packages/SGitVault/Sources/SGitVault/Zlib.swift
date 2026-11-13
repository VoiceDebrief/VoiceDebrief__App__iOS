import Compression
import Foundation

/// zlib (RFC 1950) on top of Apple's Compression framework.
///
/// Apple's `COMPRESSION_ZLIB` is raw deflate (RFC 1951): no 2-byte header and no
/// 4-byte Adler-32 trailer. Python's `zlib.compress` writes both, so we strip
/// them on the way in (checking the Adler-32) and add them on the way out.
public enum Zlib {
    /// The most a blob may inflate to (64 MB). A deflate bomb stops here instead of filling memory.
    public static let maxInflatedBytes = 64 * 1024 * 1024

    /// Inflate a zlib stream. Nil when the header, the deflate data or the checksum is bad,
    /// or when the output would pass `limit` bytes.
    public static func decompress(_ data: Data, limit: Int = maxInflatedBytes) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let cmf = bytes[0], flg = bytes[1]
        guard cmf & 0x0F == 8,                              // deflate
              (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0,   // header check
              flg & 0x20 == 0                               // no preset dictionary
        else { return nil }
        let raw = Data(bytes[2..<(bytes.count - 4)])
        let trailer = bytes[(bytes.count - 4)...]
        let expected = trailer.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard let inflated = inflateRaw(raw, limit: limit) else { return nil }
        guard adler32(inflated) == expected else { return nil }
        return inflated
    }

    /// Raw deflate → bytes, through a streaming decoder that stops as soon as the output passes `limit`.
    static func inflateRaw(_ input: Data, limit: Int) -> Data? {
        guard !input.isEmpty else { return nil }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(stream) }
        let chunk = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var output = Data()
        return input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data? in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else { return nil }
                output.append(buffer, count: chunk - stream.pointee.dst_size)
                if output.count > limit { return nil }
                if status == COMPRESSION_STATUS_END { return output }
                if stream.pointee.src_size == 0 && stream.pointee.dst_size == chunk { return nil }   // no progress: truncated
            }
        }
    }

    /// Deflate into a zlib stream (header 0x78 0x9C, Adler-32 trailer).
    public static func compress(_ data: Data) -> Data? {
        guard let raw = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }
        var out = Data([0x78, 0x9C])
        out.append(raw)
        let sum = adler32(data)
        out.append(contentsOf: [UInt8(sum >> 24 & 0xFF), UInt8(sum >> 16 & 0xFF),
                                UInt8(sum >> 8 & 0xFF), UInt8(sum & 0xFF)])
        return out
    }

    public static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        let mod: UInt32 = 65521
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var index = 0
            let count = buffer.count
            while index < count {
                let end = min(index + 5552, count)          // largest run without overflow
                while index < end {
                    a &+= UInt32(buffer[index])
                    b &+= a
                    index += 1
                }
                a %= mod
                b %= mod
            }
        }
        return b << 16 | a
    }
}
