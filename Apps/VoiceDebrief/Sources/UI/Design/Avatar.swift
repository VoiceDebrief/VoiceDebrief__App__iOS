import PhotosUI
import SwiftUI
import UIKit

/// Someone or something a note comes from or goes to, as an avatar draws it.
struct AvatarSubject: Identifiable, Equatable {
    let id: String
    var name: String
    var kind: AvatarKind = .person
    /// A photo kept on this device (a contact's, or the owner's own); nil draws the generated character.
    var photo: Data? = nil
    var variant: Int = 0
}

extension AvatarSubject {
    /// An agent from the agents report, framed by its kind so that a conductor stands out.
    init(agent: AgentsReport.Agent) {
        self.init(id: agent.id, name: agent.name, kind: AvatarKind(agentKind: agent.kind))
    }
}

/// A person's or an agent's face: their photo if one is set, else a character generated from their
/// id (`AvatarSeed`), the same on every device. People are round-ish faces; agents are heads with
/// an antenna. The frame says the kind: green for you, gold with a baton for a conductor, indigo for
/// a session, dashed for a sub-agent. Drawn well at 28, 44 and 88 points.
struct AvatarView: View {
    let id: String
    var kind: AvatarKind = .person
    var size: CGFloat = 44
    var photo: Data? = nil
    var variant: Int = 0

    init(id: String, kind: AvatarKind = .person, size: CGFloat = 44, photo: Data? = nil, variant: Int = 0) {
        self.id = id
        self.kind = kind
        self.size = size
        self.photo = photo
        self.variant = variant
    }

    init(_ subject: AvatarSubject, size: CGFloat = 44) {
        self.init(id: subject.id, kind: subject.kind, size: size, photo: subject.photo, variant: subject.variant)
    }

    private var seed: AvatarSeed { AvatarSeed(id: id, variant: variant) }
    private var framed: Bool { kind != .person }
    private var inner: CGFloat { framed ? size * 0.84 : size }

    private var outline: AnyShape {
        kind.isAgent ? AnyShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)) : AnyShape(Circle())
    }

    var body: some View {
        ZStack {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: inner, height: inner)
                    .clipShape(kind.isAgent ? AnyShape(RoundedRectangle(cornerRadius: inner * 0.28, style: .continuous)) : AnyShape(Circle()))
            } else {
                AvatarCharacter(seed: seed, agent: kind.isAgent, detailed: size >= 40)
                    .frame(width: inner, height: inner)
            }
            frame
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if kind == .conductor, size >= 40 {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .background(AvatarFrame.gold, in: Circle())
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: max(1, size * 0.03)))
                    .offset(x: size * 0.06, y: size * 0.06)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var frame: some View {
        switch kind {
        case .person:
            outline.stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        case .me:
            outline.stroke(DS.Palette.green, lineWidth: max(1.5, size * 0.06))
        case .conductor:
            outline.stroke(AvatarFrame.gold, lineWidth: max(2, size * 0.07))
        case .session:
            outline.stroke(DS.Palette.indigo, lineWidth: max(1.5, size * 0.05))
        case .subagent:
            outline.stroke(Color.secondary, style: StrokeStyle(lineWidth: max(1, size * 0.04), dash: [size * 0.08, size * 0.06]))
        }
    }
}

enum AvatarFrame {
    static let gold = Color(dsHex: 0xD4A12A)
}

/// The generated character itself, drawn in one canvas from a seed.
struct AvatarCharacter: View {
    let seed: AvatarSeed
    let agent: Bool
    var detailed = true

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let main = Color(dsHex: AvatarSeed.palette[seed.colour])
            let accent = Color(dsHex: AvatarSeed.palette[seed.accent])
            let ink = Color(dsHex: 0x0B1B2B)
            let line = max(1.4, s * 0.05)

            // The head.
            let head: Path
            if agent {
                // An antenna, then a rounded head below it.
                ctx.fill(Path(CGRect(x: s * 0.47, y: s * 0.04, width: s * 0.06, height: s * 0.14)), with: .color(accent))
                ctx.fill(Path(ellipseIn: CGRect(x: s * 0.42, y: 0, width: s * 0.16, height: s * 0.16)), with: .color(accent))
                head = Path(roundedRect: CGRect(x: s * 0.06, y: s * 0.16, width: s * 0.88, height: s * 0.8), cornerRadius: s * 0.24, style: .continuous)
            } else {
                head = AvatarCharacter.personHead(shape: seed.shape, in: CGRect(x: 0, y: 0, width: s, height: s))
            }
            ctx.fill(head, with: .linearGradient(Gradient(colors: [main.opacity(0.85), main]),
                                                 startPoint: .zero, endPoint: CGPoint(x: s, y: s)))

            let eyeY = agent ? s * 0.48 : s * 0.44
            let mouthY = agent ? s * 0.72 : s * 0.66
            let left = s * 0.35, right = s * 0.65

            // Cheeks for people, a visor stripe for agents.
            if detailed {
                if agent {
                    ctx.fill(Path(roundedRect: CGRect(x: s * 0.18, y: eyeY - s * 0.12, width: s * 0.64, height: s * 0.24), cornerRadius: s * 0.12),
                             with: .color(ink.opacity(0.28)))
                } else {
                    for x in [s * 0.24, s * 0.76] {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.06, y: s * 0.56, width: s * 0.12, height: s * 0.08)), with: .color(accent.opacity(0.75)))
                    }
                }
            }

            // The eyes.
            for x in [left, right] {
                switch (agent, seed.eyes) {
                case (true, _):
                    let w = s * (seed.eyes % 2 == 0 ? 0.13 : 0.1)
                    ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: eyeY - w / 2, width: w, height: w), cornerRadius: w * 0.3), with: .color(.white))
                case (false, 0):
                    ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.07, y: eyeY - s * 0.07, width: s * 0.14, height: s * 0.14)), with: .color(.white))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.035, y: eyeY - s * 0.03, width: s * 0.07, height: s * 0.07)), with: .color(ink))
                case (false, 1):
                    ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.045, y: eyeY - s * 0.075, width: s * 0.09, height: s * 0.15)), with: .color(ink))
                case (false, 2):
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: x, y: eyeY + s * 0.02), radius: s * 0.06, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                    ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
                default:
                    ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.06, y: eyeY - s * 0.05, width: s * 0.12, height: s * 0.1)), with: .color(ink))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.01, y: eyeY - s * 0.035, width: s * 0.035, height: s * 0.035)), with: .color(.white))
                }
            }

            // The mouth.
            guard detailed || !agent else { return }
            switch seed.mouth {
            case 0:
                var smile = Path()
                smile.addArc(center: CGPoint(x: s * 0.5, y: mouthY - s * 0.06), radius: s * 0.12, startAngle: .degrees(30), endAngle: .degrees(150), clockwise: false)
                ctx.stroke(smile, with: .color(agent ? .white : ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
            case 1:
                ctx.fill(Path(ellipseIn: CGRect(x: s * 0.45, y: mouthY - s * 0.04, width: s * 0.1, height: s * 0.09)), with: .color(agent ? .white : ink))
            case 2:
                var flat = Path()
                flat.move(to: CGPoint(x: s * 0.4, y: mouthY))
                flat.addLine(to: CGPoint(x: s * 0.6, y: mouthY))
                ctx.stroke(flat, with: .color(agent ? .white : ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
            default:
                var grin = Path()
                grin.move(to: CGPoint(x: s * 0.36, y: mouthY - s * 0.03))
                grin.addArc(center: CGPoint(x: s * 0.5, y: mouthY - s * 0.03), radius: s * 0.14, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                grin.closeSubpath()
                ctx.fill(grin, with: .color(agent ? .white : ink))
            }
        }
    }

    /// Four head shapes for people: a circle, a squircle, a hexagon, a flower.
    static func personHead(shape: Int, in r: CGRect) -> Path {
        let s = min(r.width, r.height)
        let c = CGPoint(x: r.midX, y: r.midY)
        switch shape {
        case 0:
            return Path(ellipseIn: r)
        case 1:
            return Path(roundedRect: r, cornerRadius: s * 0.32, style: .continuous)
        case 2:
            var p = Path()
            for i in 0..<6 {
                let a = Double(i) * .pi / 3 - .pi / 2
                let pt = CGPoint(x: c.x + s * 0.5 * cos(a), y: c.y + s * 0.5 * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        default:
            var p = Path(ellipseIn: CGRect(x: c.x - s * 0.36, y: c.y - s * 0.36, width: s * 0.72, height: s * 0.72))
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                let bc = CGPoint(x: c.x + s * 0.34 * cos(a), y: c.y + s * 0.34 * sin(a))
                p.addEllipse(in: CGRect(x: bc.x - s * 0.16, y: bc.y - s * 0.16, width: s * 0.32, height: s * 0.32))
            }
            return p
        }
    }
}

/// Who a note goes from and to, as a small picture: you, an arrow, then the recipient, or several of
/// them overlapping with "Sam, Ana and 3 more" beneath. With no recipient it says the note stays on
/// this device. Compact enough for the top of the record screen on an iPhone.
struct SendRoute: View {
    let from: AvatarSubject
    let to: [AvatarSubject]
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            end(AvatarView(from, size: size), name: from.name)
            arrow
                .frame(height: size)
            recipients
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(to.isEmpty ? "From \(from.name), kept on this device"
                                       : "From \(from.name) to \(RouteNames.line(to.map(\.name), shown: to.count))")
    }

    private func end<Face: View>(_ face: Face, name: String) -> some View {
        VStack(spacing: DS.Space.xxs) {
            face
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: size * 3)
    }

    private var arrow: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().frame(width: 4, height: 4).opacity(0.5)
            }
            Image(systemName: Icon.send)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(DS.Palette.green)
    }

    private static let step: CGFloat = 0.55

    @ViewBuilder
    private var recipients: some View {
        switch to.count {
        case 0:
            end(ZStack {
                Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: Icon.onDevice).font(.system(size: size * 0.4)).foregroundStyle(.secondary)
            }
            .frame(width: size, height: size), name: "This device")
        case 1:
            end(AvatarView(to[0], size: size), name: to[0].name)
        default:
            let shown = Array(to.prefix(4))
            end(ZStack(alignment: .leading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, subject in
                    AvatarView(subject, size: size)
                        .background(Color(.systemBackground), in: Circle())
                        .offset(x: CGFloat(index) * size * Self.step)
                        .zIndex(Double(shown.count - index))
                }
            }
            .frame(width: size + size * Self.step * CGFloat(shown.count - 1), height: size, alignment: .leading),
                name: RouteNames.line(to.map(\.name)))
        }
    }
}

/// The owner's own look: another generated character, or a photo, kept on this device only.
@MainActor
@Observable
final class MyLook {
    static let shared = MyLook()
    private static let variantKey = "vd.me.lookVariant"

    private(set) var variant: Int
    private(set) var photo: Data?
    private let photoURL: URL?

    private init() {
        variant = UserDefaults.standard.integer(forKey: Self.variantKey)
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Me", isDirectory: true)
        photoURL = folder?.appendingPathComponent("photo.jpg")
        photo = photoURL.flatMap { try? Data(contentsOf: $0) }
    }

    /// The owner as a route or a list draws them; `id` is the identity's key fingerprint, or "me".
    func subject(id: String, name: String = "Me") -> AvatarSubject {
        AvatarSubject(id: id, name: name, kind: .me, photo: photo, variant: variant)
    }

    func anotherLook() {
        variant += 1
        UserDefaults.standard.set(variant, forKey: Self.variantKey)
    }

    /// Keeps a small copy of the picture (at most 512 pixels a side); nil removes it.
    func setPhoto(_ data: Data?) {
        guard let photoURL else { return }
        if let data, let small = Self.shrink(data) {
            try? FileManager.default.createDirectory(at: photoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? small.write(to: photoURL, options: [.atomic, .completeFileProtection])
            photo = small
        } else {
            try? FileManager.default.removeItem(at: photoURL)
            photo = nil
        }
    }

    private static func shrink(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 512 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.8)
    }
}

/// "How you look", for the Identity screen: your character, a photo or another look.
struct MyLookSection: View {
    /// The identity's key fingerprint, or "me" before there is one.
    let id: String
    @State private var item: PhotosPickerItem?

    var body: some View {
        let look = MyLook.shared
        Section {
            HStack(spacing: DS.Space.m) {
                AvatarView(look.subject(id: id), size: 88)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Choose a photo", systemImage: "photo")
                    }
                    if look.photo != nil {
                        Button("Remove the photo", systemImage: "xmark.circle", role: .destructive) { look.setPhoto(nil) }
                    } else {
                        Button("Another look", systemImage: "shuffle") { look.anotherLook() }
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, DS.Space.xxs)
        } header: {
            Text("How you look")
        } footer: {
            Text("Your character is drawn from your key. Another look draws a different one on this device. A photo is kept on this device only and is never sent.")
        }
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            Task {
                if let data = try? await chosen.loadTransferable(type: Data.self) { MyLook.shared.setPhoto(data) }
                item = nil
            }
        }
    }
}
