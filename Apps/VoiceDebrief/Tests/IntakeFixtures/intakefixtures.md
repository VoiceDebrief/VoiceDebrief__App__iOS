# Intake fixtures

One small file per format for `AudioIntakeTests.swift`, made on 17 November 2026 with ffmpeg 6 from a 1-second
440 Hz tone (`-f lavfi -i sine=frequency=440:sample_rate=22050:duration=1`, mono, metadata stripped,
`-fflags +bitexact`). The videos are a 64 by 64 blue picture at 5 frames a second with that tone as their sound.

| File | Codec and container |
|---|---|
| `intake-tone.mp3` | libmp3lame 32k, with an ID3 tag |
| `intake-tone-bare.mp3` | the same with no ID3 tag (`-id3v2_version 0 -write_id3v1 0`): starts with a frame sync |
| `intake-tone.m4a` | AAC 32k in MPEG-4 (brand `M4A `) |
| `intake-tone.wav` | PCM 16-bit |
| `intake-tone.flac` | FLAC |
| `intake-tone.aiff` | PCM 16-bit big-endian in AIFF |
| `intake-tone.caf` | Apple Lossless in CAF |
| `intake-tone-vorbis.ogg` | libvorbis in Ogg: must be refused with a plain message |
| `intake-video.mp4` | H.264 and AAC, brand `isom` |
| `intake-video.mov` | the same in QuickTime, brand `qt  ` |
| `intake-video.3gp` | H.264 and AAC 16 kHz in 3GP, brand `3gp6` |
| `intake-video.webm` | VP8 and Opus in WebM: must be refused with a plain message |
| `intake-whatsapp-voice-note-1.opus`, `intake-whatsapp-voice-note-2.opus` | genuine WhatsApp voice notes (Ogg Opus, mono, 48 kHz, 120 ms packets), the owner's own test recordings of 5 August 2026, already public as `tests/fixtures/` of the VoiceDebrief__Website repository, copied byte for byte at the owner's request |

The mislabelled case (Opus bytes named `.mp3`) and the damaged ones are made by the tests from these files.
The name is not `README.md` because every file in `Tests/` is copied into the test bundle, and resource names must be unique.
