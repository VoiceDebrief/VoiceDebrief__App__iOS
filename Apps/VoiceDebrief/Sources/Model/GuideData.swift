import Foundation

// The content behind the Guide: every idea with its status, and the release history. Both are generated
// at build time by website/admin/ideas.mjs from the issues, the articles, the reality files and the
// release notes, and bundled as vd-ideas.json and vd-versions.json. Nothing here decides a status: the
// script does, by written rules, and each idea carries the sentence that decided it (`why`).

struct IdeaStatus: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let meaning: String
}

struct Idea: Codable, Hashable, Identifiable, Sendable {
    let id: String
    /// "issue", "article" or "feature" (a row of a reality file).
    let kind: String
    let number: String?
    /// "VoiceDebrief", "SGit Vaults" or "Both".
    let app: String
    let title: String
    let status: String
    let why: String
    let summary: String
    let detail: [String]
    let statusLine: String?
    let owner: String?
    let places: [String]
    let versions: [String]?
    let features: [String]?
    let issues: [String]?
    let url: String
    let source: String

    var kindLabel: String {
        switch kind {
        case "issue": number.map { "Issue \($0)" } ?? "Issue"
        case "article": "Article"
        default: "Feature"
        }
    }

    /// Every word of the query must appear somewhere in the idea.
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = ([id, number ?? "", title, summary, why, app, source, owner ?? ""] + places + detail + (features ?? []))
            .joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

struct IdeaBook: Codable, Sendable {
    let statuses: [IdeaStatus]
    let counts: [String: Int]
    let ideas: [Idea]

    static let resource = "vd-ideas"

    static func bundled(_ bundle: Bundle = .main) -> IdeaBook? {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IdeaBook.self, from: data)
    }

    func status(_ id: String) -> IdeaStatus? { statuses.first { $0.id == id } }

    /// The ideas that match, in the order of the statuses, then issues before articles before features.
    func matching(_ query: String, status: String? = nil, app: String? = nil) -> [Idea] {
        ideas.filter { idea in
            (status == nil || idea.status == status)
                && (app == nil || idea.app == app || idea.app == "Both")
                && idea.matches(query)
        }
    }

    func idea(issue number: String) -> Idea? { ideas.first { $0.id == "issue-\(number)" } }
}

struct VersionEntry: Codable, Hashable, Identifiable, Sendable {
    let version: String
    let date: String
    let notes: [String]
    let url: String
    let hasPage: Bool
    let pictures: Int
    let issues: [String]
    /// Release cards: ASCII boxes at most 72 columns wide (website/admin/cards.mjs).
    var art: [String]? = nil
    var id: String { version }
}

/// Filling a release card's placeholders, as website/admin/cards.mjs does at release: a line that ends in
/// a box edge keeps the edge in its column.
enum ReleaseCard {
    /// The sections a card's WHERE and TRY lines name, by their titles, in the order named: what its
    /// Try buttons open. "Record screen" names Record; a title must stand as a whole word.
    static func sections(in text: String) -> [RootTab] {
        let lines = text.components(separatedBy: "\n").filter {
            let t = $0.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
            return t.hasPrefix("WHERE") || t.hasPrefix("TRY")
        }
        var found: [(Int, RootTab)] = []
        let joined = lines.joined(separator: " ")
        for tab in RootTab.allCases {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: tab.title) + "\\b"
            if let r = joined.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                found.append((joined.distance(from: joined.startIndex, to: r.lowerBound), tab))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The card's title: the first line of capitals inside the box after the heading block.
    static func title(of text: String) -> String? {
        let rows = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "| ")) }
        let bars = rows.indices.filter { rows[$0].hasPrefix("+-") }
        guard bars.count >= 2, bars[1] + 1 < rows.count else { return nil }
        let t = rows[bars[1] + 1]
        return t.isEmpty ? nil : t
    }

    static func fill(_ text: String, _ values: [String: String]) -> String {
        text.components(separatedBy: "\n").map { line in
            var out = line
            for (k, v) in values { out = out.replacingOccurrences(of: "{{\(k)}}", with: v) }
            let trimmedLine = line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            guard out != line, let last = trimmedLine.last, last == "|" || last == "+" else { return out }
            let edge = trimmedLine.count - 1
            let trimmedOut = out.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let body = String(trimmedOut.dropLast()).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            guard body.count < edge else { return out }
            return body + String(repeating: " ", count: edge - body.count) + String(last)
        }.joined(separator: "\n")
    }
}

struct VersionHistory: Codable, Sendable {
    /// Notes of a build that had no number yet when it was made: the running build's, if it is not listed.
    let next: [String]
    let versions: [VersionEntry]
    /// Release cards for the running build, placeholders unfilled.
    var nextArt: [String]? = nil

    static let resource = "vd-versions"

    static func bundled(_ bundle: Bundle = .main) -> VersionHistory? {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VersionHistory.self, from: data)
    }

    /// Every version, newest first, with the running build's own notes at the top when the history in this
    /// build was written before the build had its number.
    func all(current: String) -> [VersionEntry] {
        guard !next.isEmpty, !versions.contains(where: { $0.version == current }) else { return versions }
        let art = (nextArt ?? []).map { ReleaseCard.fill($0, ["version": current, "date": "this build"]) }
        let own = VersionEntry(version: current, date: "", notes: next, url: AppInfo.notes(for: current).absoluteString,
                               hasPage: true, pictures: 0, issues: [], art: art)
        return [own] + versions
    }

    /// The newest release card: the running build's own, or else the latest version that has one.
    func latestCard(current: String) -> (version: String, text: String)? {
        for v in all(current: current) { if let first = v.art?.first { return (v.version, first) } }
        return nil
    }

    /// The versions a person has not looked at: newer than the last one they saw, up to the running one.
    /// Nothing when they have never looked (a first launch is not an update) or nothing is newer.
    func since(_ lastSeen: String?, current: String) -> [VersionEntry] {
        guard let lastSeen, !lastSeen.isEmpty else { return [] }
        return all(current: current).filter {
            Self.compare($0.version, lastSeen) == .orderedDescending && Self.compare($0.version, current) != .orderedDescending
        }
    }

    /// "v0.1.9" before "v0.1.10".
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let parts = { (s: String) in s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

/// The feature guides: a page per feature, each step a picture of one screen with numbered arrows and
/// what each number points at. Written by hand in website/guides/guides.json; the pictures are drawn by
/// website/admin/guides.py and bundled as vd-guide-<guide>-<step>.jpg.
struct FeatureGuide: Codable, Hashable, Identifiable, Sendable {
    struct Callout: Codable, Hashable, Sendable {
        let n: Int
        let text: String
    }
    struct Step: Codable, Hashable, Sendable {
        let screen: String
        let caption: String
        /// A sentence or two before the picture: what you are looking at and why it matters.
        var lead: String? = nil
        /// The picture's resource name, without its .jpg extension.
        let image: String
        let callouts: [Callout]
    }
    let id: String
    let title: String
    let app: String
    /// The section this guide is about (a `RootTab` raw value), for an Open button; none for SGit Vaults.
    var open: String? = nil
    /// Where this guide's pictures came from, when not the book's own line.
    let pictures: String?
    let intro: String
    /// Ideas (ids in vd-ideas.json) this guide is about: where each one stands.
    let ideas: [String]
    let steps: [Step]
}

struct GuideBook: Codable, Sendable {
    let pictures: String
    let guides: [FeatureGuide]

    static let resource = "vd-guides"

    static func bundled(_ bundle: Bundle = .main) -> GuideBook? {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GuideBook.self, from: data)
    }

    static func pictureURL(_ name: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "jpg")
    }
}
