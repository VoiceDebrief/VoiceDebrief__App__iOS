# 048: The lab, fourth experiment (L04): live labels

**Status:** open. From the owner's five-minute voice note of 14 November 2026, 19:07, relayed by the parent
session. See the articles "The lab" and "Two decision engines".

While a note is being recorded, ask Apple's model every few seconds to fill a small set of labels from the
transcript so far, and show them as a grid of chips that update live: who it is for (matched to contacts and
agents, with their avatar), topic, title, urgency, and a couple of others from a list. The owner can override
by voice in the middle of a recording, and the override sticks: the code owns the state, and the model
proposes through function calls, one tool for each label, with no long history. Send a window of the
transcript and measure whether sending all of it is fast enough. Show the timing of every loop.

## Where it stands (14 November 2026)

Built in the Lab as its own screen, with its own listening (the live words) and a field to type sentences
into. Compiled and unit tested; no loop has been run against a model.

## What it does not do yet, and why

- **It is not on the Record screen and labels do not travel with a note.** The board of labels is a plain
  value that can be saved, with the matched recipient and the title ready to be read from it; putting it on
  `RecordView` and into a note belongs to the session that owns them.
- **It keeps no recording.** The Lab's listening hears the words and nothing else.
- **The switches for which labels are on the L04 screen**, not in Settings, which this session does not own.
- **Tokens are estimated** at four characters each. Apple's framework has a token counter, but it is not
  known to be in the iOS 26.5 SDK that CI builds with.
- **A new session is made for every loop**, tools and all. L03 keeps a session ready between requests; if the
  loops are slow, that is the first thing to try, and the log will say whether it is needed.
- English only: the spoken phrases that set a label.

## What to measure, from the log

Time to the first label and time in all, at each window size, on an iPhone, an iPad and a Mac. Whether the
model calls the label tools at all. How often a label it offers is right, and how often it churns a label
that was already right. Whether "everything so far" fails once a note is long.
