# 300: L03, a game played by voice, with Apple's model as one of its engines

**From:** the owner, a voice note while driving, 14 November 2026.
**Session:** the game session, branch `work/game`.
**Where:** `Apps/VoiceDebrief/Sources/Game/`, `Apps/VoiceDebrief/Tests/Game*.swift`, one row "L03: Play" in the Lab.

## What was asked

A fun game, played by voice on an iPhone or an iPad, that uses Apple's on-device model (the Foundation Models
framework) as part of its engine: points, obstacles, a little action, a story, problems to solve, levels, winning
and losing, and a couple of easter eggs left to be found. The game is the excuse. The experiment is **speed and
feel**: "I say turn left: how long until it turns left?" Every command is timed from the end of speaking to the
change on the screen, the time is shown every time, and the log is kept and shared as JSON.

## The position it follows

From "Two decision engines" and "A harness inside the app": the code owns the state. The model is asked one
question at a time, with no history, and may only propose: it calls one tool, the code checks the call against
the rules and applies it or says why not. The model is given only what makes sense at that moment.

## The primitives

All in plain Swift with no model in sight, so all of it is unit tested.

| Primitive | What it is |
|---|---|
| `GameState` | A grid of tiles, the player, gold, keys, lives, moves left, points, level, status (playing, level won, won, lost). |
| `GameTile` | floor, wall, gold, key, door, trap, exit, ladder, and one that looks like a wall and is not. |
| `GameLevel` | A title, two lines of story, a few rows of text (`#` wall, `o` gold, `k` key, `D` door, `^` trap, `E` exit, `H` ladder, `@` start), a move budget and lives. |
| `GameCommand` | move (direction, steps), jump, climb, unlock, restart, next level, hint, and two that only the phrases know. |
| `GameRules.apply` | The rule engine in code: a command and a state in, a new state, whether it was accepted, a sentence and events out. |
| `GameToolScope` | The tools that make sense in this state, with descriptions that say what is possible now. |
| `GamePlanner` | A breadth-first search over the rules themselves: the shortest list of commands that wins the level. Used by the hint engine, the voice player and the tests (every level is proven winnable). |

## Two games on the same primitives

1. **Boxes**, deliberately primitive: squares seen from above. Collect the gold, the exit opens, avoid the traps,
   find the key for the door, within a move budget. Three levels.
2. **Lantern**, more visual: a small figure seen from the side, with gravity. Walk, jump gaps and spikes, climb
   ladders, carry the flame to the top. Its own levels and its own tools (walk, jump, climb).

Both are original. No existing game's name, characters, levels or look.

## Per-turn tool scoping

Each request offers only the tools the current state allows, and each tool's description is written for this
moment. For example, standing in a corridor with walls above and below, holding no key: one tool, `move`, whose
description says "Open now: left, right". Next to a door with a key: `move` and `unlock`. After a level is won:
`nextLevel` only. Lost: `restart` only. In Lantern, `climb` exists only on or above a ladder and `jump` only when
there is room above. The prompt is one line of state and the sentence. The instructions are three sentences.
The easter eggs are never offered to the model.

## Three engines, each a separate and narrow use

1. **The rule engine.** The sentence goes first to the phrases (the code's fast path: "left", "go up three",
   "unlock the door"), then, if they find nothing, to the model with the scoped tools. The first tool call ends the
   request (nothing after it is generated, which saves time and energy), is checked, and applied. A switch asks
   the model in the shadow even when the phrases acted, so every command can carry both times.
2. **The hint engine.** It watches: two wrong or useless commands in a row, eight moves without progress, or "hint".
   Then it shows a clue on the board, never the whole answer: first the square to head for, then the words to try.
   The planner knows the way; the model, given a short state and the last wrong words, may phrase the clue
   through one tool (`showClue`), which the code checks (short, one square).
3. **The voice player.** A synthetic player that speaks commands aloud with `AVSpeechSynthesizer`; the microphone
   hears them and they go through exactly the same pipeline as the owner's. It plans with `GamePlanner`, varies its
   wording (sometimes in words no phrase holds, so the model is exercised), and now and then says something wrong,
   so the hint engine is exercised too. The end of its speech is known to the millisecond, which makes its timings
   the cleanest. It is a planner in code, not a model.

## What is measured, every command

- **Latency**: the end of speech (the last change to the live words; for the voice player, the moment the
  synthesiser finished; for typed words, the press of return) to the words settling, to the engine's decision, to
  the new state applied. Shown as one large number and its parts, with the engine that acted.
- **The model's request**: time to the first tool call, total time, whether the session was prewarmed, the tools
  offered, and tokens: estimated at four characters a token for the instructions, the prompt and the tools, against
  the model's reported context (about 4,096).
- **Energy, estimated**: the time on the model times an assumed power, said as an assumption on the screen; the
  thermal state from `ProcessInfo`; the phrase engine's cost beside it, which is close to nothing.
- **The log**: every command, word for word, both engines' answers and times, the outcome, as JSON to share.

## Steps

1. This note; Boxes end to end (voice, phrases or model, tool call, move, latency shown, log). Hints in code.
2. The hint engine with the model's clue.
3. The voice player.
4. Lantern, the second game.

## Not now

Onboarding challenges on the same primitives ("your job is to record a voice memo"), and the app itself driven by
voice ("open the lab"). Exact token counts (an estimate until the SDK's count is tried). A model as the voice player.
