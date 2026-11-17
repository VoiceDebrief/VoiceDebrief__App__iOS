# 009: Read WhatsApp's Ogg Opus (spike S4)

**Status:** open: built, waiting for real files. Branch `work/share` (the share sheet session).

`AVAudioFile` does not open Ogg containers. Build the Ogg page and packet parser and feed the Opus packets to
`AVAudioConverter` (`kAudioFormatOpus`); bundle libopus only if that fails. Done when twenty real WhatsApp files decode.

## 17 November 2026: built with the Apple SDK alone

- `Model/OggOpus.swift`: Ogg pages with their CRC checked, packets joined across pages, `OpusHead` (channels,
  pre-skip, input rate, output gain, mapping family 0 only, so mono or stereo), `OpusTags`, the final granule
  position, and each packet's length from its table-of-contents byte.
- `Engine/OggOpusDecoder.swift`: Apple's Opus decoder through `AVAudioConverter`, one packet at a time, one
  converter per run of packets of the same length (WhatsApp's are all 20 ms), `primeMethod = .none` so that the
  header's pre-skip is the only trimming. Output is float PCM at 48 kHz, written as a 16-bit WAV.
- `DebriefSession`: a note whose audio starts with `OggS` is decoded first into `audio.wav` in its folder; the Ogg
  file is removed only once the WAV is complete. A failure is a step named Opus with a plain message, and the
  file stays in the note.
- Tests: `OggOpusTests`, on tones made with ffmpeg and libopus (`Apps/VoiceDebrief/Tests/OggFixtures/`).

## Left

- Twenty real WhatsApp voice notes, on a device (the owner's own; none go in the repository).
- A zero-length packet (a lost frame, allowed by RFC 7845) is refused as not valid; WhatsApp is not known to write one.
- Channel mapping family 1 (more than two channels) is refused plainly; a voice note never has it.
