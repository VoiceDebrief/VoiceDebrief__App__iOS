import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Credit")
struct CreditTests {
    static let start = Date(timeIntervalSince1970: 1_794_000_000)

    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "credit-\(UUID().uuidString).json")
    }

    // MARK: Money and prices

    @Test func moneyIsWrittenInPoundsAndPence() {
        #expect(Credit.money(5_000_000) == "£5.00")
        #expect(Credit.money(4_962_000) == "£4.962")
        #expect(Credit.money(4_960_000) == "£4.96")
        #expect(Credit.money(-250_000) == "-£0.25")
        #expect(Credit.money(0) == "£0.00")
        #expect(Credit.money(-400) == "£0.00")
        #expect(Credit.money(12_345_678) == "£12.346")
        #expect(Credit.price(30_000) == "3p")
        #expect(Credit.price(5_000) == "0.5p")
        #expect(Credit.price(0) == "free")
        #expect(Credit.price(1_200_000) == "£1.20")
    }

    @Test func aTranscriptIsChargedByTheStartedMinute() {
        #expect(PriceList.cost(.transcript, quantity: 60) == 30_000)
        #expect(PriceList.cost(.transcript, quantity: 76) == 60_000)
        #expect(PriceList.cost(.transcript, quantity: 0.2) == 30_000)
        #expect(PriceList.cost(.transcript, quantity: 404) == 210_000)
        #expect(PriceList.cost(.transcript, quantity: 0) == 0)
        #expect(PriceList.cost(.transcript, quantity: -3) == 0)
        #expect(PriceList.cost(.transcript, quantity: .nan) == 0)
    }

    @Test func theOtherPricesAreByTheThing() {
        #expect(PriceList.cost(.debrief, quantity: 1) == 50_000)
        #expect(PriceList.cost(.cleanPassage, quantity: 1) == 10_000)
        #expect(PriceList.cost(.createVault, quantity: 1) == 100_000)
        #expect(PriceList.cost(.saveToVault, quantity: 4) == 40_000)
        #expect(PriceList.cost(.send, quantity: 1) == 10_000)
        #expect(PriceList.words(.saveToVault, quantity: 4) == "Saved to a vault, 4 files")
        #expect(PriceList.words(.transcript, quantity: 76) == "Transcript, 1 min 16 s of audio")
    }

    @Test func everythingHasAPriceInWholePenceAndTheListSaysItIsAPlaceholder() {
        #expect(PriceList.all.map(\.action) == CreditAction.allCases)
        #expect(PriceList.arePlaceholders)
        // The owner's word: just about everything costs a little, in steps of one penny for now.
        for price in PriceList.all {
            #expect(price.micro > 0, "\(price.title) is free")
            #expect(price.micro % Credit.perPenny == 0, "\(price.title) is not a whole number of pence")
        }
        #expect(PriceList.price(of: .transcript)?.words == "3p a minute of audio")
        #expect(PriceList.price(of: .createVault)?.words == "10p each")
        #expect(PriceList.price(of: .saveToVault)?.words == "1p a file")
        #expect(PriceList.title(ofFeature: "debrief") == "A debrief")
        #expect(PriceList.title(ofFeature: "something-from-a-later-build") == "something-from-a-later-build")
    }

    /// Charges a book as the ledger does: the price list says the cost and the words.
    @discardableResult
    private static func charge(_ book: inout CreditBook, _ action: CreditAction, _ quantity: Double = 1,
                               noteId: String? = "n1", at: Date = Date()) -> CreditEntry? {
        book.charge(feature: action.rawValue, text: PriceList.words(action, quantity: quantity),
                    cost: PriceList.cost(action, quantity: quantity), quantity: quantity, noteId: noteId, at: at)
    }

    // MARK: The ledger's arithmetic

    @Test func aNewLedgerStartsWithFivePounds() {
        let book = CreditBook(device: "d1", at: Self.start)
        #expect(book.balance == 5_000_000)
        #expect(book.entries.count == 1)
        #expect(book.entries[0].kind == .start)
        #expect(book.entries[0].balance == 5_000_000)
        #expect(book.spent == 0)
        #expect(book.addsUp)
    }

    @Test func chargesCountDownAndEachEntryKeepsTheBalanceAfterIt() throws {
        var book = CreditBook(device: "d1", at: Self.start)
        let made1 = Self.charge(&book, .transcript, 76, noteId: "n1", at: Self.start + 10)
        let transcript = try #require(made1)
        let made2 = Self.charge(&book, .debrief, 1, noteId: "n1", at: Self.start + 20)
        let debrief = try #require(made2)
        #expect(transcript.amount == -60_000)
        #expect(transcript.balance == 4_940_000)
        #expect(transcript.text == "Transcript, 1 min 16 s of audio")
        #expect(transcript.noteId == "n1")
        #expect(transcript.quantity == 76)
        #expect(transcript.action == "transcript")
        #expect(debrief.balance == 4_890_000)
        #expect(book.balance == 4_890_000)
        #expect(book.spent == 110_000)
        #expect(book.entries.map(\.kind) == [.start, .charge, .charge])
        #expect(book.addsUp)
        // Something that costs nothing writes nothing.
        let made9 = book.charge(feature: "gift", text: "Something free", cost: 0)
        #expect(made9 == nil)
        let made10 = Self.charge(&book, .transcript, 0, noteId: "n1")
        #expect(made10 == nil)
        #expect(book.entries.count == 3)
    }

    @Test func theBalanceGoesBelowZeroAndNothingIsRefused() throws {
        var book = CreditBook(device: "d1", startingCredit: 40_000, at: Self.start)
        let made3 = Self.charge(&book, .debrief, 1, noteId: "n1")
        let first = try #require(made3)
        #expect(first.balance == -10_000)
        let made4 = Self.charge(&book, .transcript, 3_600, noteId: "n2")
        let second = try #require(made4)
        #expect(second.balance == -1_810_000)
        #expect(book.balance == -1_810_000)
        #expect(book.addsUp)
        #expect(Credit.money(book.balance) == "-£1.81")
    }

    @Test func aTopUpIsAddedOncePerReference() throws {
        var book = CreditBook(device: "d1", startingCredit: 0, at: Self.start)
        Self.charge(&book, .debrief, 1, noteId: "n1")
        let made5 = book.topUp(5_000_000, ref: "simulated-1", source: "simulated")
        let topUp = try #require(made5)
        #expect(topUp.kind == .topUp)
        #expect(topUp.balance == 4_950_000)
        #expect(topUp.text.contains("simulated"))
        #expect(topUp.text.contains("no money"))
        let made11 = book.topUp(5_000_000, ref: "simulated-1", source: "simulated")
        #expect(made11 == nil)
        let made12 = book.topUp(0, ref: "simulated-2", source: "simulated")
        #expect(made12 == nil)
        let made13 = book.topUp(5_000_000, ref: "", source: "simulated")
        #expect(made13 == nil)
        #expect(book.balance == 4_950_000)
        #expect(book.toppedUp == 5_000_000)
        // A top-up is not spending, and does not hide what was spent.
        #expect(book.spent == 50_000)
        let made6 = book.topUp(5_000_000, ref: "appstore-2000000123", source: "appstore:sandbox")
        let real = try #require(made6)
        #expect(real.text == "Top-up")
        #expect(book.addsUp)
    }

    @Test func aDeclinedChargeIsGivenBackOnceAndStaysInTheLedger() throws {
        var book = CreditBook(device: "d1", at: Self.start)
        let made7 = Self.charge(&book, .debrief, 1, noteId: "n1")
        let charge = try #require(made7)
        let made8 = book.decline(charge.id, reason: "The result was not usable")
        let refund = try #require(made8)
        #expect(refund.kind == .refund)
        #expect(refund.amount == 50_000)
        #expect(refund.ref == charge.id)
        #expect(refund.reason == "The result was not usable")
        #expect(book.balance == 5_000_000)
        #expect(book.spent == 0)
        #expect(book.isDeclined(charge))
        #expect(book.entries.count == 3)
        let made14 = book.decline(charge.id, reason: "again")
        #expect(made14 == nil)
        let made15 = book.decline(refund.id, reason: "a refund is not a charge")
        #expect(made15 == nil)
        let made16 = book.decline(book.entries[0].id, reason: "nor is the starting credit")
        #expect(made16 == nil)
        let made17 = book.decline("no such entry", reason: "x")
        #expect(made17 == nil)
        #expect(book.addsUp)
    }

    @Test func theTakingsAreAddedUpByFeature() throws {
        var book = CreditBook(device: "d1", at: Self.start)
        Self.charge(&book, .transcript, 76, at: Self.start + 10)
        Self.charge(&book, .transcript, 30, noteId: "n2", at: Self.start + 100)
        let made = Self.charge(&book, .debrief, at: Self.start + 110)
        let debrief = try #require(made)
        Self.charge(&book, .debrief, noteId: "n2", at: Self.start + 120)
        Self.charge(&book, .createVault, noteId: nil, at: Self.start + 200)
        book.decline(debrief.id, reason: "The result was not usable", at: Self.start + 300)
        book.topUp(5_000_000, ref: "simulated-1", source: "simulated", at: Self.start + 400)

        let lines = book.byFeature()
        #expect(lines.map(\.feature) == ["createVault", "transcript", "debrief"])
        #expect(lines[0] == FeatureLine(feature: "createVault", uses: 1, charged: 100_000, declined: 0, givenBack: 0))
        #expect(lines[1] == FeatureLine(feature: "transcript", uses: 2, charged: 90_000, declined: 0, givenBack: 0))
        #expect(lines[2] == FeatureLine(feature: "debrief", uses: 2, charged: 100_000, declined: 1, givenBack: 50_000))
        #expect(lines[2].net == 50_000)
        // The takings are what was spent: a top-up and the starting credit are not in them.
        #expect(lines.reduce(0) { $0 + $1.net } == book.spent)
        // A period leaves out what is older; a refund counts in the period it was given.
        let later = book.byFeature(since: Self.start + 150)
        #expect(later.map(\.feature) == ["createVault", "debrief"])
        #expect(later[1] == FeatureLine(feature: "debrief", uses: 0, charged: 0, declined: 1, givenBack: 50_000))
        #expect(book.byFeature(since: Self.start + 1_000).isEmpty)
    }

    // MARK: The file

    @Test @MainActor func aLedgerReopensAsItWasLeft() throws {
        let file = Self.temporaryFile()
        let ledger = CreditLedger(file: file, now: Self.start)
        #expect(ledger.balance == Credit.startingCredit)
        ledger.charge(.transcript, quantity: 76, noteId: "n1")
        ledger.charge(.debrief, noteId: "n1")
        ledger.charge(.cleanPassage, noteId: "n1")
        #expect(ledger.topUp(PaymentReceipt(ref: "simulated-a", credit: 5_000_000, source: "simulated")))
        #expect(!ledger.topUp(PaymentReceipt(ref: "simulated-a", credit: 5_000_000, source: "simulated")))
        let charge = try #require(ledger.newestFirst.first { $0.action == "cleanPassage" })
        ledger.decline(charge, reason: "It was a test")
        #expect(ledger.balance == 5_000_000 - 60_000 - 50_000 + 5_000_000)
        #expect(ledger.newestFirst.first?.kind == .refund)

        let again = CreditLedger(file: file)
        #expect(again.book.device == ledger.book.device)
        #expect(again.book.entries.map(\.id) == ledger.book.entries.map(\.id))
        #expect(again.book.entries.map(\.amount) == ledger.book.entries.map(\.amount))
        #expect(again.balance == ledger.balance)
        #expect(again.book.addsUp)
        #expect(again.problem == nil)
        // Reopening does not start again with new credit.
        #expect(again.book.entries.filter { $0.kind == .start }.count == 1)
    }

    /// The first form of the file, as the first build with credit writes it, with only the fields an entry must
    /// have. A later build must still open it.
    static let firstForm = """
    {
      "device" : "5B0C5F0E-7C0B-4E0B-9D53-0D3E5B5F4A11",
      "entries" : [
        { "amount" : 5000000, "at" : "2026-11-13T18:00:00Z", "balance" : 5000000,
          "id" : "A1", "kind" : "start", "text" : "Starting credit" },
        { "action" : "transcript", "amount" : -38000, "at" : "2026-11-13T18:05:00Z", "balance" : 4962000,
          "id" : "A2", "kind" : "charge", "noteId" : "n1", "quantity" : 76, "text" : "Transcript, 1 min 16 s of audio" },
        { "amount" : 5000000, "at" : "2026-11-13T18:06:00Z", "balance" : 9962000,
          "id" : "A3", "kind" : "topup", "ref" : "simulated-1", "source" : "simulated",
          "text" : "Top-up (simulated, no money taken)" }
      ],
      "v" : 1
    }
    """

    @Test @MainActor func readingANoteIsChargedOnceInASession() {
        let file = Self.temporaryFile()
        let ledger = CreditLedger(file: file, now: Self.start)
        ledger.chargeOnce(.readNote, noteId: "n1")
        ledger.chargeOnce(.readNote, noteId: "n1")
        ledger.chargeOnce(.readNote, noteId: "n2")
        #expect(ledger.balance == Credit.startingCredit - 20_000)
        #expect(ledger.book.byFeature().first?.uses == 2)
        // The app opened again is a new session: the same note read again is charged.
        let again = CreditLedger(file: file)
        again.chargeOnce(.readNote, noteId: "n1")
        #expect(again.balance == Credit.startingCredit - 30_000)
    }

    @Test @MainActor func aLedgerInItsFirstFormStillOpens() throws {
        let file = Self.temporaryFile()
        try Data(Self.firstForm.utf8).write(to: file)
        let ledger = CreditLedger(file: file)
        #expect(ledger.problem == nil)
        #expect(ledger.book.v == 1)
        #expect(ledger.book.entries.count == 3)
        #expect(ledger.balance == 9_962_000)
        #expect(ledger.book.addsUp)
        #expect(ledger.book.entries[1].action == "transcript")
        ledger.charge(.debrief, noteId: "n2")
        #expect(CreditLedger(file: file).balance == 9_912_000)
        // The reference of the earlier top-up is still known.
        #expect(!ledger.topUp(PaymentReceipt(ref: "simulated-1", credit: 5_000_000, source: "simulated")))
    }

    @Test @MainActor func aLedgerThatCannotBeReadIsKeptAndNotOverwritten() throws {
        let file = Self.temporaryFile()
        try Data("not a ledger".utf8).write(to: file)
        let ledger = CreditLedger(file: file, now: Self.start)
        #expect(ledger.problem != nil)
        #expect(ledger.balance == Credit.startingCredit)
        let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Self.start.timeIntervalSince1970)).json")
        #expect(try String(contentsOf: aside, encoding: .utf8) == "not a ledger")
    }

    // MARK: Paying

    @Test @MainActor func theSimulatedPaymentSaysItIsSimulatedAndRecordsATopUp() async throws {
        let ledger = CreditLedger(file: Self.temporaryFile(), now: Self.start)
        let provider = SimulatedPayments()
        #expect(provider.isSimulated)
        let packs = await provider.packs()
        let pack = try #require(packs.first)
        #expect(pack.credit == 5_000_000)
        let outcome = try await provider.buy(pack) { ledger.topUp($0) }
        guard case .paid(let receipt) = outcome else {
            Issue.record("a simulated payment always goes through")
            return
        }
        #expect(receipt.source == "simulated")
        #expect(ledger.balance == 10_000_000)
        #expect(ledger.newestFirst.first?.source == "simulated")
        #expect(ledger.newestFirst.first?.text == "Top-up (simulated, no money taken)")
    }

    @Test @MainActor func noScreenIsOfferedTheAppStoreBeforeThereAreProducts() {
        // The App Store provider is written and has never run. Until the products exist the switch
        // is off and the provider in use takes no money. Turn this test round when it is switched on.
        #expect(!Payments.appStoreIsOn)
        #expect(Payments.provider.isSimulated)
        #expect(Roadmap.stages(.testing).map(\.id).contains("credit"))
        #expect(!Roadmap.stages(.built).map(\.id).contains("credit"))
    }
}
