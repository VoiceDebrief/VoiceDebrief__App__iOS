import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

/// What the share sheet is doing: finding the audio among what was shared, showing its name and length,
/// and, on "Debrief in VoiceDebrief", copying it into the share inbox for the app.
@MainActor
@Observable
final class ShareModel {
    enum State: Equatable {
        case loading
        case ready
        case kept
        case failed(String)
    }

    /// The types looked for, in order. WhatsApp's voice notes are Ogg Opus; the rest is any audio.
    static let audioTypes = ["org.xiph.opus", "org.xiph.ogg-audio", "org.xiph.oga", "org.xiph.ogg", UTType.audio.identifier]

    private(set) var state: State = .loading
    private(set) var name = ""
    private(set) var seconds: Double?
    private(set) var bytes = 0
    private var file: URL?
    private var typeIdentifier = ""
    private let context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var lengthText: String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "" }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    func load() async {
        guard let found = Self.audioProvider(in: context) else {
            state = .failed("No audio was shared. VoiceDebrief takes voice notes and audio files.")
            return
        }
        let (provider, type) = found
        do {
            let copy = try await Self.copyToTemporary(provider, type: type)
            file = copy
            typeIdentifier = type
            name = provider.suggestedName.map { Self.withExtension($0, from: copy) } ?? copy.lastPathComponent
            bytes = (try? FileManager.default.attributesOfItem(atPath: copy.path)[.size] as? Int) ?? 0
            seconds = Self.seconds(of: copy)
            state = .ready
        } catch {
            state = .failed("The shared audio could not be read: \(error.localizedDescription)")
        }
    }

    /// Copies the file into the share inbox and tells the app. Nothing is kept unless this succeeds.
    func keep() {
        guard let file else { return }
        guard let inbox = ShareInbox.shared() else {
            state = .failed("This build of VoiceDebrief cannot receive shared files yet: its App Group is not set up. Nothing was kept.")
            return
        }
        do {
            try inbox.keep(fileAt: file, originalName: name, typeIdentifier: typeIdentifier, seconds: seconds)
            try? FileManager.default.removeItem(at: file)
            ShareInbox.announce()
            state = .kept
        } catch {
            state = .failed("The voice note could not be kept: \(error.localizedDescription)")
        }
    }

    func cancel() {
        if let file { try? FileManager.default.removeItem(at: file) }
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    func done() {
        context?.completeRequest(returningItems: nil)
    }

    // MARK: Finding and copying

    /// The first attachment that is audio, and the type to load it as. A file URL is the last resort, for
    /// apps that share a voice note only as a file.
    static func audioProvider(in context: NSExtensionContext?) -> (NSItemProvider, String)? {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers {
            for type in audioTypes where provider.hasItemConformingToTypeIdentifier(type) {
                // Load it as the most specific type it offers that conforms.
                let offered = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: UTType(type) ?? .audio) == true }
                return (provider, offered ?? type)
            }
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            return (provider, UTType.fileURL.identifier)
        }
        return nil
    }

    /// Copies the shared file into the extension's temporary folder: the URL handed over is valid only for a moment.
    nonisolated static func copyToTemporary(_ provider: NSItemProvider, type: String) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func copy(_ source: URL) throws -> URL {
            let target = folder.appending(path: ShareInbox.safeName(source.lastPathComponent))
            try FileManager.default.copyItem(at: source, to: target)
            return target
        }
        if type == UTType.fileURL.identifier {
            return try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    continuation.resume(with: Result { try copy(url) })
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                continuation.resume(with: Result { try copy(url) })
            }
        }
    }

    /// The suggested name with the copy's extension if it has none of its own ("Voice note" + ".opus").
    static func withExtension(_ name: String, from file: URL) -> String {
        guard (name as NSString).pathExtension.isEmpty, !file.pathExtension.isEmpty else { return name }
        return name + "." + file.pathExtension
    }

    /// The length in seconds: from the Ogg pages for an Opus voice note, otherwise from `AVAudioFile`.
    static func seconds(of file: URL) -> Double? {
        if OggOpus.looksLikeOgg(fileAt: file) {
            guard let data = try? Data(contentsOf: file), let stream = try? OggOpus.parse(data) else { return nil }
            return stream.seconds
        }
        guard let audio = try? AVAudioFile(forReading: file), audio.processingFormat.sampleRate > 0 else { return nil }
        return Double(audio.length) / audio.processingFormat.sampleRate
    }
}
