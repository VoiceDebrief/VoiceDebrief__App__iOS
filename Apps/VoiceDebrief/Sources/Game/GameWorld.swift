import Foundation

// The primitives of experiment L03, the voice game. Plain Swift with no model in sight: the code owns
// the state, and everything here is unit tested. Issue 300.

/// A square of the board. x grows to the right, y grows downwards.
struct GamePoint: Codable, Hashable, Sendable {
    var x: Int
    var y: Int

    func moved(_ direction: GameDirection, by steps: Int = 1) -> GamePoint {
        GamePoint(x: x + direction.dx * steps, y: y + direction.dy * steps)
    }

    func distance(to other: GamePoint) -> Int { abs(x - other.x) + abs(y - other.y) }
}

enum GameDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right

    var dx: Int {
        switch self {
        case .left: return -1
        case .right: return 1
        case .up, .down: return 0
        }
    }

    var dy: Int {
        switch self {
        case .up: return -1
        case .down: return 1
        case .left, .right: return 0
        }
    }

    var opposite: GameDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    /// The word heard, including the compass and what the recogniser often writes instead.
    static func from(word: String) -> GameDirection? {
        switch word {
        case "up", "upward", "upwards", "north", "op": return .up
        case "down", "downward", "downwards", "south": return .down
        case "left", "west", "lift", "lefts": return .left
        case "right", "east", "write", "rite", "wright", "rights": return .right
        default: return nil
        }
    }
}

/// The games built on the same primitives.
enum GameKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Squares seen from above. Deliberately primitive.
    case boxes
    /// A small figure seen from the side, with gravity.
    case lantern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boxes: return "Boxes"
        case .lantern: return "Lantern"
        }
    }

    var summary: String {
        switch self {
        case .boxes: return "Squares from above: gather the gold, the exit opens."
        case .lantern: return "A small figure from the side: walk, jump and climb to the light."
        }
    }

    var hasGravity: Bool { self == .lantern }
}

enum GameTile: String, Codable, Sendable {
    case floor, wall, gold, key, door, trap, exit, ladder
    /// Looks like a wall and is not. Knock.
    case secret

    init?(symbol: Character) {
        switch symbol {
        case ".", " ", "@": self = .floor
        case "#": self = .wall
        case "o": self = .gold
        case "k": self = .key
        case "D": self = .door
        case "^": self = .trap
        case "E": self = .exit
        case "H": self = .ladder
        case "?": self = .secret
        default: return nil
        }
    }

    var symbol: Character {
        switch self {
        case .floor: return "."
        case .wall: return "#"
        case .gold: return "o"
        case .key: return "k"
        case .door: return "D"
        case .trap: return "^"
        case .exit: return "E"
        case .ladder: return "H"
        case .secret: return "?"
        }
    }

    /// Nothing passes through it while it is like this.
    var isSolid: Bool { self == .wall || self == .door || self == .secret }
}

/// One level: its words, its board as text and its limits.
struct GameLevel: Sendable, Identifiable {
    let id: String
    let kind: GameKind
    let title: String
    let story: String
    let rows: [String]
    let moveBudget: Int
    let lives: Int
}

enum GameStatus: String, Codable, Sendable {
    case playing
    /// This level is done; say next level.
    case levelWon
    /// Every level is done.
    case won
    case lost
}

/// A command the rule engine understands. The phrases and the model's tools both end up here.
enum GameCommand: Codable, Equatable, Sendable {
    case move(GameDirection, Int)
    /// nil: the way the player faces.
    case jump(GameDirection?)
    case climb(GameDirection, Int)
    case unlock
    case restart
    case nextLevel
    case hint
    /// Only the phrases know these two.
    case knock
    case thanks

    /// The command as a person would say it.
    var words: String {
        switch self {
        case .move(let direction, let steps): return steps == 1 ? "go \(direction.rawValue)" : "go \(direction.rawValue) \(steps)"
        case .jump(let direction): return direction.map { "jump \($0.rawValue)" } ?? "jump"
        case .climb(let direction, let steps): return steps == 1 ? "climb \(direction.rawValue)" : "climb \(direction.rawValue) \(steps)"
        case .unlock: return "unlock the door"
        case .restart: return "restart"
        case .nextLevel: return "next level"
        case .hint: return "hint"
        case .knock: return "knock knock"
        case .thanks: return "thank you"
        }
    }

    /// Commands that use up a move from the budget when they are carried out.
    var costsMoves: Bool {
        switch self {
        case .move, .jump, .climb, .unlock: return true
        case .restart, .nextLevel, .hint, .knock, .thanks: return false
        }
    }
}

/// What happened when a command was applied, for the screen and the log.
enum GameEvent: String, Codable, Sendable {
    case moved, blocked, gold, key, trap, fell, unlocked, exitShut, levelWon, gameWon, lost, outOfMoves
    case climbed, jumped, egg, restarted, nextLevel, hint, nothing
}

/// The whole state of one game. The code owns it; nothing else writes to it.
struct GameState: Codable, Equatable, Sendable {
    var kind: GameKind
    var levelIndex: Int
    var width: Int
    var height: Int
    /// Row by row.
    var tiles: [GameTile]
    /// Where the player begins the level.
    var home: GamePoint
    var player: GamePoint
    var facing: GameDirection = .right
    var gold = 0
    var goldTotal: Int
    var keys = 0
    var lives: Int
    var movesUsed = 0
    var moveBudget: Int
    var points: Int
    /// Points when this level began, so that a restart takes back only this level's.
    var pointsAtLevelStart: Int
    var status: GameStatus = .playing
    /// The easter eggs found, by name, across levels.
    var found: [String] = []
    var thankedThisLevel = false
    /// Jumps straight up in a row on the same square.
    var jumpsInPlace = 0

    static func start(_ kind: GameKind, level index: Int = 0, points: Int = 0, found: [String] = []) -> GameState {
        let levels = GameLevels.all(kind)
        let level = levels[min(max(index, 0), levels.count - 1)]
        let width = level.rows.map(\.count).max() ?? 0
        var tiles: [GameTile] = []
        var start = GamePoint(x: 1, y: 1)
        for (y, row) in level.rows.enumerated() {
            let chars = Array(row)
            for x in 0..<width {
                let symbol = x < chars.count ? chars[x] : "#"
                if symbol == "@" { start = GamePoint(x: x, y: y) }
                tiles.append(GameTile(symbol: symbol) ?? .wall)
            }
        }
        var state = GameState(kind: kind, levelIndex: min(max(index, 0), levels.count - 1), width: width, height: level.rows.count,
                              tiles: tiles, home: start, player: start, goldTotal: tiles.filter { $0 == .gold }.count,
                              lives: level.lives, moveBudget: level.moveBudget, points: points, pointsAtLevelStart: points)
        state.found = found
        if kind.hasGravity { GameRules.settle(&state, events: nil) }
        return state
    }

    var level: GameLevel { GameLevels.all(kind)[levelIndex] }
    var isLastLevel: Bool { levelIndex == GameLevels.all(kind).count - 1 }
    var goldLeft: Int { goldTotal - gold }
    var exitOpen: Bool { goldLeft == 0 }
    var movesLeft: Int { max(moveBudget - movesUsed, 0) }

    func contains(_ point: GamePoint) -> Bool { point.x >= 0 && point.y >= 0 && point.x < width && point.y < height }

    /// Outside the board reads as wall.
    func tile(at point: GamePoint) -> GameTile {
        contains(point) ? tiles[point.y * width + point.x] : .wall
    }

    mutating func set(_ tile: GameTile, at point: GamePoint) {
        guard contains(point) else { return }
        tiles[point.y * width + point.x] = tile
    }

    func cells(of tile: GameTile) -> [GamePoint] {
        tiles.indices.filter { tiles[$0] == tile }.map { GamePoint(x: $0 % width, y: $0 / width) }
    }

    /// The board as text, one row a line, with the player as @.
    var picture: String {
        (0..<height).map { y in
            String((0..<width).map { x in
                let point = GamePoint(x: x, y: y)
                return point == player ? "@" : tile(at: point).symbol
            })
        }.joined(separator: "\n")
    }

    /// The state in one short line for the model: where the player is and what matters next.
    var oneLine: String {
        var parts: [String] = []
        if let nearest = cells(of: .gold).min(by: { $0.distance(to: player) < $1.distance(to: player) }) {
            parts.append("Nearest gold: \(GameState.relative(from: player, to: nearest)).")
        } else {
            let exits = cells(of: .exit)
            if let exit = exits.first { parts.append("All gold found; the exit is \(GameState.relative(from: player, to: exit)).") }
        }
        if let key = cells(of: .key).first { parts.append("A key is \(GameState.relative(from: player, to: key)).") }
        if keys > 0 { parts.append("You hold \(keys == 1 ? "a key" : "\(keys) keys").") }
        if let door = cells(of: .door).first { parts.append("A locked door is \(GameState.relative(from: player, to: door)).") }
        return parts.joined(separator: " ")
    }

    /// "3 left and 2 up", or "here".
    static func relative(from a: GamePoint, to b: GamePoint) -> String {
        var parts: [String] = []
        if b.x != a.x { parts.append("\(abs(b.x - a.x)) \(b.x < a.x ? "left" : "right")") }
        if b.y != a.y { parts.append("\(abs(b.y - a.y)) \(b.y < a.y ? "up" : "down")") }
        return parts.isEmpty ? "here" : parts.joined(separator: " and ")
    }
}

/// What applying one command did.
struct GameResult: Equatable, Sendable {
    var state: GameState
    /// The world changed as asked, at least in part.
    var accepted: Bool
    var message: String
    var events: [GameEvent]
}
