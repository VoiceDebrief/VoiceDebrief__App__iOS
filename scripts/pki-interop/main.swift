// pki-interop: the app's PKIKit, compiled on its own for a Mac, so that pki-interop.yml can have sgit and
// pki.sgit.ai's keys.js read what Swift writes, and Swift read what they write, without a simulator.
// Built by build.sh from the app's own source files: nothing here is a second implementation.
//
//   pki-interop read <sgit-made.json> <keysjs-made.json>              Swift reads theirs
//   pki-interop make <out folder> <sgit-made.json> <keysjs-made.json>  Swift makes its own, for them to read
//
// Every key it makes is for the run and protects nothing.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("pki-interop: " + message + "\n").utf8))
    exit(1)
}

func fixture(_ path: String) -> [String: String] {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do { return try PKIFixtureChecks.load(data) } catch { fail("\(path): \(error)") }
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first ?? "" {
    case "read" where arguments.count == 3:
        for line in try PKIFixtureChecks.sgit(fixture(arguments[1])) { print("- sgit → Swift: \(line)") }
        for line in try PKIFixtureChecks.keysjs(fixture(arguments[2])) { print("- keys.js → Swift: \(line)") }

    case "make" where arguments.count == 4:
        let out = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String) throws {
            let url = out.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let sgit = try PKIBundle(json: try PKIJSON(parsing: Data(try PKIFixtureChecks.field(fixture(arguments[2]), "bundle").utf8)))
        let keysjs = try PKIFixtureChecks.identity(try PKIFixtureChecks.field(fixture(arguments[3]), "identity")).bundle

        let started = Date()
        let me = try PKI.generate(label: "Swift interop (throwaway) “é 日本”")
        print("- Swift made an RSA-4096 and P-256 identity in \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(me.bundle.fingerprint), \(me.bundle.signingFingerprint)")
        guard PKI.problems(of: me.bundle).isEmpty else { fail("Swift's own bundle is not sound: \(PKI.problems(of: me.bundle))") }

        try write("bundle.json", me.bundle.json + "\n")
        try write("k1.txt", try PKI.keyCode(me.bundle))
        try write("private-encrypt.pkcs8.b64", me.encryptPKCS8.base64EncodedString())
        try write("private-sign.pkcs8.b64", me.signPKCS8.base64EncodedString())

        let message = "signed and sealed by Swift: “quotes”, é, 日本, 😀\n"
        try write("message.txt", message)
        try write("message.txt.sig", try PKI.detachedSignature(over: Data(message.utf8), by: me))
        try write("to-sgit.enc", try PKI.seal(Data(message.utf8), to: sgit, signedBy: me))
        try write("to-keysjs.enc", try PKI.seal(Data(message.utf8), to: keysjs, signedBy: me))
        try write("to-self.enc", try PKI.seal(Data(message.utf8), to: me.bundle, signedBy: me))
        try write("unsigned-to-self.enc", try PKI.seal(Data(message.utf8), to: me.bundle))

        // The vouching statement, as the app writes it into a vault: a device key, vouched for by the user's key.
        let device = P256.Signing.PrivateKey()
        let vouch = try IdentityVouch.make(for: IdentityVouch.Device(publicKeyPEM: PKI.pem(device.publicKey.derRepresentation, label: "PUBLIC KEY"),
                                                                     keyId: "key-rnd-imm-0123456789abcdef", name: "a test device “é”", kept: "software"),
                                           by: me, at: Date(timeIntervalSince1970: 1_794_564_000))
        _ = try IdentityVouch.check(vouch)
        try write("statement.json", String(decoding: IdentityVouch.fileData(vouch), as: UTF8.self))
        try write("statement-canonical.txt", String(decoding: PKI.canonicalBytes(vouch), as: UTF8.self))
        try write("statement-id.txt", PKI.statementId(vouch))

        let cases: [PKIJSON] = [
            .object(["b": .int(1), "a": .int(2), "é": .int(3), "Z": .int(4), "😀": .int(5), "\u{FFFF}": .int(6), "aa": .int(7), "": .int(8)]),
            .array([.string(""), .string("a/b"), .string("\u{7F}"), .string("\u{2028}"), .string("\u{0}"), .string("\u{1F}"), .string("\\"), .string("\""), .string("</script>")]),
            .object(["nested": .object(["y": .array([]), "x": .object([:])]), "n": .int(9_007_199_254_740_991), "m": .int(-1), "t": .bool(true), "f": .bool(false), "z": .null]),
        ]
        // Each case as { value, canon }: `value` is ordinary JSON for the reader to parse, `canon` what Swift says its canonical form is.
        try write("canon-cases.json", "[" + cases.map { "{\"value\":\($0.canonical),\"canon\":\(PKIJSON.quote($0.canonical))}" }.joined(separator: ",") + "]\n")

        let request = try PKIDelegation.request(for: me.bundle, label: "VoiceDebrief interop")
        try write("request.json", request.json.canonical)
        try write("request-url.txt", request.url)

        let passphrase = "throwaway passphrase, protects nothing"
        let store = try PKI.keystoreFiles(me, passphrase: passphrase)
        for (name, text) in store.files { try write("keystore/\(store.folder)/\(name)", text) }
        try write("keystore-passphrase.txt", passphrase)
        print("- Swift wrote a bundle, a k1 code, a detached signature, four envelopes, a vouching statement, a sign-in request and an sgit key store to \(out.path)")

    default:
        fail("usage: pki-interop read <sgit-made.json> <keysjs-made.json> | make <out> <sgit-made.json> <keysjs-made.json>")
    }
} catch {
    fail("\(error)")
}
