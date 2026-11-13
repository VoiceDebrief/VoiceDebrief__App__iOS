import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device language model can run here, in words a screen can show.
enum ModelStatus: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
    var text: String {
        switch self {
        case .available: return "Available"
        case .unavailable(let why): return why
        }
    }
}

enum ModelError: LocalizedError {
    case unavailable(String)
    case declined
    case tooLong
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return why
        case .declined: return "Apple's model declined to summarise this."
        case .tooLong: return "This was too long for Apple's on-device model in one request."
        case .failed(let why): return why
        }
    }
}

/// Apple's Foundation Models framework, on the device. One fresh session per request, so nothing
/// from one voice note is in the context of the next.
enum OnDeviceModel {
    static var status: ModelStatus {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable("This device does not support Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Apple Intelligence is switched off in Settings.")
            case .modelNotReady:
                return .unavailable("Apple's model is still downloading. Try again later.")
            @unknown default:
                return .unavailable("Apple's model is not available right now.")
            }
        }
        #else
        return .unavailable("This build has no Foundation Models SDK.")
        #endif
    }

    /// The model's context window in tokens, or nil when there is no model to ask.
    static var contextSize: Int? {
        #if canImport(FoundationModels)
        guard status.isAvailable else { return nil }
        return SystemLanguageModel.default.contextSize
        #else
        return nil
        #endif
    }

    /// The languages the model says it supports, as short identifiers, sorted.
    static var supportedLanguageIds: [String] {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.supportedLanguages.map { $0.minimalIdentifier }.sorted()
        #else
        return []
        #endif
    }

    static func supports(localeId: String) -> Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.supportsLocale(Locale(identifier: localeId))
        #else
        return false
        #endif
    }

    static func respond(to prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if case .unavailable(let why) = status { throw ModelError.unavailable(why) }
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                throw ModelError.declined
            case .exceededContextWindowSize:
                throw ModelError.tooLong
            default:
                throw ModelError.failed(error.localizedDescription)
            }
        }
        #else
        throw ModelError.unavailable("This build has no Foundation Models SDK.")
        #endif
    }
}
