import Foundation

/// The small part of markdown a debrief uses, as blocks a view can draw as real text.
enum DebriefBlock: Equatable, Sendable {
    case heading(String)
    case bullet(String)
    case paragraph(String)
}

enum DebriefMarkdown {
    static func blocks(_ markdown: String) -> [DebriefBlock] {
        var out: [DebriefBlock] = []
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { out.append(.heading(text)) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                out.append(.bullet(clean(String(line.dropFirst(2)))))
            } else {
                out.append(.paragraph(clean(line)))
            }
        }
        return out
    }

    /// Bold markers are dropped: the debrief is drawn as plain text.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }
}
