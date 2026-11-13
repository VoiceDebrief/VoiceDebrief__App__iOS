import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// QR codes as a way to carry a link between devices: drawn here, read from a picture here. The
/// camera's reader is `QRScanner`.
enum QRCode {
    /// A QR code for the text, drawn with hard edges at eight pixels a module.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let rendered = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    /// The text of the first QR code found in a picture: a screenshot, a photo of a screen.
    static func read(imageData: Data) -> String? {
        guard let image = CIImage(data: imageData),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
