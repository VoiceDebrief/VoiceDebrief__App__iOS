# The secrets manager: the field and the opportunity

A research brief written for the [secrets manager design](../index.md) on 14 November 2026, by a research agent working from public sources. **Treat prices as approximate** (most come from aggregator sites that disagree), and anything marked *(judgement)* as opinion. It is input to the design, not a decision: the owner decides, through the questions in the app and on the design page.

Date: 14 November 2026. Prices move often and many figures below come from aggregators; check vendor pages before quoting them. Anything marked *(judgement)* is my opinion, not a sourced fact.

## 1. The field, 2025 to 2026

| Product | Sync | Sharing | Trust and identity | Passkeys | Pricing shape | Strength | Weakness |
|---|---|---|---|---|---|---|---|
| 1Password | Vendor cloud | Shared vaults, organisation accounts | Vendor account plus Secret Key; the vendor directory supplies members' public keys | Yes; exports through Credential Exchange on iOS | Personal, Families, Teams, Business seats | Polish, Secret Key design | Subscription only, cloud only |
| Bitwarden | Vendor cloud or self-hosted | Organisations and collections; a free organisation holds 2 people | Vendor account; the server supplies members' keys | Yes; early adopter of iOS 26 export | Free, Premium, Families (6 people, about $3.99 a month), Teams and Enterprise per seat | Open source, cheap | Several malicious-server attacks found in 2026 |
| Apple Passwords | iCloud Keychain | Shared Groups; owner adds members; an item lives in one group | Apple Account | Native | Free | Built in, zero setup | Apple-only; no permissions; people removed may keep what they saw |
| Proton Pass | Vendor cloud | Shared vaults on paid plans | Proton account | Yes | Free, Plus, Family, Business | Privacy brand, low price | Younger product, fewer team controls |
| Keeper | Vendor cloud | Shared folders with permissions | Vendor account | Yes | Limited free tier, Family about $3.83 a month, Business | Enterprise compliance | Upselling, add-on pricing |
| Dashlane | Vendor cloud | Sharing and groups | Vendor account | Yes | Mostly paid; sources disagree on whether a free tier remains | Clean business admin | Malicious-server findings, price |
| KeePassXC / Strongbox | A file; you choose the sync (Dropbox, iCloud, WebDAV) | Share the file and its password | None: whoever holds the file and password | Strongbox yes; KeePassXC has some | Free / freemium or lifetime | No vendor, open format | Sharing and merge conflicts left to the user |
| Doppler | SaaS | Projects and environments | Org SSO | n/a | Free tier, then per seat | Developer experience | Proprietary, SaaS only |
| Infisical | SaaS or self-hosted | Projects, machine identities | Org accounts, machine identities | n/a | MIT core, Pro priced by identity | Open core, self-host | Org-first, needs an admin |
| HashiCorp Vault | Self-hosted or HCP | Policies | Auth backends, tokens | n/a | BSL 1.1 since 2023; OpenBao is the MPL fork | Power, dynamic secrets | Heavy to run, licence worry |
| 1Password Secrets Automation | Vendor cloud | Service accounts, Connect server | 1Password org | n/a | Part of business plans | Same store for people and machines | Tied to a 1Password business account |

Common thread: all but KeePass rely on an **account with a company** for identity, and "end-to-end" sharing means the vendor's server hands you the other person's public key, the weakness the 2026 ETH Zurich study used. *(judgement)*

Sources: [Bitwarden pricing summary](https://www.activepieces.com/blog/bitwarden-pricing-plans-free-vs-paid-2026-guide), [Apple Shared Groups guide](https://support.apple.com/guide/passwords/mchlc00a3602), [Keeper pricing](https://password-manager.cybernews.com/keeper-password-manager-review/keeper-pricing/), [Infisical on pricing](https://infisical.com/blog/secrets-manager-pricing), [Vault licensing](https://guptadeepak.com/tools/alternatives-to-hashicorp-vault/), [Bitwarden on passkey portability](https://bitwarden.com/blog/security-vendors-join-forces-to-make-passkeys-more-portable-for-everyone/).

## 2. Recurring pain points

- **Breaches have a long tail.** Vaults stolen from LastPass in 2022 were still being cracked in 2025; TRM Labs traced about $35m in crypto thefts to them, and the UK ICO fined LastPass £1.2m. URLs were stored unencrypted, which told attackers which vaults were worth cracking. ([The Hacker News](https://thehackernews.com/2025/12/lastpass-2022-breach-led-to-years-long.html), [Infosecurity](https://www.infosecurity-magazine.com/news/experts-trace-35m-stolen-crypto/))
- **"Zero knowledge" is only as good as the server's honesty.** ETH Zurich and USI showed 25 or more attacks against Bitwarden, LastPass and Dashlane under a malicious server, grouped under recovery, key escrow, **sharing** and legacy crypto. ([IACR ePrint 2026/058](https://eprint.iacr.org/2026/058), [The Hacker News](https://thehackernews.com/2026/02/study-uncovers-25-password-recovery.html))
- **Family and small-team sharing.** Free tiers stop at two people (Bitwarden); Apple's groups have no roles beyond owner and member, and Apple warns that people you remove may keep what they saw. ([Apple](https://support.apple.com/guide/passwords/mchlc00a3602), [TWiT](https://twit.tv/posts/tech/apples-passwords-app-enough))
- **Lock-in and passkey portability.** Passkeys were stuck in one manager until FIDO's Credential Exchange. Apple shipped it in iOS 26, but CXF is a standard while the CXP transport was still a draft in mid 2026, and desktop support is patchy. ([Corbado](https://www.corbado.com/blog/ios-26-passkeys.md), [analysis](https://www.youngju.dev/transcribe/2026-07-16-passkey-credential-exchange-half-shipped.en))
- **Trust networks fail open.** The 2019 SKS attack flooded two people's PGP certificates with about 150,000 signatures because anyone could sign anyone. ([Hansen](https://gist.github.com/rjhansen/67ab921ffb4084c865b3618d6955275f))
- **Developers and agents.** GitGuardian counted about 28.65 million new secrets in public GitHub commits in 2025, AI-service secrets up 81%, and over 24,000 in MCP config files; more than 60% of secrets found in 2022 still worked in 2025. ([Help Net Security](https://www.helpnetsecurity.com/2026/04/14/gitguardian-ai-agents-credentials-leak/), [GitGuardian](https://blog.gitguardian.com/ai-secrets-spread-fast/))
- **Onboarding and recovery** are where people give up and where security weakens; recovery is the ETH paper's first category. *(judgement)*

## 3. Ten things SGit Vaults could do better

Ranked by value to a team of 5 to 20, weighted by how directly the architecture gives it. *(judgement)*

1. **A team with no admin and no company account.** *Value:* five people are sharing within ten minutes, with no sign-up, invoice or IT person. *Why possible:* identity is a key pair and membership is a confirmed link, not a row in a vendor database. *Risk:* nobody is in charge when someone leaves or loses a phone.
2. **Sharing that a dishonest server cannot redirect.** *Value:* you know the key you seal to belongs to the person you met. *Why possible:* keys come from cards confirmed in person, never from the server, which shuts out the key-substitution sharing attacks in the ETH study. *Risk:* people skip the confirmation step if it feels like work.
3. **Secrets for agents, scoped and visible.** *Value:* hand an AI session one API key for one job, not a `.env` file. *Why possible:* agents have keys and append lanes, so a secret is a sealed message to that agent alone. *Risk:* an agent that leaks it still leaks it; you need expiry and rotation reminders.
4. **Signed history of every change.** *Value:* "who changed the router password, and when?" has an answer, and you can roll back. *Why possible:* signed commits are the storage model, not an audit add-on. *Risk:* history also keeps old secrets, so rotation must be explained clearly.
5. **No lock-in.** *Value:* leave, self-host or keep several remotes without asking anyone. *Why possible:* local first, server holds only ciphertext, open format. *Risk:* "where is my data?" becomes a question users must understand.
6. **Ask for a secret from someone outside the team.** *Value:* a contractor drops the Wi-Fi or AWS key into your inbox; no shared document, no chat log. *Why possible:* the append lane is write-only, so the sender gets no read access. *Risk:* spam and floods, so lanes need limits and easy rotation; the sender still needs something that can seal (the app or a small web page), which must be built.
7. **Rotation on a branch.** *Value:* change a production key, test it, then merge, so the team is never half on old and half on new. *Why possible:* branches and merges are native. *Risk:* too developer-flavoured for families; hide it there.
8. **Recovery through people you trust.** *Value:* lose every device and get back in with help from three of five confirmed contacts, no vendor reset. *Why possible:* confirmed contacts and sealed messages already exist; key shares are just more sealed messages. *Risk:* hard to get right; a mistake here undoes the whole security story.
9. **A breach of the server reveals almost nothing.** *Value:* no LastPass-style list of which sites you use. *Why possible:* objects are encrypted, including names and URLs. *Risk:* sizes, timing and who talks to whom still leak; say so plainly.
10. **On-device help.** *Value:* sort an import, spot a key pasted into a note, explain a change in plain words, with nothing sent to a cloud. *Why possible:* Apple's on-device models only. *Risk:* small models make mistakes; keep them suggesting, never deciding.

Honest limit: removing a member means new vault keys *and* changing the secrets they saw.

## 4. iOS platform facts that constrain it

- **AutoFill Credential Provider extension.** Subclass `ASCredentialProviderViewController` in an extension and add the `com.apple.developer.authentication-services.autofill-credential-provider` entitlement to **both** the extension and the app ([Apple](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller)). Declare capabilities in the extension's Info.plist under `NSExtension > NSExtensionAttributes > ASCredentialProviderExtensionCapabilities`: `ProvidesPasswords`, `ProvidesPasskeys`, and optionally `ProvidesOneTimeCodes` and `ProvidesTextToInsert` ([Apple forums](https://developer.apple.com/forums/thread/745587)).
- **Passkeys in a third-party provider (iOS 17+).** `prepareCredentialList(for:requestParameters:)` for sign-in, `prepareInterface(forPasskeyRegistration:)` for creating a passkey, and `ASPasskeyCredentialIdentity` in `ASCredentialIdentityStore` for QuickType suggestions. Early iOS 17 had bugs, fixed by 17.4 ([Apple](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller/prepareinterface(forpasskeyregistration:)), [forum](https://developer.apple.com/forums/thread/747286)). The provider stores the passkey's private key itself.
- **iOS 18 and later** add one-time codes (`prepareOneTimeCodeCredentialList`), text insertion, and conditional (automatic) passkey upgrade (`performWithoutUserInteractionIfPossible(passkeyRegistration:)`). The latest SDK also adds save and generate password requests and the `report...` signals from sites. **iOS 26** adds Credential Exchange import and export (`ASCredentialExportManager`) ([Apple](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller), [Corbado](https://www.corbado.com/blog/wwdc25-passkeys-os26.md)).
- **Face ID.** `LocalAuthentication` (`LAContext`) or a keychain item protected by `SecAccessControl` with a biometry flag; the app must set `NSFaceIDUsageDescription`.
- **Secure Enclave.** It holds P-256 keys only and they never leave the device. The signing key could live there per device; RSA-4096 cannot, so it must be wrapped by an enclave key or stored as an ordinary keychain item. *(design consequence, my judgement)*
- **iCloud Keychain sync.** `kSecAttrSynchronizable` items cannot use any `...ThisDeviceOnly` accessibility value or `kSecAttrAccess` ([Apple](https://developer.apple.com/documentation/security/ksecattrsynchronizable), [Apple](https://developer.apple.com/documentation/security/ksecattraccessible)). Syncing keys there makes Apple's account a recovery path.
- **App Groups and keychain sharing.** The extension runs in its own process, so vault files go in a shared App Group container and keys in a shared keychain access group (`keychain-access-groups`). The extension should read a small index, not a whole vault, as extensions get less memory. *(judgement)*
- **Needs the account holder (or an Admin) in the developer portal:** an App ID for the extension, the AutoFill Credential Provider capability on both App IDs, the App Group and keychain group registered, and new provisioning profiles. A Mac build needs the same on the macOS side.

## 5. First-run and team storyboard

**One person alone**
1. Welcome: "Your secrets, in vaults only you can open." One button.
2. Face ID consent; keys generated on the device (show it happening, a few seconds).
3. Your card: name and a photo you take now. Explain that the photo helps friends know it is you.
4. First vault created locally; offer to import (Apple Passwords, 1Password, Bitwarden, CSV, Credential Exchange on iOS 26).
5. Turn on AutoFill: `ASSettingsHelper` opens the right Settings page.
6. Optional: add a remote server. Optional: recovery later, when you have contacts.

**Two people meeting**

7. "Add someone": both open a QR screen. A scans B.
8. A sees B's card with **B's photo**, takes a quick photo of the person in front of them, and compares. "Is this the person in front of you?"
9. Both phones show the same short safety code (six words or digits). Both say it aloud and tap Confirm. A link exists only when **both** confirm.
10. Remote fallback: card sent over a messenger, confirmed by video call with the same code. Mark it "confirmed remotely".

**A group of five**

11. One person starts "New team" and shows one QR; others scan it and each card appears in a grid with photos.
12. Each pair that has not confirmed yet gets a tick to do; the app shows who is still unconfirmed. A shared vault can include only people the creator has confirmed. *(judgement: do not let trust pass through others)*
13. Name the team vault, pick members, done; each member's copy of the key is sealed to their key.
14. Offer recovery: "Choose three of these four to help you get back in."

## 6. Decisions for the product owner

1. **Is iCloud Keychain allowed to hold keys?** Recommend: no for identity and vault keys by default; offer it as an opt-in recovery aid with a clear warning.
2. **How do people recover after losing every device?** Recommend: social recovery through confirmed contacts (threshold such as three of five), plus a printed recovery sheet. No vendor reset, ever.
3. **Must every team member confirm every other member?** Recommend: the vault creator must have confirmed each member; members need not confirm each other to read, but must to share onward.
4. **Is AutoFill (passwords and passkeys) in version one?** Recommend: yes for passwords and passkeys; it is the daily habit that keeps people in the app. Leave one-time codes and text insertion for later.
5. **What does removing a member do?** Recommend: re-key the vault automatically, then show a checklist of the secrets that person saw, with "rotate" actions. Never imply removal un-shares the past.
