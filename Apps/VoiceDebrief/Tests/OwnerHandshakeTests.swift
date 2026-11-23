import CryptoKit
import Foundation
import SGitPeople
import Testing
@testable import VoiceDebrief

/// The handshake, checked against what the owner's side really makes: the request below was made by a throwaway
/// P-256 key standing in for a device, and the grant by `tools/owner/grant.py` with stock sgit-ai 0.27.0 and
/// a.ios's own key (signing fingerprint sha256:fe92eabba46bb9ca, public in website/identity/agent-keys.json).
/// Both are public: a signature and public keys, nothing that opens anything.
@Suite("Owner mode: the handshake")
struct OwnerHandshakeTests {
    static let pythonRequest = "or1.eyJhcHAiOiJhaS52b2ljZWRlYnJpZWYuYXBwIiwiYXQiOiIyMDI2LTExLTIzVDE5OjAwOjAwWiIsImRldmljZSI6InNoYTI1Njo4OGQ0ZTY5ZWQ0Y2FmZGViIiwiZGV2aWNlS2V5IjoiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Ga3dFd1lIS29aSXpqMENBUVlJS29aSXpqMERBUWNEUWdBRUpXTmUrV0h1QWFPaVNmUmorbVN5ZGRjUW5XL0dcbkRreUVZWlVJdkhXNFdOZHNHdlRTdllqNElzL1k2UDJxRlU2SXdqT1dNNkFBS3Z2RnV2VFh4TzN2Vnc9PVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tXG4iLCJrZXB0Ijoic2VjdXJlLWVuY2xhdmUiLCJraW5kIjoib3duZXIucmVxdWVzdC92MSIsImxhYmVsIjoiVGVzdCBpUGFkIChpbnZlbnRlZCkiLCJub25jZSI6Im4xIn0.D2Z1RsGhtfTb_rjnZU__i0ixFvJD3UwVku8wcFEkKUmCpKUCOGgw2s0wAIZQ_eSLmBZYoz1u0JQXq36MFR5EQA"
    static let pythonDevice = "sha256:88d4e69ed4cafdeb"
    static let pythonGrant = "og1.eyJncmFudCI6ImV5SmhjSEFpT2lKaGFTNTJiMmxqWldSbFluSnBaV1l1WVhCd0lpd2laR1YyYVdObElqb2ljMmhoTWpVMk9qZzRaRFJsTmpsbFpEUmpZV1prWldJaUxDSm5jbUZ1ZEdWa0lqb2lNakF5TmkweE1TMHlNMVF4T0RvMU5Ub3pPVm9pTENKcmFXNWtJam9pYjNkdVpYSXVaM0poYm5RdmRqRWlMQ0p1YjNSbElqb2labWw0ZEhWeVpTSXNJbTkzYm1WeUlqb2ljMmhoTWpVMk9tWmxPVEpsWVdKaVlUUTJZbUk1WTJFaUxDSnlaWEYxWlhOMElqb2ljMmhoTWpVMk9qZGtPRGhoT0dGbFltUmtNelF4T0RSbVlXRTVaV1ZoWldVM05UazVNbUptTTJaalpUTXdPRGN3T1RGa1pEVXdOREpsWXpKak56UmhNVGxrTURrMU5UY2lmUT09Iiwib3duZXIiOnsiZW5jcnlwdCI6Ii0tLS0tQkVHSU4gUFVCTElDIEtFWS0tLS0tXG5NSUlDSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DQWc4QU1JSUNDZ0tDQWdFQXUzWXBQTkhzaENZVHhYV2NjdGdzXG5EajkzQW5wWVlKMXBOaVRLY28rcFdLMlVBKzBaOHB4R2hQVzU4MnUxL1VXTzZ6dzJlMkpRNTROT290ZmhjMk5OXG5JaU9KNjhrZlNOWGQzcVhhVGl1UjZSQ1VmZW4xQ0lJSTF5Zi9wUlVHa2JxbUMvMFMvc2pnUHVudlRucXNVdWxkXG5HMmlRZVVPc0psdUpJUkVuNS9lZlNFaHlMVWlsVmJiaE56ZWlIdDNtV3BTdmJveUpSZCtRVkc5a3ltbDNrWHRrXG5zbnNlem9pM2daM2RDNkJRU1B2NzB3L1V2cFZWemFXVU1xYjZZMGFEdVpmSWpVdUw5V2RqL2JsUnpDRXFsNGF0XG53eUpubmdWRndDZ0dvMmhVemdxeGhOdnBrdTVIRjlCWWZWcWlQOWFOdVRQYlJhMlFDSnVxV0ZmMUlJWkdBODhmXG4yTE5tdjBIMURicVF1cGJtdzZlSVlSZ1NXODZlUUtPVVFaK3FqSWlIN016YSsyQXV0WlVQMGFiUllIb2VFSFZzXG5mcUQvV2NrZUxpbDNTLytHaWhLcnhIQkhTWFhXbCttenFtWXVHVjNEbmRqekR3ZWpFODI3T0M4SVpIdHNsWGxFXG56VUhkN3hNUnZHbDZVeXdjeXJBb1ZJZDlvN0p0L1BtWUpUMnREdEJwUVhxazk2d1VLRUNKTitmNStBSlZ5T04wXG5xVnBVazE0azYySHMrcXE3MVp6OXdsaE9hNWtDRFdCYVFmMjBXVUlYaHhZcENCblo0U3ZuVmRjVDJocURmODI5XG5vSU56U1FET21PL1F2MjZnanVzTHVWY0o4RVNsNFpGSEcrWjB1N3pJeW9lWDB2SmRYQm9BYUF1QzBsT3FsRG9XXG5tRnNLM1p4Y0lSK09lUitDcWZqZWtvMENBd0VBQVE9PVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tXG4iLCJmaW5nZXJwcmludCI6InNoYTI1NjoyYzRkOGRiOGE1ZGRiY2FjIiwibGFiZWwiOiJhLmlvcyIsInNpZ24iOiItLS0tLUJFR0lOIFBVQkxJQyBLRVktLS0tLVxuTUZrd0V3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFak1UckQ2U09BeVJOeGk1TVhYQ0x6OUVwaTlScVxuMnJCMHNDRld5ZHJuS3JhTzVVOUNWSnY3aG9ZRVZWSWljVTBuakRnUVhvYVhuSVNXdndNRTh6R2NKUT09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS1cbiIsInNpZ25pbmdfZmluZ2VycHJpbnQiOiJzaGEyNTY6ZmU5MmVhYmJhNDZiYjljYSIsInYiOjF9LCJzaWciOiJ7XG4gIFwic2lnbmF0dXJlXCI6IFwiZUVaQzZwWWJNaStHMFBmS3ZkS1JTS1dkc0ZXYjJIL1hXUHpKNC9qSElOdlBZWHdJQ1ZUSWNrbFc3R3gyc3A0d2V1UFhkK0hGNk51Ui8zMHBFQVBrRGc9PVwiLFxuICBcImZpbmdlcnByaW50XCI6IFwic2hhMjU2OmZlOTJlYWJiYTQ2YmI5Y2FcIlxufSJ9"
    static let aIos = "sha256:fe92eabba46bb9ca"

    @Test func aGrantMadeBySgitIsAcceptedWhenItsKeyIsPinned() throws {
        let accepted = try OwnerHandshake.verify(Self.pythonGrant, deviceFingerprint: Self.pythonDevice, pinned: [Self.aIos])
        #expect(accepted.owner.signingFingerprint == Self.aIos)
        #expect(accepted.grant.device == Self.pythonDevice)
        #expect(accepted.grant.note == "fixture")
        // It names the request it answers.
        let (_, bytes) = try OwnerHandshake.readRequest(Self.pythonRequest)
        #expect(accepted.grant.request == OwnerHandshake.requestId(bytes))
    }

    @Test func withNoOwnerPinnedNothingIsAccepted() {
        #expect(throws: OwnerHandshake.Failure.noOwnerPinned) {
            try OwnerHandshake.verify(Self.pythonGrant, deviceFingerprint: Self.pythonDevice, pinned: [])
        }
        // This build pins nobody yet: the owner gives his fingerprint first.
        #expect(OwnerHandshake.pinnedOwners.isEmpty)
    }

    @Test func aKeyThatIsNotPinnedIsRefused() {
        #expect(throws: OwnerHandshake.Failure.ownerNotPinned(Self.aIos)) {
            try OwnerHandshake.verify(Self.pythonGrant, deviceFingerprint: Self.pythonDevice, pinned: ["sha256:0000000000000000"])
        }
    }

    @Test func aGrantForAnotherDeviceIsRefused() {
        #expect(throws: OwnerHandshake.Failure.otherDevice) {
            try OwnerHandshake.verify(Self.pythonGrant, deviceFingerprint: "sha256:1111111111111111", pinned: [Self.aIos])
        }
    }

    @Test func aChangedGrantIsRefused() throws {
        // Swap one byte of the grant inside the envelope: the signature no longer covers it.
        let body = String(Self.pythonGrant.dropFirst(4))
        var envelope = try JSONDecoder().decode(OwnerHandshake.Envelope.self, from: try #require(PKI.data(base64url: body)))
        var grant = try #require(Data(base64Encoded: envelope.grant))
        grant[grant.count - 3] ^= 0x01
        envelope.grant = grant.base64EncodedString()
        let tampered = "og1." + PKI.base64url(try JSONEncoder().encode(envelope))
        #expect(throws: OwnerHandshake.Failure.badSignature) {
            try OwnerHandshake.verify(tampered, deviceFingerprint: Self.pythonDevice, pinned: [Self.aIos])
        }
    }

    @Test func aRequestMadeElsewhereReadsAndAChangedOneDoesNot() throws {
        let (request, _) = try OwnerHandshake.readRequest("Register me: " + Self.pythonRequest)
        #expect(request.device == Self.pythonDevice)
        #expect(request.kept == "secure-enclave")
        // The same signature over a request whose device name was changed on the way.
        let parts = Self.pythonRequest.dropFirst(4).split(separator: ".").map(String.init)
        let json = try #require(String(data: try #require(PKI.data(base64url: parts[0])), encoding: .utf8))
        let changed = json.replacingOccurrences(of: "Test iPad (invented)", with: "Someone else's iPad")
        #expect(changed != json)
        #expect(throws: OwnerHandshake.Failure.badSignature) {
            try OwnerHandshake.readRequest("or1." + PKI.base64url(Data(changed.utf8)) + "." + parts[1])
        }
        #expect(throws: OwnerHandshake.Failure.notARequest) { try OwnerHandshake.readRequest("hello") }
    }

    @Test func theAppsOwnRequestRoundTrips() throws {
        let key = P256.Signing.PrivateKey()
        let pem = PKI.pem(key.publicKey.derRepresentation, label: "PUBLIC KEY")
        let fingerprint = LaneCrypto.fingerprint(spki: key.publicKey.derRepresentation)
        let text = try OwnerHandshake.request(deviceKeyPEM: pem, fingerprint: fingerprint, kept: "keychain-this-device", label: "Test",
                                              at: Date(timeIntervalSince1970: 0), nonce: "n") { try key.signature(for: $0).rawRepresentation }
        #expect(text.hasPrefix("or1."))
        let (request, _) = try OwnerHandshake.readRequest(text)
        #expect(request.device == fingerprint)
        #expect(request.app == OwnerHandshake.app)
    }
}
