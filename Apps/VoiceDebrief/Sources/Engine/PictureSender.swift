import Foundation
import Observation
import UIKit

/// Sends a picture (a screenshot pasted from the clipboard or chosen from Photos) with a line of text to
/// a recipient, over the same encrypted lane as a voice note (the owner, 14 November 2026: "I should be
/// able to send not just text, but screenshots like this, and paste from the clipboard"). Tried five
/// times, like a note, and at once when the network comes back.
@MainActor @Observable
final class PictureSender {
    enum State: Equatable {
        case idle
        case sending(Int, Int)
        case retrying(attempt: Int, of: Int, next: Date)
        case sent(Date)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// The picture as a JPEG no wider or taller than 2048 points' worth of pixels, small enough to go in
    /// one or two parts.
    nonisolated static func jpeg(_ image: UIImage, longestSide: CGFloat = 2048, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let scale = min(1, longestSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return drawn.jpegData(compressionQuality: quality)
    }

    func send(_ image: UIImage, caption: String, to recipient: Recipient) async {
        guard let lane = recipient.lane, let data = Self.jpeg(image) else {
            state = .failed("The picture could not be prepared"); return
        }
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let id = "picture-" + formatter.string(from: now)
        let messages: [Data]
        do {
            messages = try DeveloperLane.imageMessages(image: data, imageName: "screenshot.jpg", caption: caption,
                                                       id: id, app: AppInfo.versionLine(), at: now)
        } catch {
            state = .failed(error.localizedDescription); return
        }
        var attempt = 1
        while true {
            state = .sending(0, messages.count)
            do {
                try await lane.send(messages) { done, total in
                    Task { @MainActor [weak self] in self?.state = .sending(done, total) }
                }
                state = .sent(Date())
                UsageLog.shared.action("picture.sent")
                CreditLedger.shared.charge(.send, noteId: id)
                return
            } catch {
                guard let wait = SendRetry.wait(before: attempt + 1) else {
                    var why = error.localizedDescription
                    if why.hasSuffix(".") { why.removeLast() }
                    state = .failed("not sent after \(attempt) tries (\(why))")
                    UsageLog.shared.action("picture.gave-up")
                    return
                }
                let failedAt = Date()
                state = .retrying(attempt: attempt + 1, of: SendRetry.attempts, next: failedAt.addingTimeInterval(wait))
                let net = NetworkWatch.shared
                while Date() < failedAt.addingTimeInterval(wait) {
                    if let back = net.backOnlineAt, back > failedAt, net.online { break }
                    if tryNowAsked { tryNowAsked = false; break }
                    try? await Task.sleep(for: .seconds(1))
                }
                attempt += 1
            }
        }
    }

    private var tryNowAsked = false
    func tryNow() { tryNowAsked = true }
    func reset() { state = .idle }
}
