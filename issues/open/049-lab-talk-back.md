# 049: The lab, fifth experiment (L05): talk back

**Status:** open. From the owner's memo of 15 November 2026, 11:30, relayed by the parent session.

A conversation with Apple's model by voice, with the answer spoken, about the app's own data: what are my
tasks, what happened with the memo I sent yesterday. The code owns the state; the model is asked one
question at a time through function calls.

## Where it stands (15 November 2026)

Built in the Lab on top of L06 (issue 050): each spoken question is answered the way L06 answers it, and a
short form of the answer is said with the system's voice. Four states: not listening, listening, working out
the answer, saying it. Compiled and unit tested; never run on a device.

## What it does not do yet, and why

- **It is half a conversation**: one question, one answer, no memory of the turn before, so "and the one
  before that?" means nothing to it. That follows from asking the model one question at a time with no
  history; a follow-up would need the code to carry the last question's limits forward.
- **It does not listen while it speaks**, so it cannot be interrupted by voice. The Stop button interrupts.
- **It says nothing while a note is being recorded**: speaking changes the shared audio session.
- **Each settled piece of speech is taken as a question.** A long pause in the middle of a question cuts it in two.
- English only: the word lists and the sentences of the answers.

## What to find out on a device

Whether the voice is heard and listening resumes after it; the time from the end of the question to the
first word of the answer; whether it mistakes its own echo or a cough for a question.
