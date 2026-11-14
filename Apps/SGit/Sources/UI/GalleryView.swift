import SafariServices
import SGitVault
import SwiftUI
import VisionKit

/// A gallery of vaults worth showing. Each opens in the web Vault, in a browser inside the app.
/// The list is data: what the user added here, and `showcase.json` from any vault on this device.
struct GalleryView: View {
    let shelf: VaultShelf
    @State private var search = ""
    @State private var showing: Shown?
    @State private var adding = false
    @State private var loading = false
    @State private var notice: String?

    struct Shown: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        let groups = Gallery.grouped(shelf.gallery, search: search)
        List {
            if shelf.gallery.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing in the gallery yet").font(.headline)
                        Text("The gallery is a list of vaults to show somebody: each has a name, a line about it and a link, and opens in the web Vault inside the app.")
                            .foregroundStyle(.secondary)
                        Text("Add a link here with the plus button. Or keep the list in a vault: a file called showcase.json at the top of any vault on this device is read into the gallery.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            if let notice {
                Section { Label(notice, systemImage: "checkmark.circle").font(.callout) }
            }
            if let problem = shelf.problem {
                Section {
                    ProblemLabel(text: problem)
                    Button("Dismiss") { shelf.clearProblem() }
                }
            }
            ForEach(groups, id: \.topic) { group in
                Section(group.topic.isEmpty ? "Other" : group.topic) {
                    ForEach(group.entries) { entry in
                        Button { open(entry) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.rectangle.stack").font(.title3).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).foregroundStyle(.primary)
                                    if !entry.description.isEmpty {
                                        Text(entry.description).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                }
                                Spacer()
                                Image(systemName: "safari").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if shelf.isOwn(entry) {
                                Button("Remove", role: .destructive) { shelf.removeFromGallery(entry) }
                            }
                            if let key = Gallery.nativeKey(of: entry.link) {
                                Button("Add to my vaults") {
                                    Task {
                                        if await shelf.add(keyText: key, name: entry.name) != nil {
                                            notice = "\(entry.name) is in your vaults."
                                        }
                                    }
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }
            }
            if loading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the vaults for a showcase.json")
                    }
                }
            }
        }
        .navigationTitle("Gallery")
        .searchable(text: $search, prompt: "Name, topic or description")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { adding = true }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $adding) { AddGalleryEntrySheet(shelf: shelf) }
        .fullScreenCover(item: $showing) { shown in
            SafariView(url: shown.url).ignoresSafeArea()
        }
    }

    private func refresh() async {
        loading = true
        await shelf.refreshGallery()
        loading = false
    }

    private func open(_ entry: GalleryEntry) {
        UsageLog.shared.action("gallery.open")
        notice = nil
        guard let url = Gallery.webAddress(of: entry.link) else {
            shelf.clearProblem()
            notice = "\(entry.name) has a link the web Vault cannot be given."
            return
        }
        showing = Shown(url: url)
    }
}

/// The system's own browser, inside the app. The page is the web Vault's: the app shows it and takes
/// no part in it. A key in the link sits after the `#`, which a browser does not send to a server.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct AddGalleryEntrySheet: View {
    let shelf: VaultShelf
    @State private var name = ""
    @State private var about = ""
    @State private var topic = ""
    @State private var link = ""
    @State private var scanning = false
    @Environment(\.dismiss) private var dismiss

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    private var usable: Bool { Gallery.webAddress(of: link) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Vault link, key or read-only token", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if canScan {
                        Button("Scan a QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                } footer: {
                    Text("A link from the web Vault's Share screen, or a key. It is kept in this device's Keychain. For something you will show widely, use a read key or a read-only token, not the vault key: whoever sees a vault key can change the vault.")
                }
                Section {
                    TextField("Name", text: $name)
                    TextField("One line about it", text: $about)
                    TextField("Topic", text: $topic)
                }
            }
            .navigationTitle("Add to the gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let shown = name.trimmingCharacters(in: .whitespaces)
                        shelf.addToGallery(GalleryEntry(name: shown.isEmpty ? "A vault" : shown, description: about,
                                                        topic: topic, link: link.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                    .disabled(!usable)
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScanner { text in
                        link = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        scanning = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan a vault link")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } }
                    }
                }
            }
        }
    }
}
