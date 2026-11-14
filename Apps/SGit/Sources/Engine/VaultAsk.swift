import Foundation
import SGitVault
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A first use of Apple's on-device model in this app (the owner, 14 November 2026: "start experimenting
/// with me using Apple Intelligence here"). After VoiceDebrief's Lab (`LabModelDoor.swift`): the model is
/// asked one question, in a fresh session with no history, and may reach the vault only through four
/// tools that read a copy of its listing. Every call is recorded and shown. Nothing leaves the device,
/// nothing is decrypted for the model, and no tool can change anything.

/// A vault as the tools see it: its listing and its history, copied before the question is asked.
struct VaultFacts: Equatable, Sendable {
    struct File: Equatable, Sendable {
        let path: String
        let size: Int
    }
    struct Commit: Equatable, Sendable {
        let at: Date
        let message: String
        let byThisDevice: Bool
    }
    var files: [File]
    var commits: [Commit]
    var onDevice: Bool
    var now = Date()
}

struct AskToolResult: Equatable, Sendable {
    let text: String
    let ok: Bool
}

/// The work behind the tools: plain functions over the copy, so they can be tested without a model.
struct VaultAskToolbox: Sendable {
    let facts: VaultFacts
    static let most = 40

    func summary() -> AskToolResult {
        let bytes = facts.files.reduce(0) { $0 + $1.size }
        let top = Set(facts.files.compactMap { $0.path.contains("/") ? String($0.path.split(separator: "/")[0]) : nil }).sorted()
        var lines = ["\(facts.files.count) files, \(bytes.fileSizeText) in all.",
                     facts.onDevice ? "The vault is on this device only." : "The vault is on a server."]
        lines.append(top.isEmpty ? "No folders." : "Folders at the top: \(top.joined(separator: ", ")).")
        if let last = facts.commits.first { lines.append("Last change: \(Self.when(last.at, now: facts.now)).") }
        return AskToolResult(text: lines.joined(separator: " "), ok: true)
    }

    func listFolder(_ folder: String) -> AskToolResult {
        let clean = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let inside = facts.files.filter { clean.isEmpty || $0.path.hasPrefix(clean + "/") }
        guard !inside.isEmpty else { return AskToolResult(text: "There is no folder called \(clean).", ok: false) }
        var folders = Set<String>()
        var here: [VaultFacts.File] = []
        for file in inside {
            let rest = clean.isEmpty ? file.path : String(file.path.dropFirst(clean.count + 1))
            if let slash = rest.firstIndex(of: "/") { folders.insert(String(rest[..<slash])) } else { here.append(file) }
        }
        var lines = folders.sorted().map { "folder: \($0)" }
        lines += here.prefix(Self.most).map { "file: \(VaultListing.name(of: $0.path)) (\($0.size.fileSizeText))" }
        if here.count > Self.most { lines.append("and \(here.count - Self.most) more files") }
        return AskToolResult(text: lines.joined(separator: "\n"), ok: true)
    }

    func recentChanges(limit: Int) -> AskToolResult {
        let shown = facts.commits.prefix(max(1, min(limit, 20)))
        guard !shown.isEmpty else { return AskToolResult(text: "No history has been read.", ok: false) }
        return AskToolResult(text: shown.map {
            "\(Self.when($0.at, now: facts.now)), \($0.byThisDevice ? "this device" : "another device"): \($0.message)"
        }.joined(separator: "\n"), ok: true)
    }

    func findFiles(_ text: String) -> AskToolResult {
        let wanted = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return AskToolResult(text: "Nothing to look for.", ok: false) }
        let found = facts.files.filter { $0.path.lowercased().contains(wanted) }
        guard !found.isEmpty else { return AskToolResult(text: "No file has \(wanted) in its name.", ok: true) }
        var lines = found.prefix(Self.most).map { "\($0.path) (\($0.size.fileSizeText))" }
        if found.count > Self.most { lines.append("and \(found.count - Self.most) more") }
        return AskToolResult(text: lines.joined(separator: "\n"), ok: true)
    }

    static func when(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 2 { return "just now" }
        if minutes < 120 { return "\(minutes) minutes ago" }
        if minutes < 48 * 60 { return "\(minutes / 60) hours ago" }
        return "\(minutes / (24 * 60)) days ago"
    }
}

/// One call the model made, as the screen shows it.
struct AskToolCall: Equatable, Sendable, Identifiable {
    let id: Int
    let name: String
    let arguments: String
    let result: String
    let ok: Bool
}

/// Everything that passed through one question.
struct AskRecord: Equatable, Sendable {
    var question: String
    var answer = ""
    var problem: String?
    var calls: [AskToolCall] = []
    var seconds = 0.0
}

/// Collects the tool calls of one question. Tools may be called concurrently, so it is locked.
final class AskRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [AskToolCall] = []

    var calls: [AskToolCall] {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    func record(_ name: String, _ arguments: String, _ work: () -> AskToolResult) -> String {
        let result = work()
        lock.lock()
        kept.append(AskToolCall(id: kept.count + 1, name: name, arguments: arguments, result: result.text, ok: result.ok))
        lock.unlock()
        return result.text
    }
}

enum VaultAsk {
    static let instructions = """
    You answer one question about a folder of files called a vault. You cannot see the files' contents, \
    only their names, sizes, folders and the history of changes, and only through the tools. Call a tool \
    before you answer. Answer in two or three plain sentences. If the tools do not tell you, say that \
    you do not know.
    """

    /// Whether Apple's model can run here, and if not, why, in words for the screen.
    static var unavailable: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This device does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is switched off in Settings."
            case .modelNotReady: return "Apple's model is still downloading. Try again later."
            @unknown default: return "Apple's model is not available right now."
            }
        }
        #else
        return "This build has no Foundation Models SDK."
        #endif
    }

    static func ask(_ question: String, about facts: VaultFacts) async -> AskRecord {
        var record = AskRecord(question: question)
        let started = Date()
        if let why = unavailable {
            record.problem = why
            return record
        }
        #if canImport(FoundationModels)
        let recorder = AskRecorder()
        let toolbox = VaultAskToolbox(facts: facts)
        let tools: [any Tool] = [AskSummaryTool(toolbox: toolbox, recorder: recorder),
                                 AskListFolderTool(toolbox: toolbox, recorder: recorder),
                                 AskRecentChangesTool(toolbox: toolbox, recorder: recorder),
                                 AskFindFilesTool(toolbox: toolbox, recorder: recorder)]
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        do {
            record.answer = try await session.respond(to: question).content
        } catch {
            record.problem = "Apple's model did not answer: \(error.localizedDescription)"
        }
        record.calls = recorder.calls
        #endif
        record.seconds = Date().timeIntervalSince(started)
        return record
    }
}

#if canImport(FoundationModels)
struct AskSummaryTool: Tool {
    let name = "vault_summary"
    let description = "How many files the vault holds, their total size, its top folders and when it last changed"
    let toolbox: VaultAskToolbox
    let recorder: AskRecorder

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        recorder.record(name, "") { toolbox.summary() }
    }
}

struct AskListFolderTool: Tool {
    let name = "list_folder"
    let description = "The folders and files directly inside one folder of the vault"
    let toolbox: VaultAskToolbox
    let recorder: AskRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The folder's path, such as stage or team/dinner. Empty for the top of the vault")
        let folder: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.record(name, arguments.folder) { toolbox.listFolder(arguments.folder) }
    }
}

struct AskRecentChangesTool: Tool {
    let name = "recent_changes"
    let description = "The most recent changes to the vault: when, by this device or another, and the message"
    let toolbox: VaultAskToolbox
    let recorder: AskRecorder

    @Generable
    struct Arguments {
        @Guide(description: "How many changes to list", .range(1...20))
        let limit: Int
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.record(name, "\(arguments.limit)") { toolbox.recentChanges(limit: arguments.limit) }
    }
}

struct AskFindFilesTool: Tool {
    let name = "find_files"
    let description = "The files whose name or folder contains some text"
    let toolbox: VaultAskToolbox
    let recorder: AskRecorder

    @Generable
    struct Arguments {
        @Guide(description: "Part of a file name, such as keynote or .mov")
        let text: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.record(name, arguments.text) { toolbox.findFiles(arguments.text) }
    }
}
#endif
