import Foundation
import Observation
import SGitPeople
import SGitVault

/// The people layer in the sgit app: the person's keys, contacts, inbox and secrets (Packages/SGitPeople).
/// Nothing is made at launch: the app opens and browses with no network and no prompts, and a person who only
/// looks at a vault never has an identity made for them. Keys are made when the person asks, on the You screen.
@MainActor
@Observable
final class PeopleModel {
    /// The identity and contacts' Keychain service; the secrets store has its own.
    static let peopleService = "ai.sgit.vaults.app.people"
    static let secretsService = "ai.sgit.vaults.app.secrets"

    private(set) var hub: PeopleHub?
    private(set) var making = false
    private(set) var problem: String?

    @ObservationIgnored private let peopleKeychain: any PeopleKeychain
    @ObservationIgnored private let secrets: SecretsStore
    @ObservationIgnored private let folder: URL?
    @ObservationIgnored private let client: LaneClient
    @ObservationIgnored private let nameKey = "people.name"

    init(peopleKeychain: any PeopleKeychain = LiveKeychain(service: PeopleModel.peopleService),
         secretsKeychain: any PeopleKeychain = LiveKeychain(service: PeopleModel.secretsService),
         folder: URL? = PeopleModel.defaultFolder, client: LaneClient = LaneClient()) {
        self.peopleKeychain = peopleKeychain
        self.secrets = SecretsStore(keychain: secretsKeychain)
        self.folder = folder
        self.client = client
        if let identity = PeopleIdentity.load(peopleKeychain) { open(identity) }
    }

    static var defaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("people")
    }

    var hasIdentity: Bool { hub != nil }
    var unreadCount: Int { hub?.unread ?? 0 }
    /// The identity's own keys, for the sgit app's Secrets screen (`KeysAndAccessView`).
    var keysAndAccess: [KeptSecret] { hub?.secretList ?? [] }

    var name: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: nameKey)
            hub?.rename(newValue)
        }
    }

    private func open(_ identity: PKIIdentity) {
        hub = PeopleHub(identity: identity, name: name.isEmpty ? identity.bundle.label : name, folder: folder,
                        secrets: secrets, client: client)
    }

    /// Makes the person's key pair (RSA 4096 to receive, P-256 to sign), kept in iCloud Keychain. Takes a second or more.
    func makeIdentity(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !making else { return }
        making = true
        defer { making = false }
        let keychain = peopleKeychain
        let made = await Task.detached(priority: .userInitiated) {
            Result { try PeopleIdentity.loadOrMake(keychain, label: trimmed) }
        }.value
        switch made {
        case .success(let identity):
            self.name = trimmed
            open(identity)
            problem = nil
        case .failure(let error):
            problem = error.localizedDescription
        }
    }

    #if DEBUG
    /// For the pictures: a hub made by `PeopleModel.sample`.
    func useSample(_ sample: PeopleHub) { hub = sample }
    #endif

    /// A new key for the inbox vault's first commit. The inbox vault holds only its lane; nothing else is committed to it.
    func commitSigner() -> any VaultCommitSigner { SoftwareCommitSigner() }
}
