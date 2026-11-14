import SwiftUI

/// How a status looks. The only styling the ideas screens have, kept apart from their content so the
/// design session can replace it in one place.
enum IdeaStyle {
    static func symbol(_ status: String) -> String {
        switch status {
        case "seen-working": "checkmark.seal.fill"
        case "built-untried": "hammer.fill"
        case "in-progress": "circle.lefthalf.filled"
        case "parked": "pause.circle.fill"
        default: "lightbulb"
        }
    }

    static func tint(_ status: String) -> Color {
        switch status {
        case "seen-working": .green
        case "built-untried": .teal
        case "in-progress": .orange
        case "parked": .gray
        default: .purple
        }
    }
}

struct IdeaStatusBadge: View {
    let status: IdeaStatus

    var body: some View {
        Label(status.label, systemImage: IdeaStyle.symbol(status.id))
            .font(.caption.weight(.semibold))
            .foregroundStyle(IdeaStyle.tint(status.id))
            .labelStyle(.titleAndIcon)
    }
}

/// Every idea and request for the two apps, with its status, searchable (issue 025's "where are the ideas",
/// the owner's request of 14 November 2026). Content from vd-ideas.json; see `IdeaBook`.
struct IdeasView: View {
    let book: IdeaBook
    @State private var query = ""
    @State private var status: String?
    @State private var app: String?

    init(book: IdeaBook, status: String? = nil) {
        self.book = book
        _status = State(initialValue: status)
    }

    private var results: [Idea] { book.matching(query, status: status, app: app) }

    var body: some View {
        List {
            Section {
                filters
            } footer: {
                Text("A status comes from the issues and the reality files by written rules, never a guess. Each idea says what decided its status.")
            }
            ForEach(book.statuses) { s in
                let rows = results.filter { $0.status == s.id }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { idea in
                            NavigationLink(value: idea) { IdeaRow(idea: idea, status: s) }
                        }
                    } header: {
                        Label("\(s.label) (\(rows.count))", systemImage: IdeaStyle.symbol(s.id))
                    } footer: {
                        Text(s.meaning)
                    }
                }
            }
        }
        .readableWidth()
        .overlay {
            if results.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Nothing with this status", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Choose All above to see every idea."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, prompt: "Search ideas, screens, issue numbers")
        .navigationTitle("Ideas")
        .navigationDestination(for: Idea.self) { IdeaDetailView(idea: $0, book: book) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", count: book.ideas.count, selected: status == nil) { status = nil }
                    ForEach(book.statuses) { s in
                        chip(s.label, count: book.counts[s.id] ?? 0, selected: status == s.id) { status = status == s.id ? nil : s.id }
                    }
                }
            }
            Picker("App", selection: $app) {
                Text("Both apps").tag(String?.none)
                Text("VoiceDebrief").tag(String?.some("VoiceDebrief"))
                Text("SGit Vaults").tag(String?.some("SGit Vaults"))
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }

    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title) \(count)")
                .font(.subheadline)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct IdeaRow: View {
    let idea: Idea
    let status: IdeaStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(idea.title).font(.body.weight(.medium))
            HStack(spacing: 8) {
                IdeaStatusBadge(status: status)
                Text(idea.kindLabel).font(.caption).foregroundStyle(.secondary)
                if idea.app != "VoiceDebrief" { Text(idea.app).font(.caption).foregroundStyle(.secondary) }
            }
            if let place = idea.places.first {
                Label(place, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One idea: its status and why, where it is in the app, the versions that named it, and its text.
struct IdeaDetailView: View {
    let idea: Idea
    let book: IdeaBook

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title).font(.title3.weight(.semibold))
                    if let s = book.status(idea.status) {
                        IdeaStatusBadge(status: s)
                        Text(s.meaning).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Why this status") {
                Text(idea.why)
                if let line = idea.statusLine, !line.isEmpty { Text(line).font(.footnote).foregroundStyle(.secondary) }
            }
            if !idea.places.isEmpty {
                Section("Where it is") {
                    ForEach(idea.places, id: \.self) { Label($0, systemImage: "mappin.and.ellipse") }
                }
            }
            if let versions = idea.versions, !versions.isEmpty {
                Section("Versions that named it") {
                    ForEach(versions, id: \.self) { v in
                        Link(destination: AppInfo.notes(for: v)) { Label(v, systemImage: "shippingbox") }
                    }
                }
            }
            if let features = idea.features, !features.isEmpty {
                Section("In the reality file") {
                    ForEach(features, id: \.self) { Text($0) }
                }
            }
            let related = (idea.issues ?? []).compactMap { book.idea(issue: $0) }.filter { $0.id != idea.id }
            if !related.isEmpty {
                Section("Related issues") {
                    ForEach(related) { r in
                        NavigationLink(value: r) { IdeaRow(idea: r, status: book.status(r.status) ?? IdeaStatus(id: r.status, label: r.status, meaning: "")) }
                    }
                }
            }
            if !idea.detail.isEmpty {
                Section("What it says") {
                    ForEach(Array(idea.detail.enumerated()), id: \.offset) { Text($0.element).textSelection(.enabled) }
                }
            }
            Section {
                if let owner = idea.owner { LabeledContent("Owner", value: owner) }
                LabeledContent("From", value: idea.source)
                if let url = URL(string: idea.url) {
                    Link(destination: url) {
                        Label(idea.kind == "issue" ? "Open the issue" : idea.kind == "article" ? "Read the article" : "Open the reality file",
                              systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle(idea.kindLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}
