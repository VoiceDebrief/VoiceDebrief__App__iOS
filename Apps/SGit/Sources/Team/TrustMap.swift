import Foundation
import SGitPeople
import SwiftUI

/// Who you know and how well, as a drawing (design: website/sgit-app/secrets/, "The trust map"). Built on
/// the device from your own contacts: nothing is published.
enum TrustLink: String, Equatable, Sendable {
    /// Fingerprints compared face to face, and they have written to you: the strongest.
    case verified
    /// Both sides hold the other's card: they have written to your inbox, which only your card allows.
    case mutual
    /// Only you hold their card so far.
    case oneWay

    var words: String {
        switch self {
        case .verified: return "Checked face to face, both ways"
        case .mutual: return "Both of you have each other's card"
        case .oneWay: return "Only you have their card so far"
        }
    }

    static func of(isMutual: Bool, verified: Bool) -> TrustLink {
        if isMutual && verified { return .verified }
        return isMutual ? .mutual : .oneWay
    }
}

/// One person on the map, as the drawing needs them.
struct TrustPerson: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let link: TrustLink
    let met: String
    let isAgent: Bool
    let canReceive: Bool
}

enum TrustLayout {
    /// Places for `count` people on a circle around the centre, starting at the top, clockwise.
    static func positions(count: Int, in size: CGSize, inset: CGFloat = 56) -> [CGPoint] {
        guard count > 0 else { return [] }
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(40, min(size.width, size.height) / 2 - inset)
        return (0..<count).map { index in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count)
            return CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
        }
    }

    /// What the map says under itself, in a sentence.
    static func summary(_ people: [TrustPerson]) -> String {
        let humans = people.filter { !$0.isAgent }
        let agents = people.count - humans.count
        let both = people.filter { $0.link != .oneWay }.count
        var parts = ["\(humans.count) \(humans.count == 1 ? "person" : "people")"]
        if agents > 0 { parts.append("\(agents) \(agents == 1 ? "agent" : "agents")") }
        let waiting = people.count - both
        return parts.joined(separator: " and ") + ": \(both) linked both ways" + (waiting > 0 ? ", \(waiting) waiting for their side." : ".")
    }
}

extension PeopleHub {
    var trustPeople: [TrustPerson] {
        contacts.map { contact in
            TrustPerson(id: contact.id, name: contact.name,
                        link: .of(isMutual: contact.isMutual, verified: contact.verifiedAt != nil),
                        met: contact.met.words, isAgent: contact.isAgent, canReceive: contact.canReceive)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// The map itself: you in the middle, each person around you, the line between saying how well you know them.
struct TrustMapView: View {
    let shelf: VaultShelf
    let people: PeopleModel
    @State private var chosen: TrustPerson?
    @State private var sharing = false

    var body: some View {
        Group {
            if let hub = people.hub {
                let everyone = hub.trustPeople
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        drawing(hub: hub, everyone: everyone)
                            .frame(height: 380)
                            .frame(maxWidth: .infinity)
                        Text(everyone.isEmpty ? "Nobody yet. Show your card to someone, or scan theirs, in People." : TrustLayout.summary(everyone))
                            .font(.callout)
                        legend
                        if everyone.contains(where: \.canReceive) {
                            Button {
                                sharing = true
                            } label: {
                                Label("Make a shared vault with some of them", systemImage: "person.3.sequence")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Drawn on this device from your own contacts. Nobody else sees it, and nothing here is published.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .sheet(item: $chosen) { person in
                    NavigationStack { TrustPersonView(hub: hub, person: person) }
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $sharing) {
                    NavigationStack { ShareWithPeopleView(shelf: shelf, hub: hub, vault: nil) }
                        .tracked("share-with-people")
                }
            } else {
                ContentUnavailableView("No keys yet", systemImage: "person.2.circle",
                                       description: Text("Make your keys in People first: the map is drawn from the cards you swap."))
            }
        }
        .navigationTitle("Who you trust")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func drawing(hub: PeopleHub, everyone: [TrustPerson]) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let places = TrustLayout.positions(count: everyone.count, in: size)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                Canvas { context, _ in
                    for (index, person) in everyone.enumerated() {
                        var path = Path()
                        path.move(to: centre)
                        path.addLine(to: places[index])
                        let style: StrokeStyle
                        switch person.link {
                        case .verified: style = StrokeStyle(lineWidth: 4, lineCap: .round)
                        case .mutual: style = StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        case .oneWay: style = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6])
                        }
                        context.stroke(path, with: .color(person.link == .oneWay ? .secondary : .accentColor), style: style)
                    }
                }
                node(name: hub.name, photo: nil, agent: false, size: 72, isMe: true)
                    .position(centre)
                ForEach(Array(everyone.enumerated()), id: \.element.id) { index, person in
                    Button { chosen = person } label: {
                        node(name: person.name, photo: hub.book.photo(person.id), agent: person.isAgent, size: 54, isMe: false)
                    }
                    .buttonStyle(.plain)
                    .position(places[index])
                    .accessibilityLabel("\(person.name): \(person.link.words)")
                }
            }
        }
    }

    private func node(name: String, photo: Data?, agent: Bool, size: CGFloat, isMe: Bool) -> some View {
        VStack(spacing: 4) {
            Group {
                if agent {
                    Circle().fill(.quaternary).overlay(Image(systemName: "cpu").font(.title3))
                } else {
                    ContactPhoto(data: photo, name: name)
                }
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(isMe ? Color.accentColor : .clear, lineWidth: 3))
            Text(isMe ? "You" : name).font(.caption2).lineLimit(1).frame(maxWidth: 90)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([TrustLink.verified, .mutual, .oneWay], id: \.self) { link in
                HStack(spacing: 10) {
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        let style = link == .oneWay ? StrokeStyle(lineWidth: 2, dash: [5, 4])
                                                    : StrokeStyle(lineWidth: link == .verified ? 4 : 2.5)
                        context.stroke(path, with: .color(link == .oneWay ? .secondary : .accentColor), style: style)
                    }
                    .frame(width: 36, height: 10)
                    Text(link.words).font(.footnote)
                }
            }
        }
    }
}

/// One person from the map: how you met, how well you know them, what you can do together.
struct TrustPersonView: View {
    let hub: PeopleHub
    let person: TrustPerson

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ContactPhoto(data: hub.book.photo(person.id), name: person.name).frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text(person.name).font(.headline)
                        Text(person.link.words).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("How you know them") {
                LabeledContent("Met", value: person.met)
                LabeledContent("Fingerprint", value: VaultNaming.grouped(String(person.id.suffix(16))))
                if person.isAgent { LabeledContent("Kind", value: "An agent") }
                LabeledContent("Their inbox", value: person.canReceive ? "Known: you can send to them" : "Not known yet")
            }
            if person.link == .oneWay {
                Section {
                    Text("Their side is missing. Send them your card from People: once they write back, the line between you is solid.")
                        .font(.callout)
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
