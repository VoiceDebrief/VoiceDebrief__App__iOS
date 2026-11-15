# What changed in v0.1.115

Released 15 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

Two more Lab experiments, from the owner's memo of the morning. L06, task discovery: ask about your own data (what are my tasks, what happened with the memo I sent yesterday, what is waiting for me) and see it answered in three steps. The question is read for what kind of thing it asks for, by the code's word lists and by Apple's model through one tool for each kind; the code walks a tree of the app's data and shows each branch it entered and each thing it kept or passed over, with the reason; and the answer is put together by the code from what the walk kept. The model is never shown your data and writes none of the answer. L05, talk back: the same, as a conversation by voice. It listens for one question, answers, says the answer aloud, and listens again. Both time every turn and keep a log that can be shared as JSON. In test: no question has been put to a model, and L05 has not been heard on a device.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
