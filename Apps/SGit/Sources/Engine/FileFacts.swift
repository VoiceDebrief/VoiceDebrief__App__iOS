import AVFoundation
import Foundation
import ImageIO
import QuickLookThumbnailing
import UIKit

/// What is kept beside every file added to a vault (the owner, 14 November 2026: thumbnails in the vault
/// so that "we don't want everybody to download massive things", and "from everything that gets loaded,
/// extract metadata"). Both live in a hidden folder, keyed by the file's content hash, so a renamed or
/// moved file keeps them and any client can find them:
///
///     .sgit/thumbs/<content hash>.jpg   a small picture: the image, a frame of the video, a page of a document
///     .sgit/meta/<content hash>.json    what could be read from the file, in the schema below
enum FileFacts {
    static let folder = ".sgit"
    static func thumbPath(_ contentHash: String) -> String { "\(folder)/thumbs/\(contentHash).jpg" }
    static func metaPath(_ contentHash: String) -> String { "\(folder)/meta/\(contentHash).json" }
    static let thumbPixels = 480

    /// Whether the person allows where a photo or video was taken to be kept in the vault. Off unless
    /// they turn it on: anyone with the vault's key would see it.
    static let keepLocationSetting = "files.keepLocation"
    static var keepLocation: Bool { UserDefaults.standard.bool(forKey: keepLocationSetting) }

    /// The small picture and the facts for one plain file, before it is encrypted.
    static func make(for url: URL, name: String, size: Int, contentHash: String, contentType: String,
                     keepLocation: Bool, at date: Date = Date()) async -> (thumb: Data?, meta: Data?) {
        let kind = VaultListing.kind(of: name)
        var meta = FileMeta(name: name, size: size, contentHash: contentHash, contentType: contentType,
                            kind: "\(kind)", addedAt: date)
        var thumb: Data?
        switch kind {
        case .image:
            thumb = await Task.detached(priority: .utility) { Thumbnail.jpeg(of: url, maxPixel: thumbPixels) }.value
            let read = await Task.detached(priority: .utility) { imageFacts(url, keepLocation: keepLocation) }.value
            meta.image = read.image
            meta.location = read.location
            meta.header = read.header
        case .video, .audio:
            if kind == .video { thumb = await Thumbnail.videoFrame(of: url, maxPixel: thumbPixels) }
            let read = await mediaFacts(url, keepLocation: keepLocation)
            meta.video = read.video
            meta.location = read.location
        case .document:
            thumb = await documentPicture(url)
        }
        return (thumb, try? meta.encoded())
    }

    /// A picture of the first page of a PDF or document, as the Files app would show it.
    static func documentPicture(_ url: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: thumbPixels, height: thumbPixels),
                                                   scale: 1, representationTypes: .thumbnail)
        guard let picture = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return picture.uiImage.jpegData(compressionQuality: 0.8)
    }

    static func imageFacts(_ url: URL, keepLocation: Bool) -> (image: FileMeta.Image?, location: FileMeta.Location?, header: [String: String]) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return (nil, nil, [:]) }
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        let image = FileMeta.Image(
            width: props[kCGImagePropertyPixelWidth as String] as? Int,
            height: props[kCGImagePropertyPixelHeight as String] as? Int,
            orientation: props[kCGImagePropertyOrientation as String] as? Int,
            taken: exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
            make: tiff[kCGImagePropertyTIFFMake as String] as? String,
            model: tiff[kCGImagePropertyTIFFModel as String] as? String,
            lens: exif[kCGImagePropertyExifLensModel as String] as? String,
            iso: (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first,
            exposureSeconds: exif[kCGImagePropertyExifExposureTime as String] as? Double,
            aperture: exif[kCGImagePropertyExifFNumber as String] as? Double,
            focalLength: exif[kCGImagePropertyExifFocalLength as String] as? Double)
        var location: FileMeta.Location?
        if keepLocation, var latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
           var longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef as String] as? String) == "S" { latitude = -latitude }
            if (gps[kCGImagePropertyGPSLongitudeRef as String] as? String) == "W" { longitude = -longitude }
            location = FileMeta.Location(latitude: latitude, longitude: longitude,
                                         altitude: gps[kCGImagePropertyGPSAltitude as String] as? Double)
        }
        return (image, location, header(props, keepLocation: keepLocation))
    }

    /// Every property the file's header carries, flattened to "{Exif}.ExposureTime" = "0.008", without
    /// the GPS block unless location is allowed, and without anything long.
    static func header(_ props: [String: Any], keepLocation: Bool) -> [String: String] {
        var out: [String: String] = [:]
        func walk(_ dict: [String: Any], _ prefix: String) {
            for (key, value) in dict {
                if key == (kCGImagePropertyGPSDictionary as String), !keepLocation { continue }
                if key == (kCGImagePropertyMakerAppleDictionary as String) { continue }
                let name = prefix.isEmpty ? key : prefix + "." + key
                if let inner = value as? [String: Any] { walk(inner, name); continue }
                let text = "\(value)".replacingOccurrences(of: "\n", with: " ")
                if text.count <= 200 { out[name] = text }
            }
        }
        walk(props, "")
        return out
    }

    static func mediaFacts(_ url: URL, keepLocation: Bool) async -> (video: FileMeta.Video?, location: FileMeta.Location?) {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
        var video = FileMeta.Video(durationSeconds: duration)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
                let shown = size.applying(transform)
                video.width = Int(abs(shown.width))
                video.height = Int(abs(shown.height))
            }
            video.frameRate = (try? await track.load(.nominalFrameRate)).map(Double.init)
            if let format = try? await track.load(.formatDescriptions).first {
                video.codec = fourCC(CMFormatDescriptionGetMediaSubType(format))
            }
        }
        var location: FileMeta.Location?
        if let items = try? await asset.load(.metadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                let value = try? await item.load(.stringValue)
                switch key {
                case .commonKeyCreationDate: video.taken = value
                case .commonKeyMake: video.make = value
                case .commonKeyModel: video.model = value
                case .commonKeyLocation where keepLocation:
                    if let value { location = FileMeta.Location(iso6709: value) }
                default: break
                }
            }
        }
        return (video, location)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
    }
}

/// The facts kept beside a file: `sgit.ai/file-meta/v1`. Every field but the first six may be absent.
struct FileMeta: Codable, Equatable, Sendable {
    static let format = "sgit.ai/file-meta/v1"

    struct Image: Codable, Equatable, Sendable {
        var width: Int?
        var height: Int?
        var orientation: Int?
        /// As the camera wrote it: "2026:11:14 13:05:22".
        var taken: String?
        var make: String?
        var model: String?
        var lens: String?
        var iso: Int?
        var exposureSeconds: Double?
        var aperture: Double?
        var focalLength: Double?
    }

    struct Video: Codable, Equatable, Sendable {
        var durationSeconds: Double?
        var width: Int?
        var height: Int?
        var frameRate: Double?
        /// The codec's four characters, such as "hvc1" or "avc1".
        var codec: String?
        var taken: String?
        var make: String?
        var model: String?
    }

    struct Location: Codable, Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var altitude: Double?

        init(latitude: Double, longitude: Double, altitude: Double? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
        }

        /// From "+38.7223-009.1393+045.000/", the form QuickTime keeps.
        init?(iso6709 text: String) {
            let numbers = text.matches(of: /[+-][0-9]+(\.[0-9]+)?/).compactMap { Double(String($0.output.0)) }
            guard numbers.count >= 2 else { return nil }
            self.init(latitude: numbers[0], longitude: numbers[1], altitude: numbers.count > 2 ? numbers[2] : nil)
        }
    }

    var format = FileMeta.format
    var name: String
    var size: Int
    var contentHash: String
    var contentType: String
    var kind: String
    var addedAt: Date
    var image: Image?
    var video: Video?
    var location: Location?
    var header: [String: String]?

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> FileMeta? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let meta = try? decoder.decode(FileMeta.self, from: data), meta.format == format else { return nil }
        return meta
    }

    /// The lines a file's screen shows.
    var lines: [(String, String)] {
        var out: [(String, String)] = []
        if let w = image?.width ?? video?.width, let h = image?.height ?? video?.height { out.append(("Dimensions", "\(w) × \(h)")) }
        if let seconds = video?.durationSeconds, seconds > 0 {
            let total = Int(seconds.rounded())
            out.append(("Length", total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
                                                : String(format: "%d:%02d", total / 60, total % 60)))
        }
        if let codec = video?.codec { out.append(("Codec", codec)) }
        if let taken = image?.taken ?? video?.taken { out.append(("Taken", taken)) }
        let camera = [image?.make ?? video?.make, image?.model ?? video?.model].compactMap { $0 }.joined(separator: " ")
        if !camera.isEmpty { out.append(("Camera", camera)) }
        if let lens = image?.lens { out.append(("Lens", lens)) }
        if let location { out.append(("Where", String(format: "%.4f, %.4f", location.latitude, location.longitude))) }
        return out
    }
}
