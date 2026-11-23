import Foundation
import UIKit

/// Photos sent with a request to a site's keeper, prepared as the site's own page prepares them (send.js: at most
/// 1600 px on the long side, JPEG at 0.85, as a data URL; at most 4 per request). A lane message must stay under the
/// server's limit (sealing and encoding make it about 1.8 times larger, and the server refuses a payload over 5 MB),
/// so the pictures of one request are kept under `budget` bytes together, by lowering the quality if they must.
enum SitePhotos {
    static let longSide: CGFloat = 1600
    static let quality: CGFloat = 0.85
    static let most = 4
    static let budget = 2_000_000

    /// One picture, scaled and compressed: nil if the bytes are not a picture.
    static func jpeg(_ data: Data, quality: CGFloat = quality) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, longSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// The pictures of one request, in the site's format, within the budget.
    static func images(from pictures: [Data]) -> [SitePersonKey.Image] {
        let chosen = Array(pictures.prefix(most))
        for q in [quality, 0.7, 0.55, 0.4] {
            let jpegs = chosen.compactMap { jpeg($0, quality: q) }
            if jpegs.reduce(0, { $0 + $1.count }) <= budget || q == 0.4 {
                return jpegs.enumerated().map { index, jpeg in
                    SitePersonKey.Image(name: "photo-\(index + 1).jpg", type: "image/jpeg",
                                        data: "data:image/jpeg;base64," + jpeg.base64EncodedString())
                }
            }
        }
        return []
    }
}
