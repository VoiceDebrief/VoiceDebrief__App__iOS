import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads the text on a photo of a business card or a badge with Apple's Vision text recognition, on
/// the device: nothing leaves it. The lines go to `CardTextReader`.
enum CardPhotoReader {
    static func lines(in data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let raw = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
            // Top to bottom (Vision's origin is the bottom left), then left to right.
            let observations = (request.results ?? []).sorted {
                abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 ? $0.boundingBox.midY > $1.boundingBox.midY
                                                                      : $0.boundingBox.minX < $1.boundingBox.minX
            }
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}
