import Foundation

/// The rule engine in code. A command and a state in; a new state, whether the command was carried out,
/// a sentence and what happened out. Whatever proposed the command (the phrases, the model, the voice
/// player), this is the only place the state changes.
enum GameRules {
    /// The most squares one command moves.
    static let maxSteps = 9

    static func apply(_ command: GameCommand, to input: GameState) -> GameResult {
        var s = input
        var events: [GameEvent] = []
        if command != .jump(.up) { s.jumpsInPlace = 0 }

        switch command {
        case .restart:
            let fresh = s.status == .won
                ? GameState.start(s.kind, level: 0, points: 0, found: s.found)
                : GameState.start(s.kind, level: s.levelIndex, points: s.pointsAtLevelStart, found: s.found)
            return GameResult(state: fresh, accepted: true, message: "Level \(fresh.levelIndex + 1), from the start.", events: [.restarted])
        case .nextLevel:
            guard s.status == .levelWon else {
                return refuse(input, s.status == .won ? "That was the last level. Say restart to play again." : "Finish this level first.")
            }
            let next = GameState.start(s.kind, level: s.levelIndex + 1, points: s.points, found: s.found)
            return GameResult(state: next, accepted: true, message: "Level \(next.levelIndex + 1): \(next.level.title).", events: [.nextLevel])
        case .hint:
            return GameResult(state: s, accepted: true, message: "A clue is on the board.", events: [.hint])
        case .thanks:
            if s.thankedThisLevel { return GameResult(state: s, accepted: true, message: "You are welcome.", events: [.nothing]) }
            s.thankedThisLevel = true
            s.points += 5
            if !s.found.contains("manners") { s.found.append("manners") }
            return GameResult(state: s, accepted: true, message: "You are welcome. Five points for manners.", events: [.egg])
        default:
            break
        }

        switch s.status {
        case .playing: break
        case .levelWon: return refuse(input, "This level is done. Say next level.")
        case .won: return refuse(input, "Every level is done. Say restart to play again.")
        case .lost: return refuse(input, "The game is lost. Say restart.")
        }

        var taken = 0
        var message = ""
        switch command {
        case .move(let direction, let count):
            if s.kind.hasGravity && (direction == .up || direction == .down) {
                return apply(.climb(direction, count), to: input)
            }
            s.facing = direction.dx == 0 ? s.facing : direction
            for _ in 0..<clamp(count) {
                let next = s.player.moved(direction)
                let tile = s.tile(at: next)
                if tile.isSolid {
                    message = tile == .door ? "A locked door." : "A wall is in the way."
                    events.append(.blocked)
                    break
                }
                if tile == .exit && !s.exitOpen {
                    message = "The exit is shut until all the gold is found."
                    events.append(.exitShut)
                    break
                }
                s.player = next
                taken += 1
                s.movesUsed += 1
                if !enter(&s, &events) { break }
                if s.kind.hasGravity {
                    if settle(&s, &events) { break }
                    if s.status != .playing { break }
                }
            }
            if taken > 0 { events.insert(.moved, at: 0) }

        case .jump(let wanted):
            guard s.kind.hasGravity else { return refuse(input, "There is no jumping in Boxes. Say a direction.") }
            let direction = wanted ?? s.facing
            guard direction != .down else { return refuse(input, "You cannot jump down. Say climb down on a ladder.") }
            guard s.tile(at: s.player) != .ladder else { return refuse(input, "You are holding a ladder. Say climb up or climb down.") }
            let above = s.player.moved(.up)
            guard !s.tile(at: above).isSolid else { return refuse(input, "There is no room to jump here.") }
            s.movesUsed += 1
            taken = 1
            events.append(.jumped)
            if direction == .up {
                s.jumpsInPlace += 1
                if s.jumpsInPlace == 3 && !s.found.contains("dance") {
                    s.found.append("dance")
                    s.points += 25
                    events.append(.egg)
                    message = "A little dance. Twenty five points, for style."
                } else {
                    message = "You jump on the spot."
                }
                break
            }
            s.facing = direction
            s.player = above
            if enter(&s, &events) {
                for _ in 0..<2 {
                    let next = s.player.moved(direction)
                    let tile = s.tile(at: next)
                    if tile.isSolid || (tile == .exit && !s.exitOpen) { break }
                    s.player = next
                    if !enter(&s, &events) { break }
                }
            }
            if s.status == .playing { _ = settle(&s, &events) }

        case .climb(let direction, let count):
            guard s.kind.hasGravity else { return apply(.move(direction, count), to: input) }
            guard direction == .up || direction == .down else { return apply(.move(direction, count), to: input) }
            for _ in 0..<clamp(count) {
                let next = s.player.moved(direction)
                let tile = s.tile(at: next)
                let canClimb = direction == .up
                    ? s.tile(at: s.player) == .ladder && !tile.isSolid && (tile != .exit || s.exitOpen)
                    : tile == .ladder
                guard canClimb else { break }
                s.player = next
                taken += 1
                s.movesUsed += 1
                if !enter(&s, &events) { break }
            }
            if taken == 0 { return refuse(input, direction == .up ? "There is no ladder to climb here." : "There is no ladder going down here.") }
            events.insert(.climbed, at: 0)
            if s.status == .playing { _ = settle(&s, &events) }

        case .unlock:
            guard let door = GameDirection.allCases.map({ s.player.moved($0) }).first(where: { s.tile(at: $0) == .door }) else {
                return refuse(input, "There is no door next to you.")
            }
            guard s.keys > 0 else { return refuse(input, "You need a key for this door.") }
            s.keys -= 1
            s.set(.floor, at: door)
            s.movesUsed += 1
            taken = 1
            events.append(.unlocked)
            message = "The door opens."

        case .knock:
            guard let secret = GameDirection.allCases.map({ s.player.moved($0) }).first(where: { s.tile(at: $0) == .secret }) else {
                return refuse(input, "Nobody answers.")
            }
            s.set(.floor, at: secret)
            taken = 1
            if !s.found.contains("hidden-door") {
                s.found.append("hidden-door")
                s.points += 30
            }
            events.append(.egg)
            message = "Something gives way: a hidden passage. Thirty points."
            if s.kind.hasGravity { _ = settle(&s, &events) }

        case .restart, .nextLevel, .hint, .thanks:
            break
        }

        guard taken > 0 else {
            return refuse(input, message.isEmpty ? "Nothing happened." : message, events: events.isEmpty ? [.blocked] : events)
        }
        if s.status == .playing && command.costsMoves && s.movesUsed >= s.moveBudget {
            s.status = .lost
            events.append(.outOfMoves)
        }
        return GameResult(state: s, accepted: true, message: describe(s, events: events, fallback: message), events: events)
    }

    private static func clamp(_ steps: Int) -> Int { min(max(steps, 1), maxSteps) }

    private static func refuse(_ state: GameState, _ message: String, events: [GameEvent] = [.blocked]) -> GameResult {
        GameResult(state: state, accepted: false, message: message, events: events)
    }

    /// The player has just arrived on a square. Returns false when the move must stop there.
    @discardableResult
    static func enter(_ s: inout GameState, _ events: inout [GameEvent]) -> Bool {
        switch s.tile(at: s.player) {
        case .gold:
            s.gold += 1
            s.points += 10
            s.set(.floor, at: s.player)
            events.append(.gold)
        case .key:
            s.keys += 1
            s.set(.floor, at: s.player)
            events.append(.key)
        case .trap:
            s.lives -= 1
            events.append(.trap)
            if s.kind.hasGravity {
                s.player = s.home
            } else {
                // In Boxes a trap is spent once it has bitten.
                s.set(.floor, at: s.player)
            }
            if s.lives <= 0 {
                s.status = .lost
                events.append(.lost)
            }
            return false
        case .exit where s.exitOpen:
            s.points += 50 + s.movesLeft
            if s.isLastLevel {
                s.status = .won
                events.append(.gameWon)
            } else {
                s.status = .levelWon
                events.append(.levelWon)
            }
            return false
        default:
            break
        }
        return true
    }

    /// Whether the player can stay at a square without falling.
    static func supported(_ s: GameState, at point: GamePoint) -> Bool {
        let below = s.tile(at: point.moved(.down))
        return s.tile(at: point) == .ladder || below.isSolid || below == .ladder
    }

    /// Gravity: the player falls until something holds them. Returns whether they fell.
    @discardableResult
    static func settle(_ s: inout GameState, _ events: inout [GameEvent]) -> Bool {
        guard s.kind.hasGravity else { return false }
        var fell = false
        var guardRail = s.height + 1
        while !supported(s, at: s.player) && guardRail > 0 {
            guardRail -= 1
            s.player = s.player.moved(.down)
            fell = true
            if !enter(&s, &events) { break }
        }
        if fell { events.append(.fell) }
        return fell
    }

    static func settle(_ s: inout GameState, events: [GameEvent]?) {
        var ignored: [GameEvent] = []
        settle(&s, &ignored)
    }

    /// One sentence for the screen from what happened.
    static func describe(_ s: GameState, events: [GameEvent], fallback: String) -> String {
        if events.contains(.gameWon) { return "Every level done. \(s.points) points." }
        if events.contains(.levelWon) { return "Level done! Say next level." }
        if events.contains(.outOfMoves) { return "Out of moves. Say restart." }
        if events.contains(.lost) { return "Out of lives. Say restart." }
        if events.contains(.trap) { return s.kind.hasGravity ? "Ouch, spikes. Back to the start." : "A trap! One life gone." }
        if !fallback.isEmpty && (events.contains(.egg) || events.contains(.unlocked) || events.contains(.jumped)) { return fallback }
        if events.contains(.gold) { return s.exitOpen ? "All the gold! The exit is open." : "Gold. \(s.goldLeft) to go." }
        if events.contains(.key) { return "A key." }
        if !fallback.isEmpty { return fallback }
        if events.contains(.fell) { return "Down you go." }
        return "OK."
    }
}

/// A breadth-first search over the rules themselves: the shortest list of one-step commands that wins
/// the level without losing a life. The hint engine and the voice player use it, and the tests use it
/// to prove every level can be won within its budget.
enum GamePlanner {
    /// The one-step commands worth trying in a game.
    static func candidates(_ kind: GameKind) -> [GameCommand] {
        switch kind {
        case .boxes:
            return GameDirection.allCases.map { .move($0, 1) } + [.unlock]
        case .lantern:
            return [.move(.left, 1), .move(.right, 1), .jump(.left), .jump(.right), .climb(.up, 1), .climb(.down, 1), .unlock]
        }
    }

    static func plan(_ state: GameState, limit: Int = 60_000) -> [GameCommand]? {
        guard state.status == .playing else { return state.status == .levelWon ? [.nextLevel] : nil }
        struct Node { let state: GameState; let parent: Int; let command: GameCommand? }
        var nodes = [Node(state: state, parent: -1, command: nil)]
        var seen: Set<String> = [key(state)]
        var head = 0
        while head < nodes.count && nodes.count < limit {
            let node = nodes[head]
            for command in candidates(state.kind) {
                let result = GameRules.apply(command, to: node.state)
                guard result.accepted, result.state.lives == node.state.lives, result.state.status != .lost else { continue }
                let k = key(result.state)
                guard !seen.contains(k) else { continue }
                seen.insert(k)
                nodes.append(Node(state: result.state, parent: head, command: command))
                if result.state.status == .levelWon || result.state.status == .won {
                    var path: [GameCommand] = []
                    var index = nodes.count - 1
                    while let command = nodes[index].command {
                        path.append(command)
                        index = nodes[index].parent
                    }
                    return path.reversed()
                }
            }
            head += 1
        }
        return nil
    }

    private static func key(_ s: GameState) -> String { "\(s.picture)|\(s.keys)" }

    /// Runs of the same one-step move become one command with steps: what a person would say.
    static func compress(_ commands: [GameCommand]) -> [GameCommand] {
        var out: [GameCommand] = []
        for command in commands {
            if case .move(let d, let n) = command, case .move(let d0, let n0)? = out.last, d == d0, n0 + n <= GameRules.maxSteps {
                out[out.count - 1] = .move(d, n0 + n)
            } else if case .climb(let d, let n) = command, case .climb(let d0, let n0)? = out.last, d == d0, n0 + n <= GameRules.maxSteps {
                out[out.count - 1] = .climb(d, n0 + n)
            } else {
                out.append(command)
            }
        }
        return out
    }

    /// Where the next stretch of the plan ends: the square the hint engine points at.
    static func target(_ state: GameState, plan: [GameCommand]) -> GamePoint? {
        guard let first = compress(plan).first else { return nil }
        let result = GameRules.apply(first, to: state)
        return result.accepted ? result.state.player : nil
    }
}
