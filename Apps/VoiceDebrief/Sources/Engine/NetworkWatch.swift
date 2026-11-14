import Foundation
import Network
import Observation

/// Whether this device can reach the network, from the system's own path monitor (no polling). A send
/// that failed while driving through poor signal waits for the next try, or for this to say the network
/// is back, whichever comes first (the owner, 14 November 2026: "see if you can get notifications from
/// iOS to tell you that you're back online").
@MainActor @Observable
final class NetworkWatch {
    static let shared = NetworkWatch()

    private(set) var online = true
    /// When the network last came back after being away; nil if it has not been away since launch.
    private(set) var backOnlineAt: Date?
    /// Called each time the network comes back.
    var onBackOnline: [() -> Void] = []

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor [weak self] in self?.update(up) }
        }
        monitor.start(queue: DispatchQueue(label: "ai.voicedebrief.network"))
    }

    private func update(_ up: Bool) {
        let wasOnline = online
        online = up
        if up && !wasOnline {
            backOnlineAt = Date()
            onBackOnline.forEach { $0() }
        }
    }
}

/// When to try a send again: the first try, then four more, further apart each time (10 s, 30 s, 1 min,
/// 2 min), so a few minutes of no signal do not lose the send and a long outage does not drain the battery.
enum SendRetry {
    static let attempts = 5
    static let waits: [TimeInterval] = [10, 30, 60, 120]

    /// The wait before try `next` (2...attempts), or nil when there are no more tries.
    static func wait(before next: Int) -> TimeInterval? {
        let index = next - 2
        return waits.indices.contains(index) ? waits[index] : nil
    }
}
