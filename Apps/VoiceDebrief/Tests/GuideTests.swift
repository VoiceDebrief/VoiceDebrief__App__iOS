import Foundation
import Testing
@testable import VoiceDebrief

@Suite("The Guide: ideas and what is new")
struct GuideTests {
    @Test func theBundledIdeasDecodeAndEveryStatusIsKnown() throws {
        let book = try #require(IdeaBook.bundled())
        #expect(book.statuses.map(\.id) == ["seen-working", "built-untried", "in-progress", "proposed", "parked"])
        #expect(!book.ideas.isEmpty)
        let known = Set(book.statuses.map(\.id))
        for idea in book.ideas {
            #expect(known.contains(idea.status), "\(idea.id) has status \(idea.status)")
            #expect(!idea.why.isEmpty, "\(idea.id) does not say what decided its status")
        }
        #expect(book.counts.values.reduce(0, +) == book.ideas.count)
    }

    @Test func searchNeedsEveryWordAndFindsAnIssueByNumber() throws {
        let book = try #require(IdeaBook.bundled())
        #expect(book.matching("025").contains { $0.id == "issue-025" })
        #expect(book.matching("briefing version").contains { $0.id == "issue-025" })
        #expect(book.matching("zzqx-no-such-word").isEmpty)
        let parked = book.matching("", status: "parked")
        #expect(parked.allSatisfy { $0.status == "parked" })
        #expect(book.matching("", app: "SGit Vaults").allSatisfy { $0.app != "VoiceDebrief" })
    }

    @Test func theBundledHistoryDecodesNewestFirst() throws {
        let history = try #require(VersionHistory.bundled())
        let versions = history.versions.map(\.version)
        #expect(!versions.isEmpty)
        #expect(versions == versions.sorted { VersionHistory.compare($0, $1) == .orderedDescending })
    }

    static let history = VersionHistory(next: ["The newest change."], versions: [
        VersionEntry(version: "v0.1.12", date: "2", notes: ["Twelve."], url: "https://example.invalid/12", hasPage: true, pictures: 0, issues: []),
        VersionEntry(version: "v0.1.10", date: "1", notes: ["Ten."], url: "https://example.invalid/10", hasPage: true, pictures: 0, issues: []),
        VersionEntry(version: "v0.1.9", date: "0", notes: ["Nine."], url: "https://example.invalid/9", hasPage: false, pictures: 0, issues: []),
    ])

    @Test func versionsCompareByNumberNotByText() {
        #expect(VersionHistory.compare("v0.1.9", "v0.1.10") == .orderedAscending)
        #expect(VersionHistory.compare("v0.1.10", "v0.1.10") == .orderedSame)
        #expect(VersionHistory.compare("v1.0.0", "v0.9.99") == .orderedDescending)
    }

    @Test func sinceYouLastLookedCoversEverySkippedVersion() {
        // a build made before it had its number carries its own notes as next
        let all = Self.history.all(current: "v0.1.13")
        #expect(all.map(\.version) == ["v0.1.13", "v0.1.12", "v0.1.10", "v0.1.9"])
        #expect(Self.history.since("v0.1.9", current: "v0.1.13").map(\.version) == ["v0.1.13", "v0.1.12", "v0.1.10"])
        #expect(Self.history.since("v0.1.13", current: "v0.1.13").isEmpty)
        // a first launch is not an update
        #expect(Self.history.since(nil, current: "v0.1.13").isEmpty)
        #expect(Self.history.since("", current: "v0.1.13").isEmpty)
        // a listed version does not get the next notes twice
        #expect(Self.history.all(current: "v0.1.12").map(\.version) == ["v0.1.12", "v0.1.10", "v0.1.9"])
    }

    @Test func theFirstLaunchIsRememberedAndNeverOverwritten() throws {
        let defaults = try #require(UserDefaults(suiteName: "GuideTests-\(UUID().uuidString)"))
        WhatsNewMemory.seedIfNeeded(current: "v0.1.10", defaults: defaults)
        WhatsNewMemory.seedIfNeeded(current: "v0.1.12", defaults: defaults)
        #expect(defaults.string(forKey: WhatsNewMemory.key) == "v0.1.10")
        #expect(WhatsNewMemory.unseen(in: Self.history, current: "v0.1.12", defaults: defaults).map(\.version) == ["v0.1.12"])
    }

    @Test func everyGuideHasItsPicturesAndNumbersInOrder() throws {
        let book = try #require(GuideBook.bundled())
        let ideas = try #require(IdeaBook.bundled())
        #expect(!book.guides.isEmpty)
        for g in book.guides {
            for id in g.ideas { #expect(ideas.ideas.contains { $0.id == id }, "\(g.id) names \(id)") }
            for step in g.steps {
                #expect(GuideBook.pictureURL(step.image) != nil, "\(step.image).jpg is not in the app")
                #expect(step.callouts.map(\.n) == Array(1...step.callouts.count), "\(g.id): numbers out of order")
            }
        }
    }

    @Test func theBundledArticlesDecodeAndParse() throws {
        let book = try #require(ArticleBook.bundled())
        #expect(!book.articles.isEmpty)
        for a in book.articles { #expect(!ArticleBlock.parse(a.markdown).isEmpty, "\(a.id) has no blocks") }
    }

    @Test func markdownIsCutIntoBlocks() {
        let blocks = ArticleBlock.parse("## A heading\n\nOne line\nand the next.\n\n- a point\n1. first\n> quoted\n\n| A | B |\n|---|---|\n| x | y |\n\n```\ncode\n```")
        #expect(blocks == [.heading(level: 2, text: "A heading"), .paragraph("One line and the next."), .bullet("a point"),
                           .bullet("1. first"), .quote("quoted"), .bullet("A · B"), .bullet("x · y"), .code("code")])
    }
}
