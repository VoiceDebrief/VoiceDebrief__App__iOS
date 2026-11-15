# Three layers: code, the model on the device, and agents

**Kind:** a position. **From:** the owner, 15 November 2026: "three levels of intelligence, or of execution ... what we run at each layer is the superpower." Written up by the Sherpa session. Every example links to [what is built](../../built/index.md), which is the only page that says what exists; most of it is in test and has not been run on a device.

[![Three bands. Code on the device: records, keeps, decides states, counts. Apple's model on the device: transcribes, debriefs, labels, cleans, picks one action; free, private, small. Agents in a loop: the conductor drains lanes, files notes in vaults, replies, writes the app itself; capable, slow, costs per run. A voice note goes down through them: code records and keeps it, the local model transcribes and labels it, the conductor acts on it, and its reply comes back into the app.](../../assets/diagrams/three-layers.svg)](../../assets/diagrams/three-layers.svg)

## The idea in one paragraph

Three things in this project can do work. The **code** in the app is exact, instant and free, and can only do what somebody wrote. **Apple's models on the device** (speech recognition and the Foundation Models framework) understand language, cost nothing per use and never send anything away, but are small. **Agents** (Claude sessions running in a loop, with the conductor's tools, lanes and vaults) can read, write, plan and build, but take minutes, cost money per run and see only what is sent to them. None is best. The skill is choosing, for each step of a job, the lowest layer that can do it well, and handing the result up only when it needs more.

## Layer one: the code

What it is: the Swift in the app, and the scripts beside it. It holds the states, keeps the data and decides everything that has a rule.

What it does today:

- **Never loses a recording.** The note is written to disk the moment recording starts, as WAV that can be repaired if the app dies ([capture without loss](../../built/index.md)).
- **Owns every state.** A note is recording, waiting its turn, being written up, finished, interrupted, waiting to send, sent; the code decides, and the screens say it ([record while a note is written up](../../built/index.md), [a send that is not lost](../../built/index.md)).
- **Works out the briefing.** "2 new notes since you last looked" is counted from the library, not written by a model, so it is always true ([a briefing on opening](../../built/index.md)).
- **Hears the end of a note.** "Send this now" is matched against a fixed list of phrases at the very end of what was said, not interpreted ([finish by voice](../../built/index.md)).
- **Encrypts, signs and syncs.** Vault keys, signed commits, sealed lane messages and push and pull are code, tested against sgit ([the vault engine](../../built/index.md), [PKI interop](../../built/index.md)).

Why here: it must be exact, it must work offline and instantly, and it must be the same every time. Bad at: anything that needs understanding words.

## Layer two: Apple's model on the device

What it is: `SpeechAnalyzer` for the transcript and the Foundation Models framework for everything that reads or writes language, both running on the iPhone, iPad or Mac.

What it does today:

- **Transcribes.** A 22.6-second note in 0.6 seconds on a Mac; 6 minutes 44 seconds in 5.4 seconds on an iPad ([transcript on the device](../../built/index.md)).
- **Debriefs.** A summary, key points and actions, a long note read in parts sized to the model's context ([debrief on the device](../../built/index.md)).
- **Labels while you speak.** Every few seconds, who the note is for, its topic, title and urgency, each filled in through one tool call ([Lab L04](../../built/index.md)).
- **Picks one action.** Given a sentence, which of eight actions it asks for, or none, beside a list of fixed phrases doing the same, so the two can be compared ([Lab L02](../../built/index.md)).
- **Cleans a transcript, with questions.** Full sentences, a passage at a time, and up to three phrases it could not follow ([a clean text](../../built/index.md)).

Why here: it is free per use, so it can run all the time ("I don't feel like I'm using minutes"); nothing leaves the device; it answers in about a second. Bad at: long contexts (4,096 tokens on an iPhone, 8,192 on an iPad), rambling notes (it once gave a task to "[Claude]" because the note addressed Claude by name), and anything that needs the world outside the device. So it is asked one small question at a time, with the code deciding what happens with the answer (the position of [two decision engines](../two-decision-engines/index.md)).

## Layer three: agents in a loop

What it is: Claude sessions, and the conductor that receives what the app sends, working with lanes, vaults and the repository.

What it does today:

- **Receives.** A note sent to Claude (developer) is sealed on the device and dropped into an append lane; the conductor drains it, opens it and files it ([a conductor's inbox](../../built/index.md)).
- **Answers.** Replies come back through a vault the person gave to Claude, and appear under the note they answer ([Claude's replies](../../built/index.md), [the Inbox](../../built/index.md)).
- **Shows what it is doing.** The Agents section reads the agents' own report from that vault: who is working on what, and the decisions waiting for the owner ([Agents](../../built/index.md)).
- **Builds the app.** The sessions working on this repository are this layer too: a voice note from the owner becomes an issue, then code, then a release with a card, which comes back to the app in What is new.

Why here: it can read everything sent to it, plan, write code, call any tool and keep going. Bad at: speed (minutes, not seconds), cost (every run is paid for), privacy (it sees what it is sent, so what goes up is chosen and sealed), and presence (it is not on the device when the network is not).

## How a task moves between the layers

A voice note for someone, end to end:

1. **Code.** Tap to record; the note exists on disk at once; the level bars move; the end phrase is matched.
2. **Local model.** The transcript is made on the device; labels (who, topic, urgency) can be filled in while speaking; a debrief is written.
3. **Code.** The state moves to "waiting to send"; the note is sealed to the recipient's key; the send is retried until it goes, and the row says sent, with the time.
4. **Agents.** The conductor drains the lane, files the note in a vault, acts on it (an issue, a reply, a change to the app) and writes the answer back.
5. **Code.** The app pulls the vault and shows the reply under the note; the briefing counts it.

Each step is done at the lowest layer that can do it, and each handover is a file, a sealed message or a commit that can be seen. Nothing is left in a model's memory.

## Where each thing belongs

| | Code | Local model | Agents |
|---|---|---|---|
| Cost per use | none | none | paid per run |
| Privacy | on the device | on the device | sees what is sent |
| Speed | instant | about a second | minutes |
| Works offline | yes | yes | no |
| Good at | rules, states, keeping, crypto | short language tasks, one question at a time | reading, planning, building, acting in the world |
| Bad at | understanding words | long context, rambling, the outside world | speed, cost, being on the device |
| In this project | `NoteStore`, `Briefing`, `VaultBook`, `VoiceCommand` | `SpeechFileTranscriber`, `OnDeviceModel`, Lab L02 and L04 | `tools/conductor`, the agents vault, the sessions |

## What follows from it

- **Push work down.** If a fixed phrase does it, do not ask a model; if the model on the device can do it, do not send it to an agent. Lab L02 exists to find where that line is.
- **Hand up only what is needed, sealed.** An agent gets the note sent to it, not the library.
- **Make every handover a thing you can see.** A note, a label, a sealed message, a commit, a report in a vault: the app can show it, and the [harness](../a-harness-inside-the-app/index.md) idea draws it.
- **The superpower is the routing.** Each layer is ordinary on its own. What is new is a phone that records without loss, understands for free, and has a team of agents a sealed message away.
