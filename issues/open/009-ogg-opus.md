# 009: Read WhatsApp's Ogg Opus (spike S4)

**Status:** open.

`AVAudioFile` does not open Ogg containers, so a `.opus` or `.ogg` voice note fails with a message that
says so. Build the Ogg page and packet parser and feed the Opus packets to `AVAudioConverter`
(`kAudioFormatOpus`); bundle libopus only if that fails. Done when twenty real WhatsApp files decode.
