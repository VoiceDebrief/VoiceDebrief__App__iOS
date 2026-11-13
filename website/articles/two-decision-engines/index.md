# Two decision engines

*A position. From the owner's voice memo of 13 November 2026, written up by the agent.*

An application used to have one thing that decided what happens next: its code. With a model on the device it has two. The code decides by rules somebody wrote. The model decides by judgement nobody wrote. The interesting question is not which is better. It is how the two are joined.

## The position

**The code owns the states. The model is asked one question at a time.**

The application is a set of states and the moves between them: a state machine, as the pipeline already is. At a given state the code may hand the model a small, exact package (this state, this data, these tools) and ask one of two things:

- **What should happen next?** The model answers by calling a function the code offered.
- **Say this another way.** The model turns one form into another: a transcript into a debrief, a debrief into a title, a request into a query. A translation or a projection, not a conversation.

There is no long history. Each prompt stands alone, built for that state, as small as it can be. That is what makes it cheap enough for an on-device model with a few thousand tokens of context, and it is what makes it inspectable: for any decision the model made, the whole of what it was shown fits on one screen.

## Why this shape

- **Control.** The model can only do what the functions offered at that state allow. A tool that is not offered does not exist for it.
- **Debugging.** A one-prompt decision can be replayed. A decision buried in a long conversation cannot.
- **Size.** Small models are good at small, literal tasks and poor at long ones. This asks them only for the first kind.
- **Privacy.** What leaves the code for the model is chosen each time, and can be shown each time.

## Where it leads

If the model can choose the next step through function calls, it can choose what the interface shows. The screens stop being fixed pages and become what the code and the model agree to show for this state: intelligence in the application, not beside it. That only works if every decision can be seen, replayed and overruled, which is why the [lab](../the-lab/index.md) and the [harness](../a-harness-inside-the-app/index.md) come first.

## What is not claimed

None of this is built. Whether Apple's on-device model calls tools reliably enough to drive anything is the first experiment, not an assumption.
