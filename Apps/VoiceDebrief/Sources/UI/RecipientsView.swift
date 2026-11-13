import PhotosUI
import SwiftUI
import VisionKit

/// Who a note can be sent to, and how to add somebody: scan their QR code, choose a picture of it,
/// or paste their link.
struct RecipientsView: View {
    private let recipients = RecipientStore.shared
    @State private var name = ""
    @State private var link = ""
    @State private var scanning = false
    @State private var picked: PhotosPickerItem?
    @State private var message = ""

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        Form {
            Section {
                ForEach(recipients.all) { recipient in
                    NavigationLink {
                        RecipientDetailView(recipient: recipient)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipient.name)
                            Text(recipients.isBuiltIn(recipient) ? "Built into this test build" : "Lane \(recipient.lane?.vault ?? "")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Recipients")
            } footer: {
                Text("A note sent to a recipient is encrypted on this device to their key. Nobody else can read it, including the server that carries it.")
            }

            Section {
                TextField("Name (optional)", text: $name)
                if canScan {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan their QR code", systemImage: "qrcode.viewfinder")
                    }
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label("Choose a picture of their QR code", systemImage: "photo")
                }
                TextField("Or paste their link (sgi1. ...)", text: $link, axis: .vertical)
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.footnote.monospaced())
                Button("Add from the pasted link") { take(link, from: "That text") }
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Add somebody")
            } footer: {
                Text("Ask them for their QR code or link. It holds where their inbox is, a token that can only write to it, and their public key. It cannot be used to read anything.")
            }
        }
        .navigationTitle("Recipients")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScanner { text in
                    scanning = false
                    take(text, from: "That QR code")
                }
                .ignoresSafeArea()
                .navigationTitle("Scan a QR code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } }
                }
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let text = data.flatMap { QRCode.read(imageData: $0) }
                picked = nil
                if let text {
                    take(text, from: "That QR code")
                } else {
                    message = "No QR code was found in that picture."
                }
            }
        }
    }

    private func take(_ text: String, from what: String) {
        if recipients.add(name: name.trimmingCharacters(in: .whitespacesAndNewlines), text: text) {
            message = "Added."
            CreditLedger.shared.charge(.addRecipient)
            name = ""
            link = ""
        } else if text.contains(DeveloperLane.builtInLink) {
            message = "That is the developer's lane, which this build already has."
        } else {
            message = "\(what) is not a lane link."
        }
    }
}

/// One recipient: where their lane is, the key notes are encrypted to, and their QR code, so that
/// they can be passed on to somebody else.
struct RecipientDetailView: View {
    let recipient: Recipient
    private let recipients = RecipientStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: recipient.name)
                if let lane = recipient.lane {
                    LabeledContent("Lane", value: lane.vault)
                    LabeledContent("Key", value: lane.fingerprint)
                }
            } footer: {
                Text("Check the key with them if it matters: it is what decides who can read what you send.")
            }
            Section {
                if let code = QRCode.image(for: RecipientLink.write(recipient)) {
                    Image(uiImage: code)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("QR code for this recipient's lane")
                }
                ShareLink("Share their link", item: RecipientLink.write(recipient))
            } header: {
                Text("Pass them on")
            } footer: {
                Text("Anybody with this code can send to \(recipient.name). Nobody can read with it.")
            }
            if !recipients.isBuiltIn(recipient) {
                Section {
                    Button("Remove", role: .destructive) {
                        recipients.remove(recipient)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(recipient.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The camera, looking for a QR code. Reports the first one it reads.
struct QRScanner: UIViewControllerRepresentable {
    let onRead: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRead: onRead) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRead: (String) -> Void
        private var done = false

        init(onRead: @escaping (String) -> Void) { self.onRead = onRead }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onRead(text)
                    return
                }
            }
        }
    }
}

/// On a note: one button per recipient.
struct SendSection: View {
    let noteId: String
    let session: DebriefSession
    private let recipients = RecipientStore.shared
    @State private var confirmingBuiltIn = false

    private var sending: Bool {
        if case .sending = session.sharing(for: noteId) { return true }
        return false
    }

    var body: some View {
        Section {
            switch session.sharing(for: noteId) {
            case .sending(let done, let total):
                HStack(spacing: 12) {
                    ProgressView()
                    Text(total > 0 ? "Sending part \(done) of \(total)" : "Encrypting")
                }
            case .sent(let count):
                Label("Sent, in \(count) encrypted messages", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            case .idle:
                EmptyView()
            }
            ForEach(recipients.all) { recipient in
                Button {
                    if recipients.isBuiltIn(recipient) {
                        confirmingBuiltIn = true
                    } else {
                        send(to: recipient)
                    }
                } label: {
                    Label("Send to \(recipient.name)", systemImage: "paperplane")
                }
                .disabled(sending || recipient.lane == nil)
            }
            NavigationLink {
                RecipientsView()
            } label: {
                Label("Add a recipient", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Send")
                .confirmationDialog("Send this note to the developer of this test build?",
                            isPresented: $confirmingBuiltIn,
                            titleVisibility: .visible) {
            Button("Send the audio, transcript and debrief") {
                if let recipient = recipients.builtIn { send(to: recipient) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is encrypted on this device to the key \(DeveloperLane.builtInFingerprint). The server that carries it cannot read it.")
        }
        } footer: {
            Text("The audio, transcript and debrief, encrypted on this device to the recipient's key. Nothing is sent until a button here is pressed.")
        }
    }

    private func send(to recipient: Recipient) {
        guard let lane = recipient.lane else { return }
        Task { await session.share(noteId: noteId, lane: lane) }
    }
}
