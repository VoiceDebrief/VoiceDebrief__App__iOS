import Foundation
import Observation

/// One step of vault work, for the debug panel. Never holds key material:
/// `path` is a server path or a vault file path, `detail` is a description of the step.
public struct VaultTrafficEvent: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable, Codable {
        case request, cacheHit, decrypt, verify, keyDerivation, error
    }

    public let id: UUID
    public let at: Date
    public let kind: Kind
    /// e.g. "bare/refs/ref-pid-muw-…" — never a key.
    public let path: String
    public let bytes: Int
    public let durationMs: Double
    public let status: Int?
    /// e.g. "AES-256-GCM, read key, 547 B → 512 B".
    public let detail: String
    /// The vault this event belongs to.
    public let vaultId: String

    public init(id: UUID = UUID(), at: Date = Date(), kind: Kind, path: String, bytes: Int = 0,
                durationMs: Double = 0, status: Int? = nil, detail: String = "", vaultId: String = "") {
        self.id = id
        self.at = at
        self.kind = kind
        self.path = path
        self.bytes = bytes
        self.durationMs = durationMs
        self.status = status
        self.detail = detail
        self.vaultId = vaultId
    }
}

/// Every request, cache hit, decryption, verification and key derivation the vault
/// client performs, newest first, capped at 2,000 events. Feeds the debug panel.
@MainActor @Observable public final class VaultTrafficLog {
    public static let capacity = 2_000

    public private(set) var events: [VaultTrafficEvent] = []
    /// Totals since launch (not capped).
    public private(set) var totals = Totals()

    public struct Totals: Sendable, Equatable {
        public var requests = 0
        public var bytesDownloaded = 0
        public var cacheHits = 0
        public var bytesFromCache = 0
        public var decrypts = 0
        public var verifications = 0
        public var errors = 0
        public var keyDerivations = 0
        public init() {}
    }

    public init() {}

    public func record(_ event: VaultTrafficEvent) {
        events.insert(event, at: 0)
        if events.count > Self.capacity { events.removeLast(events.count - Self.capacity) }
        switch event.kind {
        case .request:
            totals.requests += 1
            totals.bytesDownloaded += event.bytes
        case .cacheHit:
            totals.cacheHits += 1
            totals.bytesFromCache += event.bytes
        case .decrypt: totals.decrypts += 1
        case .verify: totals.verifications += 1
        case .keyDerivation: totals.keyDerivations += 1
        case .error: totals.errors += 1
        }
    }

    public func clear() {
        events.removeAll()
        totals = Totals()
    }

    /// Cache hits / (hits + requests), 0 when nothing happened yet.
    public var cacheHitRate: Double {
        let total = totals.cacheHits + totals.requests
        return total == 0 ? 0 : Double(totals.cacheHits) / Double(total)
    }
}

extension Int {
    /// "547 B", "12.3 KB", "4.1 MB".
    public var vaultByteString: String {
        if self < 1_000 { return "\(self) B" }
        if self < 1_000_000 { return String(format: "%.1f KB", Double(self) / 1_000) }
        return String(format: "%.1f MB", Double(self) / 1_000_000)
    }
}
