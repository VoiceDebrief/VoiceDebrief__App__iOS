import Foundation

/// The levels of both games, as text. `#` wall, `.` floor (or air, in Lantern), `o` gold, `k` key,
/// `D` locked door, `^` trap, `E` exit, `H` ladder, `@` start. One more symbol is not listed here.
/// Every level is proven winnable within its budget by `GamePlanner` in the tests.
enum GameLevels {
    static func all(_ kind: GameKind) -> [GameLevel] {
        switch kind {
        case .boxes: return boxes
        case .lantern: return lantern
        }
    }

    static let boxes: [GameLevel] = [
        GameLevel(id: "boxes-1", kind: .boxes, title: "The storeroom",
                  story: "The vault keeper dropped two gold coins in the storeroom. Find them and the door out opens.",
                  rows: [
                      "#######",
                      "#@..o.E",
                      "#.###.#",
                      "#..o..#",
                      "#######",
                  ], moveBudget: 24, lives: 3),
        GameLevel(id: "boxes-2", kind: .boxes, title: "The locked room",
                  story: "One coin is behind a locked door. The key is at the far end, past a trap. Some walls are thinner than others.",
                  rows: [
                      "#########",
                      "#@...^.k#",
                      "#.#####.#",
                      "#o#...#.#",
                      "#.?o.oD.#",
                      "#.#####.#",
                      "#.......#",
                      "####E####",
                  ], moveBudget: 52, lives: 3),
        GameLevel(id: "boxes-3", kind: .boxes, title: "Two keys",
                  story: "The last room of the vault: two doors, two keys, and traps for the hasty.",
                  rows: [
                      "###########",
                      "#@....#..o#",
                      "#.###.#.#.#",
                      "#.#k#...#.#",
                      "#.#.#####D#",
                      "#o..^..k#.#",
                      "#####.###.#",
                      "#.o.D.....#",
                      "#####E#####",
                  ], moveBudget: 80, lives: 3),
    ]

    static let lantern: [GameLevel] = [
        GameLevel(id: "lantern-1", kind: .lantern, title: "The first flame",
                  story: "The lighthouse lamp has gone out. Pick up the spark on the way, then climb to the lamp.",
                  rows: [
                      "###########",
                      "#........E#",
                      "#......H###",
                      "#..o...H..#",
                      "#@.....H..#",
                      "###########",
                  ], moveBudget: 24, lives: 3),
        GameLevel(id: "lantern-2", kind: .lantern, title: "Spikes and a key",
                  story: "A spark lies past the spikes, and the lamp room door is locked. The key is upstairs.",
                  rows: [
                      "############",
                      "#k...H...DE#",
                      "#####H######",
                      "#....H.....#",
                      "#@.o.H.^.o.#",
                      "############",
                  ], moveBudget: 40, lives: 3),
        GameLevel(id: "lantern-3", kind: .lantern, title: "The lamp room",
                  story: "Two sparks left, one high and one over the blocks. The low road has spikes and no room to jump.",
                  rows: [
                      "#############",
                      "#o.........E#",
                      "##H######?#H#",
                      "#.H......o.H#",
                      "#.H######..H#",
                      "#@H....^...H#",
                      "#############",
                  ], moveBudget: 40, lives: 3),
    ]
}
