import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Collects the tool calls of one request. Tools may be called concurrently, so it is locked.
final class ModelDoorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ModelDoorToolCall] = []

    var toolCalls: [ModelDoorToolCall] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    /// Runs a tool's work, times it, and records the call with what it returned.
    func measure(tool name: String, arguments: [String: String], _ work: () -> LabToolResult) -> String {
        let clock = ContinuousClock()
        let start = clock.now
        let result = work()
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        lock.lock()
        calls.append(ModelDoorToolCall(order: calls.count + 1, name: name, arguments: arguments,
                                       result: result.text, ok: result.ok, durationMs: ms))
        lock.unlock()
        return result.text
    }
}

/// A set of tools the door can offer: what each is called and says of itself, and, where the
/// framework exists, the tools themselves.
protocol ModelDoorToolkit: Sendable {
    var definitions: [ModelDoorToolDefinition] { get }
    #if canImport(FoundationModels)
    func tools(named names: [String], recorder: ModelDoorRecorder) -> [any Tool]
    #endif
}

extension LabToolbox: ModelDoorToolkit {
    var definitions: [ModelDoorToolDefinition] {
        LabToolId.allCases.map { ModelDoorToolDefinition(name: $0.rawValue, description: $0.summary) }
    }

    #if canImport(FoundationModels)
    func tools(named names: [String], recorder: ModelDoorRecorder) -> [any Tool] {
        LabTools.make(LabToolId.allCases.filter { names.contains($0.rawValue) }, toolbox: self, recorder: recorder)
    }
    #endif
}

/// The model door: the one place a request to Apple's on-device model is made from the Lab. It has
/// a policy (which tools this request is offered) and a record (everything that passed through).
/// One fresh session per request and no history, so a request is one question.
///
/// The debrief pipeline does not go through here yet. It could: a request with no tools is its case.
/// Nothing here is a security boundary. It is a way to organise and to see.
enum ModelDoor {
    static func ask(_ request: ModelDoorRequest, toolbox: LabToolbox) async -> ModelDoorRecord {
        await ask(request, toolkit: toolbox)
    }

    static func ask(_ request: ModelDoorRequest, toolkit: some ModelDoorToolkit) async -> ModelDoorRecord {
        let offered = toolkit.definitions.filter { request.policy.allows($0.name) }
        var record = ModelDoorRecord(
            startedAt: Date(),
            instructions: request.instructions,
            prompt: request.prompt,
            policy: request.policy,
            toolsOffered: offered,
            toolsWithheld: toolkit.definitions.filter { !request.policy.allows($0.name) }.map(\.name))
        let recorder = ModelDoorRecorder()
        let clock = ContinuousClock()
        let start = clock.now

        #if canImport(FoundationModels)
        if case .unavailable(let why) = OnDeviceModel.status {
            record.error = ModelDoorError(kind: "unavailable", words: why, raw: "")
        } else {
            let tools = toolkit.tools(named: offered.map(\.name), recorder: recorder)
            let session = request.instructions.isEmpty
                ? LanguageModelSession(tools: tools)
                : LanguageModelSession(tools: tools, instructions: request.instructions)
            do {
                let response = try await session.respond(to: request.prompt)
                record.answer = response.content
            } catch {
                record.error = describe(error)
            }
            for entry in session.transcript {
                record.transcript.append(String(describing: entry))
                if case .toolCalls(let calls) = entry {
                    for call in calls { record.modelToolRequests.append(call.toolName) }
                }
            }
        }
        #else
        record.error = ModelDoorError(kind: "noSDK", words: "This build has no Foundation Models SDK.", raw: "")
        #endif

        let elapsed = clock.now - start
        record.totalMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        record.toolCalls = recorder.toolCalls
        return record
    }

    #if canImport(FoundationModels)
    private static func describe(_ error: Error) -> ModelDoorError {
        let raw = String(reflecting: error)
        if let failure = error as? LanguageModelSession.ToolCallError {
            return ModelDoorError(kind: "toolFailed",
                                  words: "The tool \(failure.tool.name) failed: \(failure.underlyingError.localizedDescription)",
                                  raw: raw)
        }
        // Sorted by the error's own description rather than by type: the error types changed
        // between the iOS 26 and iOS 27 SDKs, and this reads both.
        return ModelDoorError.classify(raw: raw, description: error.localizedDescription)
    }
    #endif
}

#if canImport(FoundationModels)
/// The Lab's tools as Foundation Models sees them. Each hands its work to the toolbox and its
/// record to the door's recorder.
enum LabTools {
    static func make(_ ids: [LabToolId], toolbox: LabToolbox, recorder: ModelDoorRecorder) -> [any Tool] {
        ids.map { id -> any Tool in
            switch id {
            case .clock: return LabClockTool(toolbox: toolbox, recorder: recorder)
            case .listNotes: return LabListNotesTool(toolbox: toolbox, recorder: recorder)
            case .readNote: return LabReadNoteTool(toolbox: toolbox, recorder: recorder)
            case .chooseScreen: return LabChooseScreenTool(toolbox: toolbox, recorder: recorder)
            }
        }
    }
}

struct LabClockTool: Tool {
    let name = LabToolId.clock.rawValue
    let description = LabToolId.clock.summary
    let toolbox: LabToolbox
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: [:]) { toolbox.currentDateTime() }
    }
}

struct LabListNotesTool: Tool {
    let name = LabToolId.listNotes.rawValue
    let description = LabToolId.listNotes.summary
    let toolbox: LabToolbox
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "How many notes to list", .range(1...20))
        let limit: Int
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["limit": "\(arguments.limit)"]) { toolbox.listNotes(limit: arguments.limit) }
    }
}

struct LabReadNoteTool: Tool {
    let name = LabToolId.readNote.rawValue
    let description = LabToolId.readNote.summary
    let toolbox: LabToolbox
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The id of the note, as the list of notes gives it")
        let id: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["id": arguments.id]) { toolbox.readNote(id: arguments.id) }
    }
}

struct LabChooseScreenTool: Tool {
    let name = LabToolId.chooseScreen.rawValue
    let description = LabToolId.chooseScreen.summary
    let toolbox: LabToolbox
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The screen to show next", .anyOf(["record", "library", "note", "vaults", "settings"]))
        let screen: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["screen": arguments.screen]) { toolbox.chooseScreen(arguments.screen) }
    }
}
#endif

/// The Lab's runs, kept for as long as the app is open so they can be compared.
@MainActor
@Observable
final class LabSession {
    static let shared = LabSession()

    private(set) var runs: [LabRun] = []
    private(set) var running = false

    /// One request through the model door, added to the top of the list.
    func run(presetId: String?, instructions: String, prompt: String, tools: Set<LabToolId>, store: NoteStore) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let device = LabDevice(appVersion: AppInfo.versionLine(),
                               system: ProcessInfo.processInfo.operatingSystemVersionString,
                               machine: Diagnostics.machineIdentifier(),
                               modelStatus: OnDeviceModel.status.text,
                               modelContextSize: OnDeviceModel.contextSize)
        let request = ModelDoorRequest(instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                                       prompt: prompt, policy: ModelDoorPolicy(tools: tools))
        let record = await ModelDoor.ask(request, toolbox: LabToolbox(store: store))
        let preset = LabPreset.find(presetId)
        runs.insert(LabRun(id: Note.newId(at: record.startedAt), presetId: preset?.id,
                           expectedTools: preset?.expects.map(\.rawValue), device: device, record: record), at: 0)
    }

    func clear() { runs = [] }
}
