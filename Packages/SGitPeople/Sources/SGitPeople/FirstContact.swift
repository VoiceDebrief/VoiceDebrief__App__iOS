import Foundation
import SGitVault

/// The first exchange between someone who has the server's access key (the inviter) and someone who does not
/// yet (the newcomer). The newcomer has keys from the first launch but no inbox, because making one needs the
/// access key. Section 5 of the article "People, messages and secrets":
///
///   1. The newcomer shows their card: name and public keys, no inbox (`ContactCard.make(… inbox: nil)`).
///   2. The inviter adds it, and seals the access key to it, signed, with the inviter's own card inside:
///      `invitation(…)`, a `sgm1.` text for a QR code or a WhatsApp message. Only the newcomer's key opens it.
///   3. The newcomer opens it (`open(…)`), keeps the access key, adds the inviter, makes an inbox on a new vault
///      of their own, and sends their full card to the inviter's inbox: `accept(…)` does all of that.
///   4. The inviter's next inbox check finds the card, signed by the key they already hold, and the contact
///      gains an inbox (`ContactBook.absorbCard`). From then on either can write to the other.
public enum FirstContact {
    public enum Failure: Error, Equatable, LocalizedError {
        case notAnInvitation
        case noAccessKey
        case inviterHasNoInbox

        public var errorDescription: String? {
            switch self {
            case .notAnInvitation: "This is not an invitation."
            case .noAccessKey: "The invitation does not carry an access key."
            case .inviterHasNoInbox: "Whoever invited you has no inbox to reply to."
            }
        }
    }

    /// Step 2, the inviter: the access key sealed to the newcomer's card, as `sgm1.` text.
    ///
    /// With `myCard` it is about 4,000 characters: a link or a WhatsApp message. In person, when the newcomer has
    /// already scanned the inviter's card, pass nil: about half that, which a QR code can hold.
    public static func invitation(accessKey: SharedSecret, to newcomer: ContactCard, from me: PKIIdentity, myCard: ContactCard?,
                                  note: String? = nil, at date: Date = Date()) throws -> String {
        try newcomer.check()
        let message = PeopleMessage(kind: .secret, from: me.bundle.signingFingerprint, to: newcomer.fingerprint, sentAt: date,
                                    card: try myCard?.text(), text: note, secret: accessKey)
        return try message.sealedText(to: newcomer.bundle, from: me)
    }

    /// What the newcomer finds in an invitation.
    public struct Invitation: Equatable, Sendable {
        public var opened: OpenedMessage
        public var accessKey: SharedSecret
        /// The inviter's card: the one inside, checked and signed by the same key as the invitation, or the
        /// contact whose key signed it.
        public var inviter: ContactCard?
    }

    /// Step 3, the newcomer: opens the `sgm1.` text with their own key.
    public static func open(_ text: String, me: PKIIdentity, contacts: [PKIBundle] = []) throws -> Invitation {
        guard let envelope = SealedText.envelope(in: text) else { throw Failure.notAnInvitation }
        let opened = try PeopleMessage.open(envelope: envelope, me: me, contacts: contacts)
        guard opened.message.kind == .secret, let secret = opened.message.secret else { throw Failure.notAnInvitation }
        guard secret.kind == .accessKey else { throw Failure.noAccessKey }
        var inviter: ContactCard?
        if (opened.trust == .cardInside || opened.trust == .contact), let card = opened.card, card.signingFingerprint == opened.signer {
            inviter = card
        }
        return Invitation(opened: opened, accessKey: secret, inviter: inviter)
    }

    /// The message that carries a card to someone's inbox.
    public static func cardMessage(_ myCard: ContactCard, to contact: ContactCard, from me: PKIIdentity,
                                   at date: Date = Date()) throws -> (address: InboxAddress, payload: String) {
        guard let address = contact.inbox else { throw Failure.inviterHasNoInbox }
        let message = PeopleMessage(kind: .card, from: me.bundle.signingFingerprint, to: contact.fingerprint, sentAt: date,
                                    card: try myCard.text())
        return (address, try message.lanePayload(to: contact.bundle, from: me))
    }

    /// Step 3 in full: keeps the access key, adds the inviter, makes the newcomer's inbox, keeps its keys, makes
    /// the full card and sends it to the inviter. Returns the new card. Each step that has happened stays done
    /// if a later one fails: run again, it does not make a second inbox.
    public static func accept(_ invitation: Invitation, name: String, me: PKIIdentity, secrets: SecretsStore, contacts: ContactBook,
                              maker: InboxMaker, client: LaneClient, signer: any VaultCommitSigner, how: HowMet,
                              at date: Date = Date()) async throws -> ContactCard {
        let known = invitation.opened.trust == .contact ? invitation.opened.signer.flatMap { contacts.contact(signingFingerprint: $0)?.card } : nil
        guard let inviter = invitation.inviter ?? known else { throw Failure.inviterHasNoInbox }
        let sender = SecretHolder(fingerprint: inviter.fingerprint, name: inviter.name, at: date, version: invitation.accessKey.version)
        try secrets.receive(invitation.accessKey, from: sender, at: date)
        try contacts.add(inviter, met: how, at: date, myFingerprint: me.bundle.fingerprint)
        let server = invitation.accessKey.server ?? InboxAddress.defaultServer
        let keys: InboxKeys
        if let kept = secrets.inbox {
            keys = kept
        } else {
            keys = try await maker.make(server: server, accessToken: invitation.accessKey.value, signer: signer)
            try secrets.saveInbox(keys)
        }
        let card = try ContactCard.make(name: name, identity: me, inbox: keys.address, at: date)
        let (address, payload) = try cardMessage(card, to: inviter, from: me, at: date)
        try await client.write(payload, to: address)
        contacts.recordCardSent(to: inviter.fingerprint, at: date)
        return card
    }
}

extension ContactBook {
    /// Takes the card in a received `card` message (or any message carrying one) when it is signed by the
    /// key it names: an update for a contact (a new inbox, a new name), or a new contact met through the inbox.
    @discardableResult
    public func absorbCard(from received: ReceivedMessage, myFingerprint: String? = nil, at date: Date = Date()) -> Added? {
        guard let message = received.message, let text = message.card, let signer = received.signer,
              received.trust == .contact || received.trust == .cardInside,
              let card = try? ContactCard.parse(text), card.signingFingerprint == signer else { return nil }
        return try? add(card, met: .throughInbox, at: date, myFingerprint: myFingerprint)
    }
}
