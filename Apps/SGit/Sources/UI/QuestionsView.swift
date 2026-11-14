import SwiftUI

/// A question the people building the app want the owner to answer.
struct OwnerQuestion: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let asked: String
    let question: String
    let why: String
    let options: [String]

    static let resource = "sg-questions"

    static func bundled(_ bundle: Bundle = .main) -> [OwnerQuestion] {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([OwnerQuestion].self, from: data)) ?? []
    }

    /// The one message that carries an answer over the developer's lane.
    static func laneMessage(question: OwnerQuestion, choice: String?, words: String, app: String, device: String,
                            at date: Date = Date()) throws -> Data {
        struct Answer: Encodable {
            let question: String; let id: String; let choice: String?; let words: String; let app: String; let device: String; let at: Date
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(Answer(question: question.question, id: question.id, choice: choice, words: words,
                                             app: app, device: device, at: date))
        let header = DeveloperLane.Header(kind: "sgit/answer/v1", note: "answer-\(question.id)-\(Int(date.timeIntervalSince1970))",
                                          part: 1, of: 1, name: "answer.json", size: body.count,
                                          sha256: DeveloperLane.sha256Hex(body), app: app,
                                          sentAt: ISO8601DateFormatter().string(from: date))
        return try DeveloperLane.message(header: header, body: body)
    }
}

/// The questions waiting for the owner. An answer can be a choice, typed words, or words spoken with the
/// keyboard's microphone (dictation turns speech into text on the device).
struct QuestionsView: View {
    @State private var questions = OwnerQuestion.bundled()
    @AppStorage("questions.answered") private var answeredText = ""

    private var answered: Set<String> { Set(answeredText.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                Text("Questions from the people building this app. Choose an answer, type one, or tap the microphone on the keyboard and say it. Answers are encrypted on this device to the developers' key and sent over their lane.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            let open = questions.filter { !answered.contains($0.id) }
            Section(open.isEmpty ? "Nothing waiting" : "Waiting for you (\(open.count))") {
                ForEach(open) { question in
                    NavigationLink {
                        QuestionView(question: question) { answeredText = (answered.union([question.id])).sorted().joined(separator: ",") }
                            .tracked("question")
                    } label: {
                        Text(question.question)
                    }
                }
            }
            let done = questions.filter { answered.contains($0.id) }
            if !done.isEmpty {
                Section("Answered") {
                    ForEach(done) { question in
                        Label(question.question, systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Questions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct QuestionView: View {
    let question: OwnerQuestion
    let sent: () -> Void
    @State private var choice: String?
    @State private var words = ""
    @State private var sending = false
    @State private var said: String?
    @FocusState private var typing: Bool

    var body: some View {
        List {
            Section {
                Text(question.question).font(.headline)
                Text(question.why).font(.callout).foregroundStyle(.secondary)
            }
            Section("Choose") {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        choice = choice == option ? nil : option
                    } label: {
                        Label(option, systemImage: choice == option ? "largecircle.fill.circle" : "circle")
                    }
                }
            }
            Section {
                TextField("Or say it in your own words", text: $words, axis: .vertical)
                    .lineLimit(3...10)
                    .focused($typing)
            } header: {
                Text("In your own words")
            } footer: {
                Text("To speak, tap the microphone on the keyboard.")
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    Label(sending ? "Sending" : "Send the answer", systemImage: "paperplane")
                }
                .disabled(sending || (choice == nil && words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                          || DeveloperLane.builtIn == nil)
                if let said { Text(said).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("A question")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        guard let lane = DeveloperLane.builtIn else { return }
        sending = true
        defer { sending = false }
        do {
            let app = "sgit " + AppInfo.versionLine()
            let message = try OwnerQuestion.laneMessage(question: question, choice: choice, words: words, app: app,
                                                        device: "\(UsageLog.machineIdentifier()) \(UsageLog.installId)")
            try await lane.send([message]) { _, _ in }
            said = "Sent. Thank you."
            UsageLog.shared.action("question.answer")
            sent()
        } catch {
            said = "Not sent: \(error.localizedDescription)"
        }
    }
}
