import Foundation
import SGitPeople
import SwiftUI

/// Who a shared vault was given to, kept in the vault itself so that every member's app can show it:
/// `.sgit/members.json`, schema `sgit.ai/members/v1`. Names and key fingerprints, never keys.
struct VaultMembers: Codable, Equatable, Sendable {
    static let path = ".sgit/members.json"
    static let format = "sgit.ai/members/v1"

    struct Member: Codable, Equatable, Sendable, Identifiable {
        var id: String { fingerprint }
        var name: String
        var fingerprint: String
        var addedAt: Date
        var addedBy: String
    }

    var format = VaultMembers.format
    var members: [Member]

    /// Adds people not already listed; a person given the vault twice is listed once.
    func adding(_ people: [(name: String, fingerprint: String)], by giver: String, at date: Date = Date()) -> VaultMembers {
        var out = self
        for person in people where !out.members.contains(where: { $0.fingerprint == person.fingerprint }) {
            out.members.append(Member(name: person.name, fingerprint: person.fingerprint, addedAt: date, addedBy: giver))
        }
        return out
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> VaultMembers? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let read = try? decoder.decode(VaultMembers.self, from: data), read.format == format else { return nil }
        return read
    }
}

extension VaultShelf {
    func members(of vault: SavedVault) async -> VaultMembers? {
        guard contents[vault.id]?.files.contains(where: { $0.path == VaultMembers.path }) == true,
              let handle = try? await open(vault), let data = try? await handle.read(VaultMembers.path) else { return nil }
        return VaultMembers.decode(data)
    }
}

/// "Make a shared vault for these people", or give an existing vault to more of them: the vault's key is
/// sealed to each person's key and dropped in their inbox. For now a member holds the vault key, so can do
/// everything (the owner: "for now, the shared vault means you share the vault key, which is okay").
struct ShareWithPeopleView: View {
    let shelf: VaultShelf
    let hub: PeopleHub
    /// Nil to make a new vault.
    let vault: SavedVault?
    @State private var name = ""
    @State private var chosen: Set<String> = []
    @State private var working: String?
    @State private var outcome: [String] = []
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    private var reachable: [Contact] { hub.contacts.filter(\.canReceive) }

    var body: some View {
        Form {
            if vault == nil {
                Section {
                    TextField("Name, such as Team: devices", text: $name)
                } footer: {
                    Text("A new vault, made here, put on \(shelf.serverName), and given to the people you choose.")
                }
            }
            Section {
                if reachable.isEmpty {
                    Text("Nobody you can send to yet: a person's inbox comes with their card once they have made one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reachable) { contact in
                    Button {
                        if chosen.contains(contact.id) { chosen.remove(contact.id) } else { chosen.insert(contact.id) }
                    } label: {
                        HStack(spacing: 12) {
                            ContactPhoto(data: hub.book.photo(contact.id), name: contact.name).frame(width: 36, height: 36)
                            VStack(alignment: .leading) {
                                Text(contact.name)
                                Text(TrustLink.of(isMutual: contact.isMutual, verified: contact.verifiedAt != nil).words)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: chosen.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Give it to")
            } footer: {
                Text("Each person receives the vault's key sealed to their own key, so only they can open what you send. Whoever holds the key can read, add, change and delete everything in the vault, and it cannot be taken back.")
            }
            if !shelf.hasToken {
                Section {
                    Label("A shared vault has to be on the server, which needs an access key: add one in Settings.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            }
            if let working { Section { HStack { ProgressView(); Text(working) } } }
            if let problem { Section { ProblemLabel(text: problem) } }
            if !outcome.isEmpty { Section("Done") { ForEach(outcome, id: \.self) { Text($0) } } }
        }
        .navigationTitle(vault.map { "Give \($0.name)" } ?? "A shared vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(outcome.isEmpty ? "Cancel" : "Done") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") { Task { await send() } }
                    .disabled(working != nil || chosen.isEmpty || !shelf.hasToken
                              || (vault == nil && name.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }

    private func send() async {
        problem = nil
        outcome = []
        defer { working = nil }
        var target = vault
        if target == nil {
            working = "Making the vault"
            target = await shelf.create(name: name)
        }
        guard var target else { problem = shelf.problem ?? "The vault could not be made."; return }
        if shelf.current(target).onDevice {
            working = "Putting it on \(shelf.serverName)"
            guard await shelf.sendToServer(target) else { problem = shelf.problem ?? "It could not be put on the server."; return }
            target = shelf.current(target)
        }
        let people = reachable.filter { chosen.contains($0.id) }
        working = "Writing who it is shared with"
        let before = await shelf.members(of: target) ?? VaultMembers(members: [
            VaultMembers.Member(name: hub.name, fingerprint: hub.identity.bundle.fingerprint, addedAt: Date(), addedBy: hub.name)])
        let after = before.adding(people.map { ($0.name, $0.id) }, by: hub.name)
        do {
            try await shelf.put(try after.encoded(), at: VaultMembers.path, in: target,
                                message: VaultNaming.fit("Shared with " + people.map(\.name).joined(separator: ", ")))
        } catch {
            problem = "The list of members was not written: \(VaultShelf.describe(error))"
            return
        }
        for person in people {
            working = "Sending it to \(person.name)"
            do {
                try await hub.sendVault(VaultInvitation(name: target.name, key: target.keyText, server: shelf.server.absoluteString), to: person)
                outcome.append("Sent to \(person.name), sealed to their key.")
            } catch {
                outcome.append("Not sent to \(person.name): \(error.localizedDescription)")
            }
        }
        UsageLog.shared.action("vault.share-with-people")
    }
}
