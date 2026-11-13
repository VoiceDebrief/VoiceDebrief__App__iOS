import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

/// A photo, a video or any file handed over by a picker, copied at once into a folder the app owns.
/// The copy is a file-to-file copy: the item is never loaded into memory.
struct PickedFile: Transferable, Sendable {
    let url: URL

    static func keep(_ received: URL) throws -> PickedFile {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "incoming", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: received.lastPathComponent)
        try FileManager.default.copyItem(at: received, to: target)
        return PickedFile(url: target)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { try keep($0.file) }
        FileRepresentation(importedContentType: .image) { try keep($0.file) }
        FileRepresentation(importedContentType: .data) { try keep($0.file) }
    }

    /// Copies a file chosen in the Files picker, which is only readable while its scope is open.
    static func keep(scoped url: URL) throws -> PickedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try keep(url)
    }
}

enum PhotoLibrary {
    struct Refused: LocalizedError {
        var errorDescription: String? { "sgit is not allowed to add to your photo library. Allow it in the Settings app." }
    }

    /// Adds an image or a video file to the photo library, asking for add-only access the first time.
    static func save(_ url: URL, isVideo: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Refused() }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
        }
    }
}

enum QRCode {
    /// A QR code for `text`, as an image to be shown without smoothing.
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

enum Clipboard {
    /// Copies a secret so that it stays on this device and leaves the clipboard after two minutes.
    static func copySecret(_ text: String) {
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
    }
}
