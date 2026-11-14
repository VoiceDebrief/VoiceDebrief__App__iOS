import Foundation
@testable import SGitPeople

/// Throwaway people for the tests, made in the test run and never written anywhere. RSA 2048, because 4096 takes
/// seconds; one 4096-bit card is made where its size is what is being tested.
enum People {
    // swiftlint:disable force_try
    static let ana: PKIIdentity = try! PKI.generate(label: "Ana", rsaBits: 2048, now: Date(timeIntervalSince1970: 1_794_600_000))
    static let ben: PKIIdentity = try! PKI.generate(label: "Ben", rsaBits: 2048, now: Date(timeIntervalSince1970: 1_794_600_000))
    static let eve: PKIIdentity = try! PKI.generate(label: "Eve", rsaBits: 2048, now: Date(timeIntervalSince1970: 1_794_600_000))
    // swiftlint:enable force_try

    /// A whole second, so that ISO 8601 round trips compare equal.
    static let now = Date(timeIntervalSince1970: 1_794_650_000)

    static let anaInbox = InboxAddress(server: "https://dev.send.sgraph.ai", vault: "anainbox",
                                       append: "00112233445566778899aabbccddeeff0011223344556677")
    static let benInbox = InboxAddress(server: "https://dev.send.sgraph.ai", vault: "beninbox",
                                       append: "8899aabbccddeeff00112233445566778899aabbccddeeff")

    static func card(_ who: PKIIdentity, _ name: String, inbox: InboxAddress?, at date: Date = now) throws -> ContactCard {
        try ContactCard.make(name: name, identity: who, inbox: inbox, at: date)
    }

    static func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sgitpeople-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Plays back recorded answers, one per call, in order, and keeps what was asked.
final class ReplayLaneHTTP: LaneHTTP, @unchecked Sendable {
    struct Call {
        var url: URL
        var body: [String: Any]
        var headers: [String: String]
        var operation: String { url.deletingLastPathComponent().lastPathComponent }
    }

    struct Unexpected: Error, CustomStringConvertible {
        var description: String
    }

    private let lock = NSLock()
    private var answers: [(operation: String, status: Int, body: String)]
    private(set) var calls: [Call] = []

    init(_ answers: [(operation: String, status: Int, body: String)]) {
        self.answers = answers
    }

    var remaining: Int {
        lock.lock(); defer { lock.unlock() }
        return answers.count
    }

    func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (status: Int, body: Data) {
        let parsed = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let call = Call(url: url, body: parsed, headers: headers)
        guard let next = take(call) else { throw Unexpected(description: "no answer left for \(call.operation)") }
        guard next.operation == call.operation else {
            throw Unexpected(description: "asked \(call.operation), the recording has \(next.operation) next")
        }
        return (next.status, Data(next.body.utf8))
    }

    private func take(_ call: Call) -> (operation: String, status: Int, body: String)? {
        lock.lock(); defer { lock.unlock() }
        calls.append(call)
        return answers.isEmpty ? nil : answers.removeFirst()
    }

    func call(_ index: Int) -> Call {
        lock.lock(); defer { lock.unlock() }
        return calls[index]
    }
}

/// A recorded answer with its `content` fields replaced: the recording shows the server returns a payload as it was written.
func recorded(_ json: String, replacing old: String, with new: String) -> String {
    json.replacingOccurrences(of: "\"content\":\"\(old)\"", with: "\"content\":\"\(new)\"")
}
