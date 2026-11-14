import Foundation
import Testing
@testable import SGitPeople

/// Ben's own inbox keys, for the tests: the recorded lane's id is redacted, so these are made up and only
/// ever sent to the replaying transport.
let benKeys = InboxKeys(address: People.benInbox, enumKey: String(repeating: "e", count: 64), vaultKey: "not used here")

@Suite("The lane client, against recorded answers")
struct LaneClientTests {
    @Test func writeSendsTheTokenAndPayloadAndNothingElse() async throws {
        let http = ReplayLaneHTTP([("write", 200, RecordedLane.writeOK)])
        try await LaneClient(http: http).write("cGF5bG9hZA==", to: People.benInbox)
        let call = http.call(0)
        #expect(call.url.absoluteString == "https://dev.send.sgraph.ai/api/vault/append/write/beninbox")
        #expect(call.body["append_token"] as? String == People.benInbox.append)
        #expect(call.body["payload"] as? String == "cGF5bG9hZA==")
        #expect(call.headers.isEmpty)
    }

    @Test func aWrongTokenIsNotFound() async throws {
        let http = ReplayLaneHTTP([("write", 404, RecordedLane.notFoundPage)])
        await #expect(throws: LaneError.notFound) { try await LaneClient(http: http).write("x", to: People.benInbox) }
    }

    @Test func listReadsTheRecordedEntries() async throws {
        let http = ReplayLaneHTTP([("list", 200, RecordedLane.listEmpty), ("list", 200, RecordedLane.listTwo),
                                   ("list", 200, RecordedLane.listTwoWithContent)])
        let client = LaneClient(http: http)
        #expect(try await client.list(benKeys).entries.isEmpty)
        let two = try await client.list(benKeys)
        #expect(two.entries.map(\.fileId) == [RecordedLane.fileOne, RecordedLane.fileTwo])
        #expect(two.entries.first?.inbox == RecordedLane.lane)
        #expect(two.entries.first?.received == 1_794_649_267_280)
        #expect(two.entries.first?.content == nil)
        #expect(!two.truncated)
        let withContent = try await client.list(benKeys, includeContent: true)
        #expect(withContent.entries.map(\.content) == ["aGVsbG8gb25l", "aGVsbG8gdHdv"])
        #expect(withContent.entries.first?.size == 9)
        let call = http.call(1)
        #expect(call.headers == ["x-sgraph-vault-enum-key": benKeys.enumKey])
        #expect(call.body["include_content"] as? Bool == false)
    }

    @Test func fetchAndMarkProcessedReadTheRecordedAnswers() async throws {
        let http = ReplayLaneHTTP([("fetch", 200, RecordedLane.fetchOne), ("mark-processed", 200, RecordedLane.markOne)])
        let client = LaneClient(http: http)
        let fetched = try await client.fetch(benKeys, inbox: RecordedLane.lane, fileIds: [RecordedLane.fileOne])
        #expect(fetched.files == [LaneFile(fileId: RecordedLane.fileOne, size: 9, content: "aGVsbG8gb25l")])
        #expect(fetched.missing.isEmpty)
        let marked = try await client.markProcessed(benKeys, inbox: RecordedLane.lane, fileIds: [RecordedLane.fileOne])
        #expect(marked.moved == [RecordedLane.fileOne])
        #expect(http.call(0).body["file_ids"] as? [String] == [RecordedLane.fileOne])
        #expect(http.call(1).body["inbox"] as? String == RecordedLane.lane)
    }

    @Test func configureSendsHashesNotTheKeys() async throws {
        let http = ReplayLaneHTTP([("configure", 200, RecordedLane.configured)])
        try await LaneClient(http: http).configure(People.benInbox, writeKeyHex: "aa", accessToken: "token-for-the-test",
                                                   enumKey: benKeys.enumKey)
        let call = http.call(0)
        #expect(call.headers == ["x-sgraph-vault-write-key": "aa", "x-sgraph-access-token": "token-for-the-test"])
        #expect(call.body["append_anchors"] as? [String] == [LaneClient.sha256Hex(People.benInbox.append)])
        #expect(call.body["enum_key_hash"] as? String == LaneClient.sha256Hex(benKeys.enumKey))
        #expect(!String(describing: call.body).contains(benKeys.enumKey))
    }

    @Test func randomTokensAreHexOfTheirLength() {
        #expect(LaneClient.randomHex(24).count == 48)
        let hex = LaneClient.randomHex(32)
        #expect(hex.allSatisfy { $0.isHexDigit })
        #expect(LaneClient.randomHex(24) != LaneClient.randomHex(24))
    }
}

@Suite("Checking the inbox")
struct InboxCheckTests {
    func payload(_ words: String, from: PKIIdentity = People.ana) throws -> String {
        try PeopleMessage(kind: .text, from: from.bundle.signingFingerprint, to: People.ben.bundle.signingFingerprint, sentAt: People.now,
                          text: words).lanePayload(to: People.ben.bundle, from: from)
    }

    @Test func nothingWaitingIsOneCall() async throws {
        let http = ReplayLaneHTTP([("list", 200, RecordedLane.listEmpty)])
        let store = MessageStore(file: nil)
        let new = try await InboxCheck(client: LaneClient(http: http)).run(keys: benKeys, me: People.ben, contacts: [], store: store)
        #expect(new.isEmpty)
        #expect(http.calls.count == 1)
    }

    @Test func messagesAreKeptBeforeTheLaneForgetsThem() async throws {
        let one = try payload("first"), two = try payload("second")
        // The recorded fetch, with both recorded files, and our own sealed payloads as their content.
        let fetchBoth = #"{"status":"ok","files":[{"file_id":"\#(RecordedLane.fileOne)","size":9,"content":"\#(one)"},{"file_id":"\#(RecordedLane.fileTwo)","size":9,"content":"\#(two)"}],"missing":[]}"#
        let http = ReplayLaneHTTP([("list", 200, RecordedLane.listTwo), ("fetch", 200, fetchBoth), ("mark-processed", 200, RecordedLane.markOne)])
        let file = People.temporaryFolder().appendingPathComponent("messages.json")
        let store = MessageStore(file: file)
        let new = try await InboxCheck(client: LaneClient(http: http)).run(keys: benKeys, me: People.ben, contacts: [People.ana.bundle], store: store)
        #expect(new.count == 2)
        #expect(new.map { $0.message?.text } == ["second", "first"])
        #expect(new.allSatisfy { $0.trust == .contact })
        #expect(http.call(2).body["file_ids"] as? [String] == [RecordedLane.fileOne, RecordedLane.fileTwo])
        let reopened = MessageStore(file: file)
        #expect(reopened.all.count == 2)
        #expect(reopened.unread == 2)
        reopened.markRead(RecordedLane.fileOne)
        #expect(MessageStore(file: file).unread == 1)
    }

    @Test func aMessageAlreadyKeptIsNotFetchedAgainButIsMarked() async throws {
        let store = MessageStore(file: nil)
        try store.add([ReceivedMessage(id: RecordedLane.fileOne, receivedAt: People.now)])
        let fetchTwo = recorded(#"{"status":"ok","files":[{"file_id":"\#(RecordedLane.fileTwo)","size":9,"content":"aGVsbG8gdHdv"}],"missing":[]}"#,
                                replacing: "aGVsbG8gdHdv", with: try payload("two"))
        let http = ReplayLaneHTTP([("list", 200, RecordedLane.listTwo), ("fetch", 200, fetchTwo), ("mark-processed", 200, RecordedLane.markOne)])
        let new = try await InboxCheck(client: LaneClient(http: http)).run(keys: benKeys, me: People.ben, contacts: [], store: store)
        #expect(new.map(\.id) == [RecordedLane.fileTwo])
        #expect(http.call(1).body["file_ids"] as? [String] == [RecordedLane.fileTwo])
        #expect(http.call(2).body["file_ids"] as? [String] == [RecordedLane.fileOne, RecordedLane.fileTwo])
    }

    @Test func whatDoesNotOpenIsKeptRaw() async throws {
        // The recorded "hello one" is not a sealed message: it is kept, with its content, and not lost.
        let http = ReplayLaneHTTP([("list", 200, RecordedLane.listAfterMark),
                                   ("fetch", 200, RecordedLane.fetchOne.replacingOccurrences(of: RecordedLane.fileOne, with: RecordedLane.fileTwo)),
                                   ("mark-processed", 200, RecordedLane.markOne)])
        let store = MessageStore(file: nil)
        let new = try await InboxCheck(client: LaneClient(http: http)).run(keys: benKeys, me: People.ben, contacts: [], store: store)
        #expect(new.count == 1)
        #expect(new.first?.message == nil)
        #expect(new.first?.raw == "aGVsbG8gb25l")
        #expect(new.first?.problem != nil)
        #expect(store.all.count == 1)
    }

    @Test func aServerThatCannotBeAskedThrowsAndKeepsNothing() async throws {
        let http = ReplayLaneHTTP([("list", 404, RecordedLane.notFoundPage)])
        let store = MessageStore(file: nil)
        await #expect(throws: LaneError.notFound) {
            try await InboxCheck(client: LaneClient(http: http)).run(keys: benKeys, me: People.ben, contacts: [], store: store)
        }
        #expect(store.all.isEmpty)
    }
}

@Suite("When to check")
struct InboxScheduleTests {
    let t0 = People.now

    @Test func openingChecksAtOnceThenEveryMinute() {
        var s = InboxSchedule()
        #expect(s.nextCheck(at: t0) == nil)
        s.note(.opened, at: t0)
        #expect(s.shouldCheck(at: t0))
        s.note(.checked(newMessages: 0), at: t0)
        #expect(!s.shouldCheck(at: t0.addingTimeInterval(59)))
        #expect(s.shouldCheck(at: t0.addingTimeInterval(60)))
    }

    @Test func idleChecksSlowDownToFifteenMinutes() {
        var s = InboxSchedule()
        s.note(.opened, at: t0)
        var now = t0.addingTimeInterval(InboxSchedule.idleAfter)
        var gaps: [TimeInterval] = []
        for _ in 0..<8 {
            s.note(.checked(newMessages: 0), at: now)
            let gap = s.interval(at: now)
            gaps.append(gap)
            now = now.addingTimeInterval(gap)
        }
        #expect(gaps == [120, 240, 480, 900, 900, 900, 900, 900])
    }

    @Test func activityOrANewMessageBringsItBackToEveryMinute() {
        var s = InboxSchedule()
        s.note(.opened, at: t0)
        let idle = t0.addingTimeInterval(InboxSchedule.idleAfter + 1)
        s.note(.checked(newMessages: 0), at: idle)
        s.note(.checked(newMessages: 0), at: idle.addingTimeInterval(120))
        #expect(s.interval(at: idle.addingTimeInterval(120)) == 240)
        s.note(.activity, at: idle.addingTimeInterval(130))
        #expect(s.interval(at: idle.addingTimeInterval(130)) == 60)
        let later = idle.addingTimeInterval(130 + InboxSchedule.idleAfter)
        s.note(.checked(newMessages: 0), at: later)
        s.note(.checked(newMessages: 2), at: later.addingTimeInterval(120))
        #expect(s.interval(at: later.addingTimeInterval(120)) == 60)
    }

    @Test func neverInTheBackgroundAndAtOnceOnComingBack() {
        var s = InboxSchedule()
        s.note(.opened, at: t0)
        s.note(.checked(newMessages: 0), at: t0)
        s.note(.background, at: t0.addingTimeInterval(10))
        #expect(s.nextCheck(at: t0.addingTimeInterval(3600)) == nil)
        s.note(.foreground, at: t0.addingTimeInterval(3600))
        #expect(s.shouldCheck(at: t0.addingTimeInterval(3600)))
    }
}
