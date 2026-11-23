import SwiftUI
import UIKit
import WebKit

/// Sites (R7, tier 1): scan a Sovereign Website's QR code, see the site, say what should change, and the site's
/// keeper (an agent) answers here and changes the site. "Do you want to make a change to the website? Just speak
/// here, and then the agent will come back to you."
struct SitesView: View {
    private var desk: SitesDesk { SitesDesk.shared }
    @State private var scanning = false
    @State private var pasted = ""
    @State private var adding = false

    var body: some View {
        List {
            if !desk.sites.isEmpty {
                Section("Your sites") {
                    ForEach(desk.sites) { site in
                        NavigationLink(value: site) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(site.name).font(.headline)
                                    if (desk.unseen[site.origin] ?? 0) > 0 {
                                        Text("\(desk.unseen[site.origin] ?? 0) new").font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                                    }
                                }
                                Text(URL(string: site.origin)?.host ?? site.origin).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { desk.remove(site) } }
                    }
                }
            }
            Section {
                Button { scanning = true } label: { Label("Scan a site's QR code", systemImage: "qrcode.viewfinder") }
                TextField("Or paste the site's link (…/send/#key=…)", text: $pasted, axis: .vertical)
                    .lineLimit(1...3).font(.footnote.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Add the site") { add(pasted) }.disabled(!pasted.contains("key=") || adding)
            } header: {
                Text("Add a site")
            } footer: {
                Text("The site's keeper gives you the QR code. It holds the site's address and a key that is yours: it is kept in your Keychain, and the keeper acts only on what that key signs.")
            }
            if let problem = desk.problem {
                Section { Text(problem).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Sites")
        .navigationDestination(for: SitesDesk.Site.self) { SiteDetailView(site: $0) }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScanner { text in scanning = false; add(text) }
                    .ignoresSafeArea()
                    .navigationTitle("Scan the site's QR code").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
    }

    private func add(_ text: String) {
        adding = true
        Task {
            if await desk.add(link: text) != nil { pasted = "" }
            adding = false
        }
    }
}

/// One site: the site itself, what its keeper said, and a way to speak to it.
struct SiteDetailView: View {
    let site: SitesDesk.Site
    private var desk: SitesDesk { SitesDesk.shared }
    @State private var text = ""
    @State private var reload = 0
    @State private var kind = SiteSend.defaultKind

    var body: some View {
        VStack(spacing: 0) {
            if desk.changed.contains(site.origin) {
                Button {
                    reload += 1
                    desk.reloaded(site)
                } label: {
                    Label("The site has changed. Show it", systemImage: "sparkles")
                        .frame(maxWidth: .infinity).padding(10)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal).padding(.top, 6)
            }
            SitePage(address: site.origin + "/", reload: reload)
                .frame(maxHeight: .infinity)
            Divider()
            conversation
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: site.origin) {
            while !Task.isCancelled {
                await desk.check(site)
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onDisappear { desk.markSeen(site) }
    }

    private var answers: [SiteReply] { desk.replies[site.origin] ?? [] }
    private var mine: [SitesDesk.Sent] { desk.sent.filter { $0.site == site.origin }.sorted { $0.at > $1.at } }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if answers.isEmpty && mine.isEmpty {
                        Text("Say what you would like changed. The site's keeper reads it and answers here, usually within minutes.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(answers.prefix(5)) { reply in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.text).font(.callout)
                            Text("The keeper" + (reply.at.map { ", \($0)" } ?? "")).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if let last = mine.first {
                        Text("You: \(last.text)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .frame(maxHeight: 180)
            Picker("About", selection: $kind) {
                ForEach(SiteSend.kinds, id: \.id) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.menu)
            .font(.caption)
            HStack(alignment: .bottom) {
                TextField("Speak or type what should change", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .voiceInput($text)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { if await desk.send(text, kind: kind, to: site) { text = "" } }
                } label: {
                    Image(systemName: "paperplane.fill").padding(6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(desk.sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send to the site's keeper")
            }
            if let problem = desk.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
        }
        .padding()
        .background(.bar)
    }
}

/// The site, in a web view that keeps nothing after it closes. Its own /send/ page is not needed here: the app
/// holds the key and does the sending.
struct SitePage: UIViewRepresentable {
    let address: String
    let reload: Int

    final class Coordinator { var reload = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        if let url = URL(string: address) { view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.reload != reload else { return }
        context.coordinator.reload = reload
        if let url = URL(string: address) { view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)) }
    }
}
