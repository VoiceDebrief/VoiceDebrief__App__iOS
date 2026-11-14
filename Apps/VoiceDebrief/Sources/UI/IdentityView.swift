import AuthenticationServices
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Who you are, which device this is, and what links the two. Built to show where each key lives.
struct IdentityView: View {
    let vaults: VaultBook
    var book: IdentityBook = .shared
    @State private var label = ""
    @State private var pasted = ""
    @State private var confirmForget = false
    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        List {
            userSection
            SectionBannerRow(tab: .identity)
            deviceSection
            vouchingSection
            registerSection
            if let busy = book.busy {
                Section { HStack(spacing: 12) { ProgressView(); Text(busy) } }
            }
            if let problem = book.problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
            if let notice = book.notice {
                Section { Text(notice) }
            }
        }
        .readableWidth()
        .navigationTitle("Identity")
        .task {
            book.refresh()
            book.makeDeviceKey()
        }
        .onOpenURL { url in handle(returned: url) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handle(returned: url) }
        }
    }

    // MARK: You

    @ViewBuilder private var userSection: some View {
        if let user = book.user {
            Section {
                LabeledContent("Name on the key", value: user.label)
                IdentityFingerprintRow(title: "Signing key", fingerprint: user.signingFingerprint)
                IdentityFingerprintRow(title: "Encryption key", fingerprint: user.fingerprint)
                if let created = book.userCreated {
                    LabeledContent("Made", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Private halves", value: "iCloud Keychain")
                NavigationLink("Show my public key") { IdentityKeyCodeView(bundle: user) }
                Button("Remove this identity from all my devices", role: .destructive) { confirmForget = true }
                    .confirmationDialog("Remove your key pair from iCloud Keychain? It goes from every device it reached, and cannot be brought back. What it signed can still be checked by anyone who kept its public half.",
                                        isPresented: $confirmForget, titleVisibility: .visible) {
                        Button("Remove it", role: .destructive) { book.forgetUser() }
                    }
            } header: {
                Text("You")
            } footer: {
                Text("One key pair that says who you are: RSA 4096 to receive, ECDSA P-256 to sign, the same bundle sgit makes. Its private halves are kept in iCloud Keychain, so they reach your other devices signed in to the same Apple account, encrypted so that Apple cannot read them. Two fingerprints are the same person only if they match character for character.")
            }
        } else {
            Section {
                TextField("A name for the key (yours)", text: $label)
                    .autocorrectionDisabled()
                Button("Make my identity") { Task { await book.createUser(label: label) } }
                    .disabled(book.busy != nil)
                Button("Look again") { book.refresh() }
            } header: {
                Text("You")
            } footer: {
                Text("There is no identity on this device yet. If you made one on another device signed in to the same Apple account, do not make a second: wait for iCloud Keychain to bring it (it can take a few minutes) and look again. Making one here creates a key pair and keeps it in iCloud Keychain.")
            }
        }
    }

    // MARK: This device

    private var deviceSection: some View {
        Section {
            if let device = book.device {
                IdentityFingerprintRow(title: "Device key", fingerprint: device.fingerprint)
                LabeledContent("Key id", value: device.keyId)
                LabeledContent("Made", value: device.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(device.keptInWords).font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Make this device's key") { book.makeDeviceKey() }
            }
        } header: {
            Text("This device")
        } footer: {
            Text("A second key pair that says which device, or which install of the app, did something. It never leaves this device and is not in iCloud. Deleting the app ends it: a new install makes a new one.")
        }
    }

    // MARK: Vouching

    private var vouchingSection: some View {
        Section {
            if vaults.vaults.isEmpty {
                Text("No vaults on this device yet.").foregroundStyle(.secondary)
            }
            ForEach(vaults.vaults) { vault in
                IdentityVouchRow(vault: vault, vaults: vaults, book: book)
            }
        } header: {
            Text("Vouching for this device")
        } footer: {
            Text("A short statement kept in a vault, signed by your key, saying this device's key is yours, from today, for signing commits. A reader then checks two things: the device signed, and you vouched for the device.")
        }
    }

    // MARK: The register

    private var registerSection: some View {
        Section {
            if book.connection != nil {
                switch Result(catching: { try book.checkedConnection() }) {
                case .success(let checked?):
                    Text(PKIDelegation.summary(checked))
                    IdentityFingerprintRow(title: checked.issuerName.isEmpty ? "Issuer" : checked.issuerName, fingerprint: checked.issuer)
                    LabeledContent("For", value: checked.can.joined(separator: ", "))
                    LabeledContent("From", value: checked.from)
                    LabeledContent("Until", value: checked.until)
                case .success(nil):
                    EmptyView()
                case .failure(let error):
                    Text("The delegation this app holds no longer checks: \(error.localizedDescription)").foregroundStyle(.red)
                }
                Button("Forget this connection", role: .destructive) { book.forgetConnection() }
            } else if book.user == nil {
                Text("Make your identity first.").foregroundStyle(.secondary)
            } else {
                if PKIDelegation.returnsToTheApp {
                    Button("Connect with pki.sgit.ai") { Task { await connectInApp() } }
                }
                Button(PKIDelegation.returnsToTheApp ? "Open pki.sgit.ai in the browser instead" : "Open pki.sgit.ai to connect") { connectInBrowser() }
                if book.hasPendingRequest {
                    TextField("Paste the address you were sent back to", text: $pasted, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use the pasted answer") {
                        let text = pasted
                        pasted = ""
                        Task { await book.finishConnection(text) }
                    }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } header: {
            Text("A person in the register (optional)")
        } footer: {
            Text("The app works without this. If you have an identity at pki.sgit.ai, you can sign in there with your passkey and have it vouch for this device's key, until a date. Nothing passes through a server: the request and the answer travel in the address. To check the answer, the app fetches the issuer's public key from pki.sgit.ai. The register's root this app trusts is \(PKIDelegation.pinnedRoot), fixed in the app.")
        }
    }

    private func connectInApp() async {
        do {
            let url = try book.beginConnection()
            guard let back = URL(string: PKIDelegation.returnAddress), let host = back.host() else { return }
            let returned = try await webAuthenticationSession.authenticate(using: url, callback: .https(host: host, path: back.path()),
                                                                           additionalHeaderFields: [:])
            await book.finishConnection(returned.absoluteString)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed by the person. The request stays, so an answer pasted in is still accepted.
        } catch {
            book.report("pki.sgit.ai could not be opened inside the app (\(error.localizedDescription)). Open it in the browser instead, and paste the address you are sent back to.")
        }
    }

    private func connectInBrowser() {
        guard let url = try? book.beginConnection() else { return }
        openURL(url)
    }

    private func handle(returned url: URL) {
        guard url.absoluteString.hasPrefix(PKIDelegation.returnAddress) else { return }
        Task { await book.finishConnection(url.absoluteString) }
    }
}

/// A fingerprint, selectable, in a fixed-width face so two can be compared.
struct IdentityFingerprintRow: View {
    let title: String
    let fingerprint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(fingerprint).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

/// The public half, to show or send: a QR code, the k1 code as text, and the bundle `sgit pki import` reads.
struct IdentityKeyCodeView: View {
    let bundle: PKIBundle

    var body: some View {
        let code = (try? PKI.keyCode(bundle)) ?? ""
        List {
            Section {
                if let image = IdentityQRCode.image(for: "https://pki.sgit.ai/send/#" + code) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Your public key as a QR code")
                }
            } footer: {
                Text("Your public key as a link to pki.sgit.ai's page for sending you something only you can read. It is not secret. It does not prove the key is yours: the fingerprints, compared in person or on a channel already known, do that.")
            }
            Section("Key code") {
                Text(code).font(.caption2.monospaced()).textSelection(.enabled)
                Button("Copy the key code") { UIPasteboard.general.string = code }
            }
            Section {
                ShareLink(item: bundle.json) { Label("Share the public bundle", systemImage: "square.and.arrow.up") }
            } footer: {
                Text("The JSON file that `sgit pki import` reads.")
            }
        }
        .readableWidth()
        .navigationTitle("My public key")
    }
}

enum IdentityQRCode {
    /// A QR code of `text`, at the lowest error correction so that a key code of some 900 characters fits.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 4, y: 4)),
              let rendered = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}

/// One vault, and what it says about this device's key. Stands alone, so a vault's own screen can show it too.
struct IdentityVouchRow: View {
    let vault: SavedVault
    let vaults: VaultBook
    var book: IdentityBook = .shared
    @State private var state: Status = .unknown
    @State private var working = false

    enum Status: Equatable {
        case unknown
        case none
        case vouched(by: String, name: String, from: String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vault.name)
            Group {
                switch state {
                case .unknown: Text("Not looked at yet.")
                case .none: Text("Holds no statement for this device.")
                case .vouched(let by, let name, let from): Text("This device is vouched for by \(by)\(name.isEmpty ? "" : " (\(name))"), from \(from).")
                case .failed(let why): Text(why).foregroundStyle(.red)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack {
                Button("Look") { Task { await look() } }
                if vault.canWrite, book.user != nil, state != .unknown, !isVouched {
                    Button("Vouch for this device here") { Task { await vouch() } }
                }
                if working { ProgressView() }
            }
            .buttonStyle(.borderless)
            .disabled(working)
        }
    }

    private var isVouched: Bool {
        if case .vouched = state { return true }
        return false
    }

    private func look() async {
        working = true
        defer { working = false }
        do {
            let device = try book.deviceSigner()
            if let checked = try await IdentityVaultAccess.statement(forDevice: device.fingerprint, in: vault, book: vaults) {
                state = .vouched(by: checked.user.signingFingerprint, name: checked.user.label, from: checked.from)
            } else {
                state = .none
            }
        } catch {
            state = .failed(VaultBook.describe(error))
        }
    }

    private func vouch() async {
        working = true
        defer { working = false }
        do {
            let device = try book.deviceSigner()
            let files = try book.vouchFiles()
            _ = try await IdentityVaultAccess.write(files, message: "Vouch for device key \(device.fingerprint)", to: vault, book: vaults, signer: device)
        } catch {
            state = .failed(VaultBook.describe(error))
            return
        }
        await look()
    }
}
