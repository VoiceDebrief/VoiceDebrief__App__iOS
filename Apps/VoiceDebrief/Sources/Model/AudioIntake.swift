import Foundation
import UniformTypeIdentifiers

/// The kinds of audio file the app takes in: from the Files sheet, and from the share sheet.
enum AudioIntake {
    /// WhatsApp's voice notes: Opus in Ogg, named `.opus` (or `.ogg` by some apps).
    static let opus: UTType = UTType(filenameExtension: "opus", conformingTo: .audio) ?? .audio
    static let ogg: UTType = UTType(filenameExtension: "ogg", conformingTo: .audio) ?? .audio

    /// What the Files sheet offers. `.audio` covers .m4a, .mp3 and .wav; the two Ogg types are named in case
    /// the system does not count them as audio.
    static var importableTypes: [UTType] {
        var types: [UTType] = [.audio]
        for type in [opus, ogg] where !types.contains(type) { types.append(type) }
        return types
    }
}
