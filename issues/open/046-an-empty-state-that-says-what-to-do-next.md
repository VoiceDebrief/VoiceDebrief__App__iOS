# 046: Every empty screen says what to do next

**Status:** open. Asked for by the owner, 14 November 2026, through the Sherpa brief: "an empty state for every screen that says what to do next". From the Sherpa session's reading of the empty pictures (screens.yml run 39, sgit-app-screens.yml run 19). **Owner:** each screen's own session; the Sherpa session writes the words.

The rule, from SGit Vaults' own first screen, which already does it: an empty screen says what this place is for in one sentence, then the one thing to do, as a button where one fits. It does not only say that nothing is here.

| Screen | Today | Proposed |
|---|---|---|
| VoiceDebrief, Record (`record-empty`) | Says what recording does; the button is there. | Holds. |
| VoiceDebrief, Library (`library-empty`) | "No notes yet. A note is kept here the moment its recording stops." Says what, not what to do. | "No notes yet. Record one on the Record tab: it is kept here the moment you stop, then transcribed and debriefed on this device." With a button that opens Record, if the shell can be asked to change tab. |
| VoiceDebrief, Vaults (`vaults-empty`) | "None yet." in the list, then the Create form. | "No vaults yet. A vault keeps your notes encrypted, on this device first; once you have one, every finished note is saved into it." Above the Create form, as SGit Vaults does it. |
| VoiceDebrief, Recipients (`recipients`, with only the built-in one) | Says what sending does; the add form follows. | Holds: one line could say "Nobody added yet" when the built-in recipient is the only one. |
| VoiceDebrief, Identity (`identity`, none made) | Explains, and says to wait for iCloud Keychain before making a second. | Holds. |
| VoiceDebrief, Contacts, Your activity | Added after the pictures used here. | To read when screens.yml has pictured them empty. |
| VoiceDebrief, Guide | Each part says when this build carries none of it. | Holds. |
| SGit Vaults, first screen (`vaults-empty`) | "No vaults yet", what a vault is, add one by its key or create one. | Holds: the model for the others. |

Done when each "Proposed" row is in the app, or its owner has said why not.
