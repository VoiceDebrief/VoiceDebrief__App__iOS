import SwiftUI

/// The board: tiles drawn in a Canvas, the player and the clue as views on top so that a move is
/// animated. Sized to fit any screen, from a small iPhone to a large iPad.
struct GameBoardView: View {
    let state: GameState
    let hint: GameHint?

    var body: some View {
        GeometryReader { geometry in
            let cell = min(geometry.size.width / CGFloat(max(state.width, 1)), geometry.size.height / CGFloat(max(state.height, 1)))
            let origin = CGPoint(x: (geometry.size.width - cell * CGFloat(state.width)) / 2,
                                 y: (geometry.size.height - cell * CGFloat(state.height)) / 2)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    GameBoardPainter(state: state, cell: cell, origin: origin).paint(&context)
                }
                if let point = hint?.cell {
                    GameHintRing()
                        .frame(width: cell * 0.95, height: cell * 0.95)
                        .position(center(point, cell: cell, origin: origin))
                        .allowsHitTesting(false)
                }
                GamePlayerMark(kind: state.kind, facing: state.facing, lost: state.status == .lost)
                    .frame(width: cell * 0.86, height: cell * 0.86)
                    .position(center(state.player, cell: cell, origin: origin))
                    .animation(.spring(duration: 0.16, bounce: 0.15), value: state.player)
            }
        }
        .aspectRatio(CGFloat(max(state.width, 1)) / CGFloat(max(state.height, 1)), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The board. \(state.oneLine)")
    }

    private func center(_ point: GamePoint, cell: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(point.x) + 0.5) * cell, y: origin.y + (CGFloat(point.y) + 0.5) * cell)
    }
}

/// Draws the tiles of either game.
struct GameBoardPainter {
    let state: GameState
    let cell: CGFloat
    let origin: CGPoint

    private var side: Bool { state.kind.hasGravity }

    func rect(_ x: Int, _ y: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y) * cell, width: cell, height: cell)
    }

    func paint(_ context: inout GraphicsContext) {
        let whole = CGRect(x: origin.x, y: origin.y, width: cell * CGFloat(state.width), height: cell * CGFloat(state.height))
        if side {
            context.fill(Path(roundedRect: whole, cornerRadius: cell * 0.2),
                         with: .linearGradient(Gradient(colors: [Color(dsHex: 0x0B1B2B), Color(dsHex: 0x1B3A55)]),
                                               startPoint: CGPoint(x: whole.midX, y: whole.minY), endPoint: CGPoint(x: whole.midX, y: whole.maxY)))
        } else {
            context.fill(Path(roundedRect: whole, cornerRadius: cell * 0.2), with: .color(Color(dsHex: 0xE8EEF2)))
        }
        for y in 0..<state.height {
            for x in 0..<state.width {
                tile(state.tile(at: GamePoint(x: x, y: y)), in: rect(x, y), context: &context)
            }
        }
    }

    private func tile(_ tile: GameTile, in r: CGRect, context: inout GraphicsContext) {
        let inset = r.insetBy(dx: cell * 0.06, dy: cell * 0.06)
        switch tile {
        case .floor:
            if !side { context.fill(Path(roundedRect: inset, cornerRadius: cell * 0.12), with: .color(.white)) }
        case .wall, .secret:
            let colour = side ? Color(dsHex: 0x5B4A3A) : Color(dsHex: 0x12283C)
            context.fill(Path(roundedRect: r.insetBy(dx: cell * 0.02, dy: cell * 0.02), cornerRadius: cell * 0.1), with: .color(colour))
            if side {
                var top = Path()
                top.addRect(CGRect(x: r.minX, y: r.minY, width: r.width, height: cell * 0.14))
                context.fill(top, with: .color(Color(dsHex: 0x3E8E5E)))
            }
            if tile == .secret {
                // A hairline crack, for the observant.
                var crack = Path()
                crack.move(to: CGPoint(x: r.midX - cell * 0.1, y: r.minY + cell * 0.3))
                crack.addLine(to: CGPoint(x: r.midX + cell * 0.05, y: r.midY))
                crack.addLine(to: CGPoint(x: r.midX - cell * 0.05, y: r.maxY - cell * 0.3))
                context.stroke(crack, with: .color(.white.opacity(0.12)), lineWidth: max(cell * 0.02, 0.5))
            }
        case .gold:
            if !side { context.fill(Path(roundedRect: inset, cornerRadius: cell * 0.12), with: .color(.white)) }
            if side {
                context.fill(star(in: r.insetBy(dx: cell * 0.22, dy: cell * 0.22)), with: .color(Color(dsHex: 0xF0B429)))
            } else {
                let coin = r.insetBy(dx: cell * 0.26, dy: cell * 0.26)
                context.fill(Path(ellipseIn: coin), with: .color(Color(dsHex: 0xF0B429)))
                context.stroke(Path(ellipseIn: coin.insetBy(dx: cell * 0.06, dy: cell * 0.06)), with: .color(Color(dsHex: 0xB98500)), lineWidth: cell * 0.04)
            }
        case .key:
            if !side { context.fill(Path(roundedRect: inset, cornerRadius: cell * 0.12), with: .color(.white)) }
            let colour = Color(dsHex: 0xB98500)
            let ring = CGRect(x: r.minX + cell * 0.18, y: r.midY - cell * 0.14, width: cell * 0.28, height: cell * 0.28)
            context.stroke(Path(ellipseIn: ring), with: .color(colour), lineWidth: cell * 0.07)
            context.fill(Path(CGRect(x: ring.maxX, y: r.midY - cell * 0.035, width: cell * 0.36, height: cell * 0.07)), with: .color(colour))
            context.fill(Path(CGRect(x: r.maxX - cell * 0.24, y: r.midY, width: cell * 0.07, height: cell * 0.14)), with: .color(colour))
        case .door:
            context.fill(Path(roundedRect: r.insetBy(dx: cell * 0.08, dy: cell * 0.02), cornerRadius: cell * 0.08), with: .color(Color(dsHex: 0x8A5A2B)))
            context.fill(Path(ellipseIn: CGRect(x: r.midX - cell * 0.07, y: r.midY - cell * 0.1, width: cell * 0.14, height: cell * 0.14)), with: .color(Color(dsHex: 0xF0B429)))
        case .trap:
            if !side { context.fill(Path(roundedRect: inset, cornerRadius: cell * 0.12), with: .color(Color(dsHex: 0xFFE3E3))) }
            var spikes = Path()
            let count = 3
            let width = r.width / CGFloat(count)
            for i in 0..<count {
                let left = r.minX + CGFloat(i) * width
                spikes.move(to: CGPoint(x: left + width * 0.1, y: r.maxY - cell * 0.08))
                spikes.addLine(to: CGPoint(x: left + width * 0.5, y: r.minY + cell * 0.35))
                spikes.addLine(to: CGPoint(x: left + width * 0.9, y: r.maxY - cell * 0.08))
                spikes.closeSubpath()
            }
            context.fill(spikes, with: .color(side ? Color(dsHex: 0xC9D2DA) : Color(light: 0xD93A3F, dark: 0xFF6B6B)))
        case .exit:
            let open = state.exitOpen
            if side {
                let lamp = r.insetBy(dx: cell * 0.2, dy: cell * 0.12)
                if open {
                    context.fill(Path(ellipseIn: r.insetBy(dx: -cell * 0.1, dy: -cell * 0.1)), with: .color(Color(dsHex: 0xF0B429).opacity(0.25)))
                }
                context.fill(Path(roundedRect: lamp, cornerRadius: cell * 0.12), with: .color(open ? Color(dsHex: 0xF0B429) : Color(dsHex: 0x6B7785)))
            } else {
                context.fill(Path(roundedRect: inset, cornerRadius: cell * 0.12),
                             with: .color(open ? Color(light: 0x0E9E72, dark: 0x12C08A) : Color(dsHex: 0x9AA6B2)))
                var arrow = Path()
                arrow.move(to: CGPoint(x: r.minX + cell * 0.3, y: r.midY))
                arrow.addLine(to: CGPoint(x: r.maxX - cell * 0.3, y: r.midY))
                arrow.move(to: CGPoint(x: r.maxX - cell * 0.42, y: r.midY - cell * 0.13))
                arrow.addLine(to: CGPoint(x: r.maxX - cell * 0.3, y: r.midY))
                arrow.addLine(to: CGPoint(x: r.maxX - cell * 0.42, y: r.midY + cell * 0.13))
                context.stroke(arrow, with: .color(.white.opacity(open ? 1 : 0.5)), lineWidth: cell * 0.07)
            }
        case .ladder:
            let colour = Color(dsHex: 0xC8A06A)
            var ladder = Path()
            ladder.addRect(CGRect(x: r.minX + cell * 0.22, y: r.minY, width: cell * 0.07, height: r.height))
            ladder.addRect(CGRect(x: r.maxX - cell * 0.29, y: r.minY, width: cell * 0.07, height: r.height))
            for i in 0..<3 {
                ladder.addRect(CGRect(x: r.minX + cell * 0.22, y: r.minY + cell * (0.15 + CGFloat(i) * 0.3), width: cell * 0.56, height: cell * 0.06))
            }
            context.fill(ladder, with: .color(colour))
        }
    }

    private func star(in r: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = r.width / 2
        let inner = outer * 0.45
        for i in 0..<10 {
            let angle = Double(i) * .pi / 5 - .pi / 2
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// The player: a green box with eyes in Boxes; a small figure with a lantern in Lantern.
struct GamePlayerMark: View {
    let kind: GameKind
    let facing: GameDirection
    let lost: Bool

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width
            let look: CGFloat = facing == .left ? -1 : (facing == .right ? 1 : 0)
            switch kind {
            case .boxes:
                ZStack {
                    RoundedRectangle(cornerRadius: s * 0.22).fill(lost ? Color.gray : DS.Palette.green)
                    HStack(spacing: s * 0.16) {
                        Circle().fill(.white).frame(width: s * 0.2)
                        Circle().fill(.white).frame(width: s * 0.2)
                    }
                    .offset(x: look * s * 0.08, y: facing == .up ? -s * 0.1 : (facing == .down ? s * 0.1 : -s * 0.04))
                }
            case .lantern:
                ZStack {
                    // The lantern's glow, on the side the figure faces.
                    Circle().fill(Color(dsHex: 0xF0B429).opacity(lost ? 0 : 0.35))
                        .frame(width: s * 0.6)
                        .offset(x: (look == 0 ? 1 : look) * s * 0.3, y: s * 0.05)
                    Capsule().fill(lost ? Color.gray : DS.Palette.green)
                        .frame(width: s * 0.36, height: s * 0.5)
                        .offset(y: s * 0.18)
                    Circle().fill(Color(dsHex: 0xF5D6B8))
                        .frame(width: s * 0.34)
                        .offset(y: -s * 0.2)
                    Circle().fill(Color(dsHex: 0x0B1B2B))
                        .frame(width: s * 0.07)
                        .offset(x: (look == 0 ? 0.5 : look) * s * 0.08, y: -s * 0.22)
                    RoundedRectangle(cornerRadius: s * 0.04).fill(Color(dsHex: 0xF0B429))
                        .frame(width: s * 0.14, height: s * 0.18)
                        .offset(x: (look == 0 ? 1 : look) * s * 0.3, y: s * 0.12)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A ring that breathes, round the square the clue points at.
struct GameHintRing: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 4)
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(light: 0xB98500, dark: 0xF0B429), lineWidth: 3 + 2 * pulse)
                .opacity(0.5 + 0.5 * pulse)
        }
    }
}
