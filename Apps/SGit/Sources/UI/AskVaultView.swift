import SGitVault
import SwiftUI

/// An experiment: ask Apple's on-device model a question about this vault. The model sees names, sizes
/// and the history through four tools, never a file's contents, and every call it makes is shown.
struct AskVaultView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    @State private var question = ""
    @State private var asking = false
    @State private var records: [AskRecord] = []

    static let examples = ["What is in this vault?", "What changed most recently?", "Are there any videos?"]

    var body: some View {
        List {
            Section {
                TextField("Ask about this vault", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                Button {
                    Task { await ask(question) }
                } label: {
                    Label(asking ? "Asking Apple's model" : "Ask", systemImage: "sparkles")
                }
                .disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty || VaultAsk.unavailable != nil)
                ForEach(Self.examples, id: \.self) { example in
                    Button(example) { Task { await ask(example) } }
                        .font(.callout)
                        .disabled(asking || VaultAsk.unavailable != nil)
                }
            } footer: {
                if let why = VaultAsk.unavailable {
                    Text("\(why) Nothing can be asked on this device.")
                } else {
                    Text("An experiment. Apple's model runs on this device and nothing is sent anywhere. It is told the names, sizes and folders of the files and the history of changes, through the calls listed under each answer. It is not given what is inside any file, and it cannot change the vault. Its answers can be wrong.")
                }
            }
            ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                Section(record.question) {
                    if let problem = record.problem {
                        ProblemLabel(text: problem)
                    } else {
                        Text(record.answer)
                    }
                    ForEach(record.calls) { call in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(call.arguments.isEmpty ? call.name : "\(call.name): \(call.arguments)",
                                  systemImage: call.ok ? "wrench.and.screwdriver" : "exclamationmark.triangle")
                                .font(.footnote.weight(.semibold))
                            Text(call.result).font(.footnote).foregroundStyle(.secondary).lineLimit(8)
                        }
                    }
                    Text(record.calls.isEmpty ? "No tool was called · \(Int(record.seconds.rounded())) s"
                                              : "\(record.calls.count) tool call\(record.calls.count == 1 ? "" : "s") · \(Int(record.seconds.rounded())) s")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ask this vault")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask(_ text: String) async {
        let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !asking else { return }
        asking = true
        defer { asking = false }
        UsageLog.shared.action("ask.question")
        let contents = shelf.contents[vault.id]
        let device = shelf.deviceKeyId
        let facts = VaultFacts(files: (contents?.files ?? []).map { VaultFacts.File(path: $0.path, size: $0.size) },
                               commits: (contents?.history ?? []).map {
                                   VaultFacts.Commit(at: $0.timestamp, message: $0.message, byThisDevice: $0.authorKeyId != nil && $0.authorKeyId == device)
                               },
                               onDevice: shelf.current(vault).onDevice)
        let record = await VaultAsk.ask(asked, about: facts)
        records.insert(record, at: 0)
        if record.problem == nil { question = "" }
    }
}
