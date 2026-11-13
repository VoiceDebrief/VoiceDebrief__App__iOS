import CommonCrypto
import CryptoKit
import Foundation

/// AES-256-GCM a piece at a time, so a file of any size can be sealed or opened in constant memory.
///
/// sgit stores a blob as one AES-GCM message: iv(12) + ciphertext + tag(16). CryptoKit seals a message
/// only when it holds all of it, which for a video means the whole file and the whole ciphertext in
/// memory at once. This type produces and reads the same bytes from a stream:
///
/// - the counter-mode keystream comes from CommonCrypto (AES-CTR, big-endian counter starting at iv‖2);
/// - the authentication tag is GHASH over the ciphertext, computed here with 4-bit tables, masked with
///   AES(iv‖1), as NIST SP 800-38D defines it for a 96-bit iv and no associated data.
///
/// The tests seal with this and open with CryptoKit, and the reverse, at every awkward length.
/// When opening, plaintext comes out before the tag has been checked: the caller must not use it until
/// `finish` has returned (see `VaultFileCipher.open`, which deletes its output when the tag is wrong).
public final class VaultGCMStream {
    public enum Direction: Sendable { case seal, open }

    private let direction: Direction
    private var cryptor: CCCryptorRef?
    private var tableHigh = [UInt64](repeating: 0, count: 16)
    private var tableLow = [UInt64](repeating: 0, count: 16)
    private var hashHigh: UInt64 = 0
    private var hashLow: UInt64 = 0
    private var maskHigh: UInt64 = 0
    private var maskLow: UInt64 = 0
    /// Ciphertext bytes that do not yet make a whole 16-byte block.
    private var pending: [UInt8] = []
    private var ciphertextBytes: UInt64 = 0

    private static let reduction: [UInt64] = [
        0x0000, 0x1c20, 0x3840, 0x2460, 0x7080, 0x6ca0, 0x48c0, 0x54e0,
        0xe100, 0xfd20, 0xd940, 0xc560, 0x9180, 0x8da0, 0xa9c0, 0xb5e0,
    ]

    public init(key: SymmetricKey, iv: Data, direction: Direction) throws {
        guard iv.count == VaultCrypto.ivBytes, key.bitCount == 256 else {
            throw VaultError.malformed(path: "stream cipher", detail: "needs a 256-bit key and a 12-byte iv")
        }
        self.direction = direction
        let keyBytes = key.withUnsafeBytes { Array($0) }
        let ivBytes = Array(iv)

        // H = AES(0), the hash key; and AES(iv‖1), which masks the tag.
        let hashKey = try Self.encryptBlock([UInt8](repeating: 0, count: 16), key: keyBytes)
        let mask = try Self.encryptBlock(ivBytes + [0, 0, 0, 1], key: keyBytes)
        maskHigh = Self.word(mask, 0)
        maskLow = Self.word(mask, 8)
        buildTables(high: Self.word(hashKey, 0), low: Self.word(hashKey, 8))

        var made: CCCryptorRef?
        let counter = ivBytes + [0, 0, 0, 2]
        let status = CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                             CCPadding(ccNoPadding), counter, keyBytes, keyBytes.count,
                                             nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &made)
        guard Int(status) == kCCSuccess, made != nil else {
            throw VaultError.malformed(path: "stream cipher", detail: "AES-CTR could not start (\(status))")
        }
        cryptor = made
    }

    deinit {
        if let cryptor { CCCryptorRelease(cryptor) }
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var out: UInt64 = 0
        for i in 0..<8 { out = (out << 8) | UInt64(bytes[offset + i]) }
        return out
    }

    private static func encryptBlock(_ block: [UInt8], key: [UInt8]) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, block, 16, &out, 16, &moved)
        guard Int(status) == kCCSuccess, moved == 16 else {
            throw VaultError.malformed(path: "stream cipher", detail: "AES block failed (\(status))")
        }
        return out
    }

    /// The sixteen multiples of H that the 4-bit multiplication looks up.
    private func buildTables(high: UInt64, low: UInt64) {
        tableHigh[8] = high
        tableLow[8] = low
        var vh = high
        var vl = low
        var i = 4
        while i > 0 {
            let carry: UInt64 = (vl & 1) == 1 ? 0xe100_0000 : 0
            vl = (vh << 63) | (vl >> 1)
            vh = (vh >> 1) ^ (carry << 32)
            tableLow[i] = vl
            tableHigh[i] = vh
            i >>= 1
        }
        i = 2
        while i <= 8 {
            let bh = tableHigh[i]
            let bl = tableLow[i]
            for j in 1..<i {
                tableHigh[i + j] = bh ^ tableHigh[j]
                tableLow[i + j] = bl ^ tableLow[j]
            }
            i *= 2
        }
    }

    /// (xh‖xl) × H in GF(2^128), a nibble at a time from the least significant.
    @inline(__always)
    private static func multiply(_ xh: UInt64, _ xl: UInt64, _ th: UnsafeBufferPointer<UInt64>,
                                 _ tl: UnsafeBufferPointer<UInt64>, _ red: UnsafeBufferPointer<UInt64>) -> (UInt64, UInt64) {
        var nibble = Int(truncatingIfNeeded: xl & 0xf)
        var zh = th[nibble]
        var zl = tl[nibble]
        for k in 1..<32 {
            let source = k < 16 ? xl : xh
            nibble = Int(truncatingIfNeeded: (source >> UInt64(4 * (k & 15))) & 0xf)
            let rem = Int(truncatingIfNeeded: zl & 0xf)
            zl = (zh << 60) | (zl >> 4)
            zh = (zh >> 4) ^ (red[rem] << 48)
            zh ^= th[nibble]
            zl ^= tl[nibble]
        }
        return (zh, zl)
    }

    /// Feeds ciphertext into the tag.
    private func absorb(_ data: Data) {
        guard !data.isEmpty else { return }
        ciphertextBytes += UInt64(data.count)
        var yh = hashHigh
        var yl = hashLow
        var carried = pending
        tableHigh.withUnsafeBufferPointer { th in
            tableLow.withUnsafeBufferPointer { tl in
                Self.reduction.withUnsafeBufferPointer { red in
                    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                        var offset = 0
                        let count = raw.count
                        if !carried.isEmpty {
                            while carried.count < 16, offset < count {
                                carried.append(raw[offset])
                                offset += 1
                            }
                            if carried.count == 16 {
                                (yh, yl) = Self.multiply(yh ^ Self.word(carried, 0), yl ^ Self.word(carried, 8), th, tl, red)
                                carried.removeAll(keepingCapacity: true)
                            }
                        }
                        while count - offset >= 16 {
                            let xh = UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                            let xl = UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self))
                            (yh, yl) = Self.multiply(yh ^ xh, yl ^ xl, th, tl, red)
                            offset += 16
                        }
                        while offset < count {
                            carried.append(raw[offset])
                            offset += 1
                        }
                    }
                }
            }
        }
        hashHigh = yh
        hashLow = yl
        pending = carried
    }

    /// The next piece: plaintext in and ciphertext out when sealing, the reverse when opening.
    /// Pieces may be of any length.
    public func update(_ input: Data) throws -> Data {
        guard !input.isEmpty else { return Data() }
        guard let cryptor else { throw VaultError.malformed(path: "stream cipher", detail: "already finished") }
        var output = Data(count: input.count)
        var moved = 0
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                CCCryptorUpdate(cryptor, source.baseAddress, source.count, target.baseAddress, target.count, &moved)
            }
        }
        guard Int(status) == kCCSuccess, moved == input.count else {
            throw VaultError.malformed(path: "stream cipher", detail: "AES-CTR failed (\(status))")
        }
        absorb(direction == .seal ? output : input)
        return output
    }

    /// The 16-byte tag over everything given to `update`. Call once, at the end.
    public func finish() -> Data {
        var yh = hashHigh
        var yl = hashLow
        let bits = ciphertextBytes &* 8
        var last = pending
        tableHigh.withUnsafeBufferPointer { th in
            tableLow.withUnsafeBufferPointer { tl in
                Self.reduction.withUnsafeBufferPointer { red in
                    if !last.isEmpty {
                        while last.count < 16 { last.append(0) }
                        (yh, yl) = Self.multiply(yh ^ Self.word(last, 0), yl ^ Self.word(last, 8), th, tl, red)
                    }
                    // The length block: 64 bits of associated data length (none), 64 bits of ciphertext length.
                    (yh, yl) = Self.multiply(yh, yl ^ bits, th, tl, red)
                }
            }
        }
        pending = []
        if let cryptor { CCCryptorRelease(cryptor) }
        cryptor = nil
        var tag = Data(capacity: 16)
        for word in [yh ^ maskHigh, yl ^ maskLow] {
            for shift in stride(from: 56, through: 0, by: -8) {
                tag.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        return tag
    }
}

/// Sealing and opening whole files with `VaultGCMStream`, a megabyte at a time.
public enum VaultFileCipher {
    public static let pieceBytes = 1 << 20

    /// What sealing a file produced.
    public struct Sealed: Sendable, Equatable {
        public let plaintextBytes: Int
        public let ciphertextBytes: Int
        /// sha256 of the plaintext, hex, first 12: the content hash sgit keeps in a tree entry.
        public let contentHash: String
        /// sha256 of the ciphertext file, hex, all 64: the object id is a prefix of it.
        public let ciphertextSHA256: String
    }

    /// What opening a file produced.
    public struct Opened: Sendable, Equatable {
        public let plaintextBytes: Int
        public let contentHash: String
    }

    private static func handle(reading url: URL) throws -> FileHandle { try FileHandle(forReadingFrom: url) }

    private static func handle(writing url: URL) throws -> FileHandle {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw VaultError.malformed(path: url.lastPathComponent, detail: "could not create the file")
        }
        return try FileHandle(forWritingTo: url)
    }

    public static func byteCount(of url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw VaultError.malformed(path: url.lastPathComponent, detail: "no file size")
        }
        return size
    }

    /// Writes iv + ciphertext + tag for `source` to `destination`, never holding more than one piece.
    /// - Parameter progress: called with the plaintext bytes sealed so far.
    public static func seal(file source: URL, to destination: URL, key: SymmetricKey, iv: Data? = nil,
                            progress: (@Sendable (Int) -> Void)? = nil) throws -> Sealed {
        let nonce = iv ?? Data(AES.GCM.Nonce())
        let stream = try VaultGCMStream(key: key, iv: nonce, direction: .seal)
        let input = try handle(reading: source)
        defer { try? input.close() }
        let output = try handle(writing: destination)
        var finished = false
        defer {
            try? output.close()
            if !finished { try? FileManager.default.removeItem(at: destination) }
        }
        var plainHash = SHA256()
        var cipherHash = SHA256()
        var plainBytes = 0
        try output.write(contentsOf: nonce)
        cipherHash.update(data: nonce)
        var more = true
        while more {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let piece = try input.read(upToCount: pieceBytes), !piece.isEmpty else {
                    more = false
                    return
                }
                plainHash.update(data: piece)
                let sealed = try stream.update(piece)
                cipherHash.update(data: sealed)
                try output.write(contentsOf: sealed)
                plainBytes += piece.count
            }
            progress?(plainBytes)
        }
        let tag = stream.finish()
        try output.write(contentsOf: tag)
        cipherHash.update(data: tag)
        finished = true
        return Sealed(plaintextBytes: plainBytes,
                      ciphertextBytes: plainBytes + VaultCrypto.ivBytes + VaultCrypto.tagBytes,
                      contentHash: String(Data(plainHash.finalize()).hexString.prefix(12)),
                      ciphertextSHA256: Data(cipherHash.finalize()).hexString)
    }

    /// Opens iv + ciphertext + tag from `source` into `destination`. When the tag does not verify the
    /// destination is deleted and `VaultError.decryptFailed` is thrown: nothing unauthenticated is left.
    /// - Parameter progress: called with the plaintext bytes written so far.
    public static func open(file source: URL, to destination: URL, key: SymmetricKey,
                            progress: (@Sendable (Int) -> Void)? = nil) throws -> Opened {
        let total = try byteCount(of: source)
        let overhead = VaultCrypto.ivBytes + VaultCrypto.tagBytes
        guard total >= overhead else { throw VaultError.decryptFailed(path: source.lastPathComponent) }
        let input = try handle(reading: source)
        defer { try? input.close() }
        guard let iv = try input.read(upToCount: VaultCrypto.ivBytes), iv.count == VaultCrypto.ivBytes else {
            throw VaultError.decryptFailed(path: source.lastPathComponent)
        }
        let stream = try VaultGCMStream(key: key, iv: iv, direction: .open)
        let output = try handle(writing: destination)
        var verified = false
        defer {
            try? output.close()
            if !verified { try? FileManager.default.removeItem(at: destination) }
        }
        var plainHash = SHA256()
        var remaining = total - overhead
        var written = 0
        while remaining > 0 {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let piece = try input.read(upToCount: min(pieceBytes, remaining)), !piece.isEmpty else {
                    throw VaultError.decryptFailed(path: source.lastPathComponent)
                }
                let plain = try stream.update(piece)
                plainHash.update(data: plain)
                try output.write(contentsOf: plain)
                remaining -= piece.count
                written += plain.count
            }
            progress?(written)
        }
        let expected = stream.finish()
        guard let tag = try input.read(upToCount: VaultCrypto.tagBytes), tag.count == VaultCrypto.tagBytes else {
            throw VaultError.decryptFailed(path: source.lastPathComponent)
        }
        var difference: UInt8 = 0
        for (a, b) in zip(tag, expected) { difference |= a ^ b }
        guard difference == 0 else { throw VaultError.decryptFailed(path: source.lastPathComponent) }
        verified = true
        return Opened(plaintextBytes: written,
                      contentHash: String(Data(plainHash.finalize()).hexString.prefix(12)))
    }

    /// sha256 of a file, hex, read a piece at a time.
    public static func sha256(of url: URL) throws -> String {
        let input = try handle(reading: url)
        defer { try? input.close() }
        var hash = SHA256()
        var more = true
        while more {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let piece = try input.read(upToCount: pieceBytes), !piece.isEmpty else {
                    more = false
                    return
                }
                hash.update(data: piece)
            }
        }
        return Data(hash.finalize()).hexString
    }

    /// The first bytes of a file (to recognise the deflate envelope without reading the file).
    public static func prefix(of url: URL, count: Int) throws -> Data {
        let input = try handle(reading: url)
        defer { try? input.close() }
        return try input.read(upToCount: count) ?? Data()
    }
}
