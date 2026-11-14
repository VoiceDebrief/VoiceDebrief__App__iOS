import Foundation
import Testing
@testable import VoiceDebrief

// Experiment L03, the voice game. Everything here is code: no model is asked and no model answer is
// invented. A "proposal" in these tests is a tool call written by the test to check the code's checks.

@Suite("L03: the levels")
struct GameLevelTests {
    @Test func everyLevelParsesWithAStartAnExitAndGold() {
        for kind in GameKind.allCases {
            for index in GameLevels.all(kind).indices {
                let state = GameState.start(kind, level: index)
                #expect(state.width > 0 && state.height > 0)
                #expect(state.tiles.count == state.width * state.height)
                #expect(state.cells(of: .exit).count == 1)
                #expect(state.goldTotal > 0)
                #expect(state.tile(at: state.player) != .wall)
                #expect(state.status == .playing)
            }
        }
    }

    @Test func everyLevelCanBeWonWithinItsBudgetWithoutLosingALife() {
        for kind in GameKind.allCases {
            for index in GameLevels.all(kind).indices {
                let start = GameState.start(kind, level: index)
                let plan = GamePlanner.plan(start)
                #expect(plan != nil, "\(kind) level \(index + 1) has no way through")
                guard let plan else { continue }
                #expect(plan.count <= start.moveBudget, "\(kind) level \(index + 1) needs \(plan.count) of \(start.moveBudget)")
                var state = start
                for command in plan {
                    let result = GameRules.apply(command, to: state)
                    #expect(result.accepted)
                    state = result.state
                }
                #expect(state.status == .levelWon || state.status == .won)
                #expect(state.lives == start.lives)
                #expect(state.gold == state.goldTotal)
            }
        }
    }

    @Test func theLastLevelIsTheWholeGame() {
        for kind in GameKind.allCases {
            let last = GameLevels.all(kind).count - 1
            var state = GameState.start(kind, level: last)
            for command in GamePlanner.plan(state) ?? [] { state = GameRules.apply(command, to: state).state }
            #expect(state.status == .won)
            #expect(GameRules.apply(.nextLevel, to: state).accepted == false)
            let again = GameRules.apply(.restart, to: state).state
            #expect(again.levelIndex == 0 && again.points == 0)
        }
    }
}

@Suite("L03: the rules of Boxes")
struct GameBoxesRuleTests {
    @Test func aWallStopsAMoveAndCostsNothing() {
        let start = GameState.start(.boxes)
        let result = GameRules.apply(.move(.up, 1), to: start)
        #expect(!result.accepted)
        #expect(result.state == start)
        #expect(result.message == "A wall is in the way.")
    }

    @Test func goldIsCollectedAndTheExitStaysShutUntilAllOfItIs() {
        var state = GameState.start(.boxes)
        state = GameRules.apply(.move(.right, 3), to: state).state
        #expect(state.gold == 1 && state.points == 10)
        #expect(state.player == GamePoint(x: 4, y: 1))
        let shut = GameRules.apply(.move(.right, 2), to: state)
        #expect(shut.accepted)
        #expect(shut.state.player == GamePoint(x: 5, y: 1))
        #expect(shut.events.contains(.exitShut))
        #expect(shut.state.movesUsed == 4)
    }

    @Test func aTrapTakesALifeAndIsSpent() {
        let start = GameState.start(.boxes, level: 1)
        let result = GameRules.apply(.move(.right, 6), to: start)
        #expect(result.state.lives == start.lives - 1)
        #expect(result.state.player == GamePoint(x: 5, y: 1))
        #expect(result.state.tile(at: GamePoint(x: 5, y: 1)) == .floor)
        #expect(result.events.contains(.trap))
    }

    @Test func runningOutOfMovesLoses() {
        var state = GameState.start(.boxes)
        state.moveBudget = 2
        state = GameRules.apply(.move(.down, 1), to: state).state
        #expect(state.status == .playing)
        let result = GameRules.apply(.move(.down, 1), to: state)
        #expect(result.state.status == .lost)
        #expect(result.events.contains(.outOfMoves))
        #expect(GameRules.apply(.move(.right, 1), to: result.state).accepted == false)
    }

    @Test func aDoorNeedsAKeyAndADoorNextToYou() {
        var state = GameState.start(.boxes, level: 1)
        #expect(GameRules.apply(.unlock, to: state).message == "There is no door next to you.")
        state.player = GamePoint(x: 7, y: 4)
        #expect(GameRules.apply(.unlock, to: state).message == "You need a key for this door.")
        state.keys = 1
        let result = GameRules.apply(.unlock, to: state)
        #expect(result.accepted)
        #expect(result.state.tile(at: GamePoint(x: 6, y: 4)) == .floor)
        #expect(result.state.keys == 0)
    }

    @Test func restartTakesBackOnlyThisLevelsPoints() {
        var state = GameState.start(.boxes, level: 1, points: 100)
        state = GameRules.apply(.move(.down, 2), to: state).state
        #expect(state.points == 110)
        let again = GameRules.apply(.restart, to: state).state
        #expect(again.points == 100)
        #expect(again.player == again.home)
    }
}

@Suite("L03: the rules of Lantern")
struct GameLanternRuleTests {
    @Test func aJumpGoesUpAndTwoAcrossThenFalls() {
        let start = GameState.start(.lantern)
        #expect(start.player == GamePoint(x: 1, y: 4))
        let result = GameRules.apply(.jump(.right), to: start)
        #expect(result.accepted)
        #expect(result.state.player == GamePoint(x: 3, y: 4))
        #expect(result.state.gold == 1)
        #expect(result.state.movesUsed == 1)
    }

    @Test func spikesAreJumpedOverOrTheyCostALife() {
        var state = GameState.start(.lantern, level: 1)
        state.player = GamePoint(x: 6, y: 4)
        let over = GameRules.apply(.jump(.right), to: state)
        #expect(over.state.player == GamePoint(x: 8, y: 4))
        #expect(over.state.lives == state.lives)
        let into = GameRules.apply(.move(.right, 1), to: state)
        #expect(into.state.lives == state.lives - 1)
        #expect(into.state.player == state.home)
    }

    @Test func aLadderIsClimbedAndNotJumpedFrom() {
        var state = GameState.start(.lantern)
        state.player = GamePoint(x: 7, y: 4)
        #expect(GameRules.apply(.jump(.right), to: state).accepted == false)
        let up = GameRules.apply(.climb(.up, 3), to: state)
        #expect(up.state.player == GamePoint(x: 7, y: 1))
        #expect(GameRules.apply(.climb(.up, 1), to: up.state).accepted == false)
        // Up and down in Lantern are climbing.
        #expect(GameRules.apply(.move(.up, 3), to: state).state.player == GamePoint(x: 7, y: 1))
    }

    @Test func climbingWhereThereIsNoLadderIsRefused() {
        let result = GameRules.apply(.climb(.up, 1), to: GameState.start(.lantern))
        #expect(!result.accepted)
        #expect(result.message == "There is no ladder to climb here.")
    }
}

@Suite("L03: the tools of each turn")
struct GameToolScopeTests {
    static func names(_ state: GameState) -> [String] { GameToolScope.tools(for: state).map(\.name) }

    @Test func onlyOpenDirectionsAreOfferedAndSaidSo() {
        let tools = GameToolScope.tools(for: GameState.start(.boxes))
        #expect(tools.map(\.name) == ["move"])
        #expect(tools[0].directions == ["down", "right"])
        #expect(tools[0].description.contains("Open now: down, right."))
    }

    @Test func unlockIsOfferedOnlyNextToADoorWithAKey() {
        var state = GameState.start(.boxes, level: 1)
        state.player = GamePoint(x: 7, y: 4)
        #expect(!Self.names(state).contains("unlock"))
        state.keys = 1
        #expect(Self.names(state).contains("unlock"))
    }

    @Test func aWonOrLostGameOffersOneTool() {
        var state = GameState.start(.boxes)
        state.status = .levelWon
        #expect(Self.names(state) == ["nextLevel"])
        state.status = .lost
        #expect(Self.names(state) == ["restart"])
    }

    @Test func lanternOffersClimbOnALadderAndJumpOffIt() {
        var state = GameState.start(.lantern)
        #expect(Self.names(state) == ["move", "jump"])
        state.player = GamePoint(x: 7, y: 4)
        #expect(Self.names(state) == ["move", "climb"])
        #expect(GameToolScope.tools(for: state).first { $0.name == "climb" }?.directions == ["up"])
    }

    @Test func theEasterEggsAreNeverOffered() {
        for kind in GameKind.allCases {
            for index in GameLevels.all(kind).indices {
                for name in Self.names(GameState.start(kind, level: index)) {
                    #expect(GameToolName(rawValue: name) != nil)
                }
            }
        }
        #expect(!GameToolName.allCases.map(\.rawValue).contains("knock"))
    }

    @Test func aProposalIsCheckedAgainstThisTurnsTools() {
        let offered = GameToolScope.tools(for: GameState.start(.boxes))
        #expect(GameToolScope.check(tool: "move", arguments: ["direction": "right", "steps": "2"], offered: offered) == .ok(.move(.right, 2)))
        #expect(GameToolScope.check(tool: "move", arguments: ["direction": "up", "steps": "1"], offered: offered)
                == .refused("The direction \"up\" is not open now."))
        #expect(GameToolScope.check(tool: "unlock", arguments: [:], offered: offered) == .refused("The tool unlock was not offered this turn."))
        #expect(GameToolScope.check(tool: "move", arguments: ["direction": "down", "steps": "40"], offered: offered) == .ok(.move(.down, 9)))
    }
}

@Suite("L03: the phrases")
struct GamePhraseTests {
    static func boxes(_ text: String) -> GameCommand? { GamePhrases.parse(text, kind: .boxes) }
    static func lantern(_ text: String) -> GameCommand? { GamePhrases.parse(text, kind: .lantern) }

    @Test func directionsAndCounts() {
        #expect(Self.boxes("Go left two.") == .move(.left, 2))
        #expect(Self.boxes("left") == .move(.left, 1))
        #expect(Self.boxes("Left to.") == .move(.left, 2))
        #expect(Self.boxes("down 3") == .move(.down, 3))
        #expect(Self.boxes("Write!") == .move(.right, 1))
        #expect(Self.boxes("go up all the way") == .move(.up, GameRules.maxSteps))
        #expect(Self.boxes("north twice") == .move(.up, 2))
    }

    @Test func otherCommands() {
        #expect(Self.boxes("Open the door") == .unlock)
        #expect(Self.boxes("next level please") == .nextLevel)
        #expect(Self.boxes("I'm stuck") == .hint)
        #expect(Self.boxes("let's start again") == .restart)
        #expect(Self.boxes("Thank you very much") == .thanks)
        #expect(Self.boxes("knock knock") == .knock)
    }

    @Test func boxesHasNoJumpingAndLanternDoes() {
        #expect(Self.boxes("jump left") == .move(.left, 1))
        #expect(Self.lantern("jump left") == .jump(.left))
        #expect(Self.lantern("jump") == .jump(nil))
        #expect(Self.lantern("climb up three") == .climb(.up, 3))
        #expect(Self.lantern("climb") == .climb(.up, 1))
    }

    @Test func refusalsAndChatterAreNotCommands() {
        #expect(Self.boxes("Don't go left") == nil)
        #expect(Self.boxes("I think the meeting went well") == nil)
        #expect(Self.boxes("") == nil)
    }
}

@Suite("L03: the hidden things")
struct GameSecretTests {
    @Test func thanksPaysOncePerLevel() {
        let first = GameRules.apply(.thanks, to: GameState.start(.boxes))
        #expect(first.state.points == 5 && first.state.found == ["manners"])
        #expect(GameRules.apply(.thanks, to: first.state).state.points == 5)
    }

    @Test func aWallThatIsNotAWall() {
        var state = GameState.start(.boxes, level: 1)
        #expect(GameRules.apply(.knock, to: state).message == "Nobody answers.")
        state = GameRules.apply(.move(.down, 3), to: state).state
        let knocked = GameRules.apply(.knock, to: state)
        #expect(knocked.accepted)
        #expect(knocked.state.tile(at: GamePoint(x: 2, y: 4)) == .floor)
        #expect(knocked.state.found.contains("hidden-door"))
    }

    @Test func threeJumpsOnTheSpot() {
        var state = GameState.start(.lantern)
        for _ in 0..<3 { state = GameRules.apply(.jump(.up), to: state).state }
        #expect(state.found.contains("dance"))
        #expect(state.points == 25)
        #expect(state.player == GamePoint(x: 1, y: 4))
    }
}

@Suite("L03: hints, measures and the log")
struct GameMeasureTests {
    @Test func aClueComesWhenStuckAndGoesUpALevel() {
        #expect(GameHints.level(wrongStreak: 1, movesSinceProgress: 0, asked: false, showing: nil) == nil)
        #expect(GameHints.level(wrongStreak: 2, movesSinceProgress: 0, asked: false, showing: nil) == 1)
        #expect(GameHints.level(wrongStreak: 0, movesSinceProgress: 8, asked: false, showing: nil) == 1)
        let one = GameHint(cell: nil, words: "", level: 1, source: "code")
        #expect(GameHints.level(wrongStreak: 3, movesSinceProgress: 0, asked: false, showing: one) == 2)
        let clue = GameHints.make(GameState.start(.boxes), level: 2)
        #expect(clue?.cell != nil)
        #expect(clue?.words.hasPrefix("Try saying") == true)
        #expect(GameHints.make(GameState.start(.boxes), level: 1)?.words == "Head for the glowing square.")
    }

    @Test func tokensAndEnergyAreEstimatedAsSaid() {
        #expect(GameTokenEstimate.of("") == 0)
        #expect(GameTokenEstimate.of("abcd") == 1)
        #expect(GameTokenEstimate.of("abcde") == 2)
        let tools = GameToolScope.tools(for: GameState.start(.boxes))
        let estimate = GameTokenEstimate.estimate(instructions: "abcd", prompt: "abcdefgh", tools: tools, context: 4096)
        #expect(estimate.instructions == 1 && estimate.prompt == 2)
        #expect(estimate.total < 200)
        #expect(abs(GameEnergy.milliwattHours(ms: 1200, watts: 3) - 1.0) < 0.0001)
    }

    @Test func theRulesPromptIsShort() {
        let prompt = GameModelEngine.prompt(words: "go left two", state: GameState.start(.boxes, level: 2))
        let estimate = GameTokenEstimate.estimate(instructions: GameModelEngine.rulesInstructions, prompt: prompt,
                                                  tools: GameToolScope.tools(for: GameState.start(.boxes, level: 2)), context: 4096)
        #expect(estimate.total < 300)
    }

    @MainActor
    @Test func aTypedCommandMovesAndIsTimed() {
        let game = GameController(kind: .boxes)
        game.mode = .phrases
        game.hear("go down two", source: "typed")
        #expect(game.state.player == GamePoint(x: 1, y: 3))
        #expect(game.latest?.engine == "phrases")
        #expect(game.latest?.command == "go down 2")
        #expect(game.latest?.totalMs != nil)
        #expect(game.stats.phraseActed == 1)
    }

    @MainActor
    @Test func twoWrongCommandsBringAClue() {
        let game = GameController(kind: .boxes)
        game.mode = .phrases
        game.hear("go up", source: "typed")
        #expect(game.hint == nil)
        game.hear("fly to the moon", source: "typed")
        #expect(game.hint?.level == 1)
        #expect(game.stats.notUnderstood == 1)
        game.hear("hint", source: "typed")
        #expect(game.hint?.level == 2)
    }

    @MainActor
    @Test func theLogIsJSON() throws {
        let game = GameController(kind: .boxes)
        game.mode = .phrases
        game.hear("right", source: "typed")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let log = try decoder.decode(GameLog.self, from: Data(game.log.json.utf8))
        #expect(log.experiment == "L03")
        #expect(log.entries.count == 1)
        #expect(log.entries[0].words == "right")
        #expect(log.assumptions.count == 3)
    }
}
