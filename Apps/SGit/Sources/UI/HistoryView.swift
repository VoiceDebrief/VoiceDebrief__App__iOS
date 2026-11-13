import SGitVault
import SwiftUI

/// The commits of a vault, newest first.
struct HistoryView: View {
    let shelf: VaultShelf
    let vault: SavedVault

    var body: some View {
        let history = shelf.contents[vault.id]?.history ?? []
        List {
            if history.isEmpty {
                Text("No history has been read yet.").foregroundStyle(.secondary)
            }
            ForEach(history) { commit in
                NavigationLink {
                    CommitView(shelf: shelf, vault: vault, commit: commit)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(commit.message.isEmpty ? "(no message)" : commit.message).lineLimit(2)
                        Text("\(commit.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(String(commit.commitId.suffix(12)))")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                        Label(Self.words(commit.signature), systemImage: commit.signature.isVerified ? "checkmark.seal" : "seal")
                            .font(.footnote)
                            .foregroundStyle(commit.signature.isVerified ? Color.secondary : Color.orange)
                    }
                }
            }
            if history.count >= 50 {
                Text("The 50 most recent commits are shown.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { _ = try? await shelf.load(vault) }
    }

    static func words(_ status: VaultSignatureStatus) -> String {
        switch status {
        case .verified: return "Signature verified"
        case .unsigned: return "Not signed"
        case .invalid: return "Signature does not verify"
        case .keyMissing: return "Signed, but the key is not in the vault"
        case .legacy: return "Signed in an older form, not checked"
        }
    }
}

/// One commit: who signed it and what it changed.
struct CommitView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let commit: VaultCommit
    @State private var changes: [VaultChange]?
    @State private var fingerprint: String?
    @State private var problem: String?

    var body: some View {
        List {
            Section("Commit") {
                LabeledContent("Message", value: commit.message.isEmpty ? "(no message)" : commit.message)
                LabeledContent("When", value: commit.timestamp.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Id", value: String(commit.commitId.suffix(12)))
                LabeledContent("Parents", value: commit.parents.isEmpty ? "none: the first commit" : commit.parents.map { String($0.suffix(12)) }.joined(separator: ", "))
            }
            Section {
                LabeledContent("Signature", value: HistoryView.words(commit.signature))
                if let keyId = commit.authorKeyId {
                    LabeledContent("Key", value: keyId)
                }
                if let fingerprint {
                    LabeledContent("Fingerprint", value: VaultNaming.grouped(fingerprint))
                    if fingerprint == shelf.deviceFingerprint {
                        Label("This device's key", systemImage: "iphone").font(.callout)
                    }
                }
            } header: {
                Text("Signed by")
            } footer: {
                Text("The fingerprint is the first 16 characters of the SHA-256 of the public key that signed this commit. It says which key, not which person: nothing in the vault yet ties a key to a name.")
            }
            Section("What changed") {
                if let problem { ProblemLabel(text: problem) }
                if let changes {
                    if changes.isEmpty { Text("No files changed.").foregroundStyle(.secondary) }
                    ForEach(changes) { change in
                        HStack {
                            Image(systemName: Self.icon(change.kind)).foregroundStyle(Self.colour(change.kind))
                            Text(change.path).font(.footnote).lineLimit(2)
                            Spacer()
                            Text(change.size.fileSizeText).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else if problem == nil {
                    ProgressView()
                }
            }
        }
        .navigationTitle(String(commit.commitId.suffix(12)))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let keyId = commit.authorKeyId { fingerprint = await shelf.fingerprint(ofKey: keyId, in: vault) }
            do {
                changes = try await shelf.changes(in: commit, of: vault)
            } catch {
                problem = "The changes could not be read: \(VaultShelf.describe(error))"
            }
        }
    }

    static func icon(_ kind: VaultChange.Kind) -> String {
        switch kind {
        case .added: return "plus.circle"
        case .modified: return "pencil.circle"
        case .removed: return "minus.circle"
        }
    }

    static func colour(_ kind: VaultChange.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .modified: return .orange
        case .removed: return .red
        }
    }
}
