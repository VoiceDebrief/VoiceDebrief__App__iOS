import CryptoKit
import Foundation

/// Sending a voice note to the developer, by the user's choice, for judging Apple's models on real
/// notes. The note goes to an sgit append lane: a write-only channel on a vault server. It is
/// encrypted on this device to the developer's public key, so the server stores bytes it cannot read.
///
/// A lane is a link, `sgi1.<vault>.<token>.<public key>`, the form newsroom.sgit.ai and the PrompTugal
/// apps already use. One is built in, so that a test build can send without setting anything up; a
/// link pasted on the Diagnostics tab takes its place. Either way nothing is sent without the button.
struct DeveloperLane: Equatable, Sendable {
    let vault: String
    let token: String
    let publicKeyPEM: String
    let fingerprint: String

    /// The developer's lane during the test period (13 November 2026). Committed on purpose, at the
    /// owner's request: a lane link holds a vault id, a token that can only write, and a public key.
    /// It cannot read the lane or decrypt anything. The private key is held by the developer session
    /// that made it; when that session ends the lane goes dead and this link must be replaced.
    static let builtInLink = "sgi1.fjq2ekcw.e123c04c7e9a754afd2c37340b2ba786fc34de3729c33042.MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsy-kwYsyRxMcnEwiMTZZYDDUUhVwBOamnuBL4Q_w8MweDR7-y7tugd4s1TGpU3M_eY0-7Pb60WReUoxCnfcmEnEq6WDuEzxlLxHnr5vALhcap8xbnTWG_udhfuOYkCIMqKaP4cTb4nYS82Uo-TkFu1JWa3b0Cdc1nIXZlzphfq3XHzfKkFCc6GIxTPpXc7OLmfcx5aqDcw56heNeMPjXuPadNabwjHyxffTKxtgepYgTPPo7jMMFi7cGmLo2XAfCz0vCxNYExaJXBg9HRonHIpcj-CS1wu9-puVCvMAp8w8O4JorcjucjhuKOv7zKu63jM1F1ArxovXGNDed7LBuV0ZWdBW-99T_OpOIMOmm-iF9o3oyoQgbVYBJhaDIr8IvHiGb6DHAnrF2I8b0je50uFAH0P-3IqsdUsrX-9_0uegopTcgTwxvgPTNzKLejjpJJa-Wvs0nkYRO-OzargFsf2RuQCzOoszmgvzO3FH-wR2o3fGpYOaV79LXqpiVlbf8VF4eh6s93qLxrmBE50trq4pB3ifyUiuH8zO0-Pv3UwvCDbaOHojHYCDY7wOtWzAqgtsteOQmUA7z8fKGraLUjHMiZlqC-JC_XhWxHtN7ZI3ulRmSaMdWKMt9j4aPUTt2-XuWs4Bq81JIdst_XWwO6AEeXUqLmMzn-1tM15TcKU0CAwEAAQ"
    static let builtInFingerprint = "sha256:81021cb4dd6d073e"

    static var builtIn: DeveloperLane? { parse(builtInLink) }

    /// The lane to send to: a valid pasted link if there is one, otherwise the built-in lane.
    static func current(pasted: String) -> DeveloperLane? {
        parse(pasted) ?? builtIn
    }

    /// The one host with the append routes (sgit.ai /api/append-lanes). Not configurable.
    static let endpoint = URL(string: "https://dev.send.sgraph.ai")!
    /// Raw bytes per message. Encrypting and encoding twice makes a message about 1.8 times this, and
    /// the server refuses a payload over 5 MB.
    static let partSize = 2_000_000

    var writeURL: URL { Self.endpoint.appendingPathComponent("api/vault/append/write/\(vault)") }

    /// A lane from an `sgi1.` link, alone or inside other text. Nil if there is none, or its key is not RSA.
    static func parse(_ text: String) -> DeveloperLane? {
        guard let match = text.firstMatch(of: #/sgi1\.([a-z0-9]{4,24})\.([0-9a-f]{16,128})\.([A-Za-z0-9_-]{200,3000})/#) else { return nil }
        var base64 = String(match.3).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let spki = Data(base64Encoded: base64), (try? LaneCrypto.pkcs1(fromSPKI: spki)) != nil else { return nil }
        return DeveloperLane(vault: String(match.1), token: String(match.2),
                             publicKeyPEM: LaneCrypto.pem(spki: spki), fingerprint: LaneCrypto.fingerprint(spki: spki))
    }

    // MARK: What is sent

    /// The first line of every message: what it is and which note it belongs to.
    struct Header: Codable, Equatable, Sendable {
        var kind: String
        var note: String
        var part: Int
        var of: Int
        var name: String
        var size: Int
        var sha256: String
        var app: String
        var sentAt: String

        static let audioKind = "voicedebrief/audio/v1"
        static let runKind = "voicedebrief/run/v1"
        static let cleanKind = "voicedebrief/clean/v1"
    }

    /// A file's bytes cut into pieces of at most `size`. An empty file has no pieces.
    static func parts(of data: Data, size: Int = partSize) -> [Data] {
        guard size > 0 else { return [] }
        var out: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            out.append(data.subdata(in: start..<end))
            start = end
        }
        return out
    }

    /// One message before encryption: the header as one line of JSON, a newline, then the bytes.
    static func message(header: Header, body: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var out = try encoder.encode(header)
        out.append(0x0A)
        out.append(body)
        return out
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Every message for one note: the audio in parts, then the run (transcript, debrief, timings) as JSON.
    static func messages(audio: Data, audioName: String, run: DebriefRun, clean: CleanText? = nil, noteId: String, app: String, at date: Date) throws -> [Data] {
        let sentAt = ISO8601DateFormatter().string(from: date)
        let pieces = parts(of: audio)
        let digest = sha256Hex(audio)
        var out: [Data] = []
        for (index, piece) in pieces.enumerated() {
            let header = Header(kind: Header.audioKind, note: noteId, part: index + 1, of: pieces.count, name: audioName,
                                size: audio.count, sha256: digest, app: app, sentAt: sentAt)
            out.append(try message(header: header, body: piece))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let runJSON = try encoder.encode(run)
        let header = Header(kind: Header.runKind, note: noteId, part: 1, of: 1, name: "run.json",
                            size: runJSON.count, sha256: sha256Hex(runJSON), app: app, sentAt: sentAt)
        out.append(try message(header: header, body: runJSON))
        if let clean {
            encoder.dateEncodingStrategy = .iso8601
            let cleanJSON = try encoder.encode(clean)
            let cleanHeader = Header(kind: Header.cleanKind, note: noteId, part: 1, of: 1, name: "clean.json",
                                     size: cleanJSON.count, sha256: sha256Hex(cleanJSON), app: app, sentAt: sentAt)
            out.append(try message(header: cleanHeader, body: cleanJSON))
        }
        return out
    }

    // MARK: Sending

    enum SendError: LocalizedError {
        case refused(Int)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .refused(let status):
                return status == 404 ? "The lane refused the note (404): the link may be out of date."
                                     : "The lane refused the note (status \(status))."
            case .tooLarge:
                return "The lane refused the note as too large."
            }
        }
    }

    /// Encrypts each message to the developer's key and appends it to the lane. The server's answer is
    /// blind by design: it says only that the write was accepted.
    func send(_ messages: [Data], onProgress: @escaping @Sendable (Int, Int) -> Void) async throws {
        let key = try LaneCrypto.publicKey(pem: publicKeyPEM)
        for (index, message) in messages.enumerated() {
            onProgress(index + 1, messages.count)
            let payload = LaneCrypto.lanePayload(encText: try LaneCrypto.encrypt(message, to: key))
            var request = URLRequest(url: writeURL, timeoutInterval: 120)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["append_token": token, "payload": payload],
                                                          options: [.sortedKeys])
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 413 { throw SendError.tooLarge }
            guard (200..<300).contains(status) else { throw SendError.refused(status) }
        }
    }
}
