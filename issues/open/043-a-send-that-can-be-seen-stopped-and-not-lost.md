# 043: A send that can be seen, stopped and not lost

**Built (untried on a device): pendingSend and sendProblem kept on the note on disk; waiting sends resumed at launch and when the note is ready; Do not send on the card; rows say waiting, not sent or sent with a time; the briefing says could not be sent; an already-sent recipient asks first.**

**Status:** open. From review round 3 (14 November 2026, `website/reviews/round-3/index.md`). **Owner:** the main session (`RecordView`, `SendBar`, `DebriefSession`, `NoteRow`, `Briefing`).

New findings 1, 2, 3, 7 and 13. Screens `record.recording`, `record.working`, `library`, `record-briefing`,
`note.finished`. Found by four of five users, and in the code.

Finishing and sending in one press (issue 026) is what the fifth user wanted: two taps from a thought to
"Maria has it". That stands. Around it:

1. **No way back where the press is made.** "Finish and send to <name>" is directly under the tick and sends
   with no question. The send waits until the note is written up, and `cancelQueuedSend` exists, but only the
   send bar on the note calls it. The card on the record screen ("Your last note will be sent to ...") has
   "Dismiss" only. Give that card a "Do not send" that cancels the queued send, and keep it until the send has
   started. The privacy user decided against the app on this alone.
2. **A waiting send is lost if the app is closed.** `queuedSends`, `queuedLanes` and `outbox` in
   `DebriefSession` are in memory. Keep what was asked for on the note (to whom, when asked), and send it when
   the note is finished or the app next opens.
3. **A failed send leaves no trace.** `sharing = .failed` is one value for one note, replaced by the next send.
   Record the failure on the note, as `saveProblem` does for a vault, show it on the note and in its row, and
   offer to try again.
4. **Rows and the briefing.** A row says nothing for "waiting to be sent to Maria", "sending" or "could not be
   sent"; the briefing counts what was sent and has no line for what was not. Add both. A row could carry the
   time it was sent, which today is only inside the note.
5. **Sending twice.** "Send to <name>" stays enabled on a note already sent to that person and sends again at
   once. Ask first when the note has already gone to that recipient, or say "Send again".
6. **On an iPad** in landscape the "Finish and send" row is at the left edge, far from the tick. Centre it.

Not asked for: a question before "Finish and send". One press is the point; a way back is what is missing.
