import SwiftUI
import UIKit

/// Owner mode (R6 of the 23 November 2026 brief): every agent and what it is doing, the latest sites,
/// videos, briefs and decision slides, the decisions waiting for the owner, and a way to talk to any page.
/// Read from one committed JSON feed (`OwnerFeed`), never from HTML. The owner's decisions and his actions
/// are listed apart. Demo shows an invented twin, and nothing done in demo mode leaves the device.
struct OwnerView: View {
    let book: VaultBook
    private var desk: OwnerDesk { OwnerDesk.shared }
    @Environment(\.openURL) private var openURL

    /// What is being talked to: an item (a page) and its agent, or an agent alone.
    struct Talk: Identifiable {
        var item: OwnerFeed.Item?
        var agent: String
        var id: String { (item?.id ?? "") + "/" + agent }
    }
    @State private var talking: Talk?
    @State private var pastedGrant = ""

    var body: some View {
        List {
            deviceSection
            Section {
                Picker("Feed", selection: Bindable(desk).source) {
                    ForEach(OwnerDesk.Source.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if let feed = desk.feed {
                    Text("Made \(feed.made.formatted(date: .abbreviated, time: .shortened)) by \(feed.by)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if desk.isDemo || desk.feed?.twin == true {
                    Label("Invented data. Answers and messages here are kept on this device and never sent.", systemImage: "theatermasks")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Owner mode reads one JSON feed (owner.feed/v1). Live reads \(OwnerDesk.livePath) from the agents vault chosen on the Agents screen.")
            }

            if let feed = desk.feed {
                decisionsSection(feed)
                agentsSection(feed)
                itemsSection("Latest websites", systemImage: "globe", items: feed.sites, feed: feed)
                itemsSection("Videos", systemImage: "play.rectangle", items: feed.videos, feed: feed)
                itemsSection("Briefs", systemImage: "doc.text", items: feed.briefs, feed: feed)
                itemsSection("Decision slides", systemImage: "rectangle.on.rectangle", items: feed.slides, feed: feed)
            }

            Section("Your decisions") {
                if desk.decisions.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(desk.decisions.reversed()) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.title).font(.callout.weight(.semibold))
                        Text("You chose: \(record.choice)").font(.callout)
                        Text("Asked by \(record.from). \(record.delivery). \(record.at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Your actions") {
                if desk.actions.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(desk.actions.reversed()) { action in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.subject).font(.callout.weight(.semibold))
                        if let text = action.text { Text(text).font(.callout) }
                        Text("\(action.kind == "talk-to-page" ? "Talked to the page" : "Message"). \(action.delivery). \(action.at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let problem = desk.problem {
                Section { Text(problem).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Owner")
        .refreshable { await desk.refresh(book: book) }
        .task(id: desk.source) {
            desk.checkGrant(deviceFingerprint: IdentityBook.shared.device?.fingerprint)
            await desk.refresh(book: book)
        }
        .toolbar {
            ToolbarItem { Button { Task { await desk.refresh(book: book) } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        }
        .sheet(item: $talking) { talk in
            OwnerTalkSheet(talk: talk, feed: desk.feed, demo: desk.isDemo || desk.feed?.twin == true) { text in
                await desk.talk(about: talk.item, to: talk.agent, text: text)
            }
        }
    }

    /// The handshake: this install's key, registered with the owner's key.
    @ViewBuilder private var deviceSection: some View {
        Section {
            if let grant = desk.grant {
                Label("Registered by the owner's key \(grant.owner.signingFingerprint)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Granted \(grant.grant.granted) to this device's key \(grant.grant.device).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget this registration", role: .destructive) { desk.forgetGrant() }
            } else {
                Text("Live data and sending open only on a device the owner has registered with his own key. Demo works anywhere.")
                    .font(.callout)
                if OwnerHandshake.pinnedOwners.isEmpty {
                    Label("This build does not know the owner's key yet, so no registration can be accepted.", systemImage: "key.slash")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Button("Make a registration request") {
                    do {
                        let signer = try IdentityBook.shared.deviceSigner()
                        desk.makeRequest(signer: signer, label: IdentityDeviceKey.deviceName)
                    } catch {
                        desk.makeRequest(failed: error)
                    }
                }
                if let request = desk.request {
                    if let image = QRCode.image(for: request) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240)
                            .accessibilityLabel("The registration request as a QR code")
                    }
                    HStack(spacing: 16) {
                        ShareLink(item: request) { Label("Share", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = request } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
                    .buttonStyle(.borderless)
                    Text("The owner runs tools/owner/grant.py with his sgit key on this text and gives back an og1. grant.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Paste the grant (og1.)", text: $pastedGrant, axis: .vertical)
                    .lineLimit(1...4).font(.footnote.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Accept the grant") {
                    do {
                        let signer = try IdentityBook.shared.deviceSigner()
                        if desk.accept(grant: pastedGrant, deviceFingerprint: signer.fingerprint) { pastedGrant = "" }
                    } catch {
                        desk.makeRequest(failed: error)
                    }
                }
                .disabled(!pastedGrant.contains("og1."))
            }
            if let problem = desk.grantProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("This device")
        }
    }

    @ViewBuilder private func decisionsSection(_ feed: OwnerFeed) -> some View {
        let open = (feed.decisions ?? []).sorted { $0.at > $1.at }
        Section("Decisions for you") {
            if open.isEmpty { Text("Nothing waits for you.").foregroundStyle(.secondary) }
            ForEach(open) { decision in
                VStack(alignment: .leading, spacing: 8) {
                    Text(decision.title).font(.headline)
                    if let detail = decision.detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                    if let slides = decision.slides, let item = feed.slides?.first(where: { $0.id == slides }), let url = URL(string: item.url) {
                        Button { openURL(url) } label: { Label("See the slides", systemImage: "rectangle.on.rectangle") }.font(.footnote)
                    }
                    if let record = desk.decided(decision) {
                        Label("You chose: \(record.choice). \(record.delivery).", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.green)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { options(decision) }
                        VStack(alignment: .leading) { options(decision) }
                    }
                    Text("From \(feed.agent(decision.from)?.name ?? decision.from), \(decision.at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private func options(_ decision: OwnerFeed.Decision) -> some View {
        ForEach(decision.options, id: \.self) { choice in
            Button(choice) { Task { await desk.answer(decision, with: choice) } }
                .buttonStyle(.bordered)
                .disabled(desk.sending)
        }
    }

    @ViewBuilder private func agentsSection(_ feed: OwnerFeed) -> some View {
        Section("Every agent") {
            ForEach(feed.agentsBySize) { agent in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: Self.symbol(status: agent.status)).foregroundStyle(Self.colour(status: agent.status))
                        Text(agent.name).font(.callout.weight(.semibold))
                        Spacer()
                        Text([agent.kind, agent.account.map { "account \($0)" }].compactMap { $0 }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(agent.doing).font(.callout)
                    if let waiting = agent.waitingFor { Text("Waiting for \(waiting)").font(.caption).foregroundStyle(.orange) }
                    HStack(spacing: 16) {
                        if let site = agent.site, let url = URL(string: site) {
                            Button { openURL(url) } label: { Label("Site", systemImage: "globe") }
                        }
                        Button { talking = Talk(item: nil, agent: agent.id) } label: { Label("Message", systemImage: "bubble.left") }
                    }
                    .font(.footnote).buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private func itemsSection(_ title: String, systemImage: String, items: [OwnerFeed.Item]?, feed: OwnerFeed) -> some View {
        let items = (items ?? []).sorted { $0.made > $1.made }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.title, systemImage: systemImage).font(.callout.weight(.semibold))
                        if let summary = item.summary { Text(summary).font(.callout).foregroundStyle(.secondary) }
                        Text("\(feed.agent(item.agent)?.name ?? item.agent), \(item.made.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            if let url = URL(string: item.url) { Button { openURL(url) } label: { Label("Open", systemImage: "arrow.up.right.square") } }
                            Button { talking = Talk(item: item, agent: item.agent) } label: { Label("Talk to this page", systemImage: "mic.bubble") }
                        }
                        .font(.footnote).buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    static func symbol(status: String) -> String {
        switch status {
        case "working": "circle.dotted.circle"
        case "waiting": "hourglass"
        case "blocked": "exclamationmark.octagon"
        case "done": "checkmark.circle"
        default: "moon.zzz"
        }
    }

    static func colour(status: String) -> Color {
        switch status {
        case "working": .green
        case "waiting": .orange
        case "blocked": .red
        default: .secondary
        }
    }
}

/// Says something about a page (or to an agent), typed or spoken, and relays it to the agent.
struct OwnerTalkSheet: View {
    let talk: OwnerView.Talk
    let feed: OwnerFeed?
    let demo: Bool
    let send: (String) async -> Void
    @State private var text = ""
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let item = talk.item {
                        Text(item.title).font(.headline)
                        Text(item.url).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("To \(feed?.agent(talk.agent)?.name ?? talk.agent)").font(.callout)
                }
                Section {
                    TextField("What should change, or what do you want to ask?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .voiceInput($text)
                } footer: {
                    Text(demo ? "Demo: kept on this device, not sent." : "Sealed to the agent's key (or the conductor's, which passes it on). The server stores bytes it cannot read.")
                }
            }
            .navigationTitle(talk.item == nil ? "Message" : "Talk to this page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(demo ? "Keep" : "Send") {
                        busy = true
                        Task { await send(text); busy = false; dismiss() }
                    }
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
