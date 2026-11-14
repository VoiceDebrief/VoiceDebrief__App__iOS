import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// A QR code for a card, a sealed message or a link. Correction level L: a card is about 1,200 characters, and
/// L keeps its code small enough to scan from a screen.
public enum PeopleQR {
    public static func image(_ text: String, scale: CGFloat = 8) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
