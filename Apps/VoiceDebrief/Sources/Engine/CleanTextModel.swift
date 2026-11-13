import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// The shape Apple's model fills in for one passage. Guided generation: the framework constrains
/// the model to this structure, so nothing has to be parsed out of prose.
@Generable(description: "A passage of a voice note rewritten clearly, and the phrases that could not be understood")
struct GeneratedPassage {
    @Guide(description: "The passage rewritten as clear sentences, with everything that was said kept")
    var clean: String

    @Guide(description: "Phrases that made no sense, at most three. Empty when everything was clear")
    var unclear: [GeneratedDoubt]
}

@Generable(description: "A phrase that could not be understood")
struct GeneratedDoubt {
    @Guide(description: "The exact words from the passage")
    var phrase: String

    @Guide(description: "One short question to ask the speaker")
    var question: String
}
#endif

extension OnDeviceModel {
    /// One passage through the model, as structure. A fresh session each time: no passage is in the
    /// context of the next.
    static func cleanPassage(prompt: String) async throws -> (clean: String, questions: [CleanQuestion]) {
        #if canImport(FoundationModels)
        if case .unavailable(let why) = status { throw ModelError.unavailable(why) }
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt, generating: GeneratedPassage.self)
            let made = response.content
            let questions = made.unclear.prefix(3).compactMap { doubt -> CleanQuestion? in
                let phrase = doubt.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                let question = doubt.question.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !phrase.isEmpty, !question.isEmpty else { return nil }
                return CleanQuestion(phrase: phrase, question: question, answer: nil)
            }
            return (made.clean.trimmingCharacters(in: .whitespacesAndNewlines), Array(questions))
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
