# 050: The lab, sixth experiment (L06): task discovery

**Status:** open. From the owner's memo of 15 November 2026, 11:30, relayed by the parent session.

The owner's pattern from earlier work: the model first works out what kind of thing is being asked (task,
note, project, person, decision), then the code queries a tree of the app's data and the answer is built
from what the query returned, never invented. Show the tree being walked. Timing and tokens on every turn.

## Where it stands (15 November 2026)

Built in the Lab. Five kinds: tasks, notes, what was sent, a person, decisions waiting. Two readers of the
question, the code's word lists and the model (one tool for each kind); the walk and the answer are the
code's. Compiled and unit tested; no question has been put to a model.

## What it does not do yet, and why

- **No projects.** Nothing in the app records a project. A question about one is read as notes about a subject.
- **No labels from L04.** They are not kept on notes yet (issue 048), so the tree has no branch for them.
- **Replies are tied to a note only by quotation**: a message from an agent that quotes the note's opening
  words. A reply that does not quote is found under the person, not under the note.
- **Decisions are what the agents report says agents are waiting on you for.** A decision asked for in any
  other way is not seen.
- **The answer's sentences are fixed patterns.** They are plain and repetitive. Letting the model reword an
  answer it is handed would read better and would let it invent; that is a later experiment, with the walk's
  lines shown beside it.
- **Tokens are estimated** at four characters each, as in L04.

## What to measure, from the log

How often the model's reading of the kind is right and how often the word lists' is; what the model adds on
questions the word lists cannot read; its time per question; whether it fills in the subject and the time
or leaves them out.
