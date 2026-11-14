import Foundation

/// The vaults published at https://sgit.ai/demos/vaults/, each with the read key its maker published on
/// purpose (`sgit_public_read_`: it can look and never change anything). A copy ships with the app,
/// written by `scripts/sgit-app/demo_vaults.py`; the list is also read live when the gallery opens, so
/// new vaults appear without a new build.
struct DemoVault: Codable, Equatable, Identifiable, Sendable {
    var id: String { vault }
    let number: Int
    let name: String
    let slug: String
    let vault: String
    let summary: String
    let category: String
    let files: Int
    let size: String
    let published: String
    let page: String
    /// Nil for a vault seen in the live list but not in this build's copy: its key is read from its page when opened.
    var readKey: String?
}

struct DemoCatalog: Codable, Equatable, Sendable {
    static let resource = "sg-demo-vaults"
    static let base = URL(string: "https://sgit.ai/demos/vaults/")!
    static let source = URL(string: "https://sgit.ai/demos/vaults/index.html")!

    var format: String
    var source: String
    var fetched: String
    var vaults: [DemoVault]

    static func bundled(_ bundle: Bundle = .main) -> DemoCatalog? {
        guard let url = bundle.url(forResource: resource, withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DemoCatalog.self, from: data)
    }

    /// The rows of the page's Markdown twin, without their keys.
    static func rows(fromIndex text: String) -> [DemoVault] {
        text.split(separator: "\n").compactMap { line -> DemoVault? in
            guard line.hasPrefix("| "), line.dropFirst(2).first?.isNumber == true else { return nil }
            let cells = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 7, let number = Int(cells[0]),
                  let head = cells[1].firstMatch(of: /^\[(.+?)\]\(([^)]+?)\/index\.md\)`([a-z0-9]+)`$/),
                  cells[cells.count - 1].wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return nil }
            let slug = String(head.output.2)
            return DemoVault(number: number, name: String(head.output.1), slug: slug, vault: String(head.output.3),
                             summary: cells[2..<(cells.count - 4)].joined(separator: " | "),
                             category: cells[cells.count - 4], files: Int(cells[cells.count - 3]) ?? 0,
                             size: cells[cells.count - 2], published: cells[cells.count - 1],
                             page: base.appendingPathComponent(slug).appendingPathComponent("index.html").absoluteString, readKey: nil)
        }
    }

    /// The live rows, each with the key from the bundled copy where it has one.
    func merged(withLive live: [DemoVault]) -> [DemoVault] {
        guard !live.isEmpty else { return vaults }
        let keys = Dictionary(vaults.map { ($0.vault, $0.readKey) }, uniquingKeysWith: { first, _ in first })
        return live.map { row in
            var row = row
            row.readKey = keys[row.vault] ?? nil
            return row
        }
    }

    /// A published read key for this vault, from its own page. Only the public prefix is accepted.
    static func readKey(inPage text: String, vault: String) -> String? {
        text.matches(of: /sgit_public_read_[0-9a-f]{64}:[a-z0-9]{4,24}/).map { String($0.output) }.first { $0.hasSuffix(":" + vault) }
    }

    static func fetchLive() async -> [DemoVault] {
        guard let (data, response) = try? await URLSession.shared.data(from: base.appendingPathComponent("index.md")),
              (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { return [] }
        return rows(fromIndex: text)
    }

    static func fetchKey(for vault: DemoVault) async -> String? {
        let url = base.appendingPathComponent(vault.slug).appendingPathComponent("index.md")
        guard let (data, _) = try? await URLSession.shared.data(from: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return readKey(inPage: text, vault: vault.vault)
    }

    /// By category, the biggest first; within one, newest first.
    static func grouped(_ all: [DemoVault], search: String) -> [(category: String, vaults: [DemoVault])] {
        let wanted = search.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = wanted.isEmpty ? all : all.filter {
            $0.name.lowercased().contains(wanted) || $0.summary.lowercased().contains(wanted) || $0.category.lowercased().contains(wanted)
        }
        return Dictionary(grouping: shown, by: \.category)
            .map { ($0.key, $0.value.sorted { $0.number > $1.number }) }
            .sorted { $0.1.count != $1.1.count ? $0.1.count > $1.1.count : $0.0 < $1.0 }
    }
}
