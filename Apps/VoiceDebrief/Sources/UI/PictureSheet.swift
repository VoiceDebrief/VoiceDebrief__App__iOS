import PhotosUI
import SwiftUI
import UIKit

/// A picture on its way: the picture, a line to go with it, who it is for, and Send. Opened by "Paste
/// screenshot" or "Choose picture" on the record screen.
struct PictureSheet: View {
    let image: UIImage
    @State var recipient: Recipient
    @State private var caption = ""
    @State private var sender = PictureSender()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SendRoute(from: MyLook.shared.subject(id: "me"), to: [AvatarSubject(recipient: recipient)], size: 44)
                        .padding(.vertical, DS.Space.xxs)
                }
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                }
                Section("With it") {
                    TextField("A line about it (optional)", text: $caption, axis: .vertical)
                        .lineLimit(1...5)
                }
                Section("For") {
                    Picker("Send to", selection: $recipient) {
                        ForEach(RecipientStore.shared.all) { Text($0.name).tag($0) }
                    }
                }
                Section { status }
            }
            .navigationTitle("Send a picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await sender.send(image, caption: caption, to: recipient) } }
                        .keyboardShortcut(.return, modifiers: .command)   // Cmd+Return sends (the owner)
                        .disabled(busy)
                }
            }
            .onAppear { UsageLog.shared.action("picture.opened") }
            .onChange(of: sender.state) { _, state in
                if case .sent = state { Task { try? await Task.sleep(for: .seconds(2.5)); dismiss() } }
            }
        }
    }

    private var busy: Bool {
        switch sender.state {
        case .sending, .retrying, .sent: return true
        default: return false
        }
    }

    @ViewBuilder private var status: some View {
        switch sender.state {
        case .idle:
            Text("Encrypted to \(recipient.name)'s key and sent over their lane, like a voice note.")
                .font(.footnote).foregroundStyle(.secondary)
        case .sending(let done, let total):
            HStack { ProgressView(); Text("Sending, part \(done) of \(total)").font(.footnote) }
        case .retrying(let attempt, let of, let next):
            HStack {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(DS.Palette.amber)
                Text("No connection. Trying again \(Text(next, style: .relative)) (try \(attempt) of \(of))").font(.footnote)
                Spacer()
                Button("Try now") { sender.tryNow() }.font(.footnote)
            }
        case .sent(let at):
            Label("Sent to \(recipient.name) at \(at.formatted(date: .omitted, time: .shortened))", systemImage: Icon.done)
                .font(.headline).foregroundStyle(DS.Palette.green)
        case .failed(let why):
            VStack(alignment: .leading, spacing: 8) {
                Label("Not sent: \(why)", systemImage: Icon.failed).font(.footnote).foregroundStyle(DS.Palette.red)
                Button("Send again") { Task { await sender.send(image, caption: caption, to: recipient) } }
            }
        }
    }
}

/// "Paste screenshot" (from the clipboard) and "Choose picture" (from Photos), side by side.
struct PictureButtons: View {
    let recipient: Recipient?
    @State private var picked: PickedImage?
    @State private var nothingToPaste = false

    struct PickedImage: Identifiable { let id = UUID(); let image: UIImage }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let image = UIPasteboard.general.image {
                    picked = PickedImage(image: image)
                } else {
                    nothingToPaste = true
                }
            } label: {
                Label("Paste screenshot", systemImage: "doc.on.clipboard")
            }
            PhotoChooser { picked = PickedImage(image: $0) }
        }
        .buttonStyle(.bordered)
        .font(.footnote)
        .alert("There is no picture on the clipboard", isPresented: $nothingToPaste) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Take a screenshot, tap its preview, then Copy (or Share, Copy), and paste here.")
        }
        .sheet(item: $picked) { item in
            if let to = recipient ?? RecipientStore.shared.builtIn ?? RecipientStore.shared.all.first {
                PictureSheet(image: item.image, recipient: to)
            } else {
                Text("Add a contact first: a picture goes to someone.").padding()
            }
        }
    }
}

/// Choose a picture from Photos (a screenshot, usually).
struct PhotoChooser: View {
    let onPicked: (UIImage) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label("Choose picture", systemImage: "photo")
        }
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            Task {
                if let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onPicked(image)
                }
                item = nil
            }
        }
    }
}
