# Ogg Opus fixtures

Small Ogg Opus files for `OggOpusTests.swift`. Tones only: no voice, invented or real. Made on 17 November 2026
with ffmpeg 6 and libopus, in the shape WhatsApp sends (mono, 16 kHz input, 20 ms packets, VoIP mode):

| File | How |
|---|---|
| `oggfixture-tone-440-short.opus` | `ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=16000:duration=0.6" -c:a libopus -b:a 16k -application voip -frame_duration 20 -map_metadata -1 -fflags +bitexact -flags:a +bitexact` (one audio page) |
| `oggfixture-tone-300-pages.ogg` | the same, 300 Hz for 4 s, with `-page_duration 250000` (18 pages) |
| `oggfixture-tone-500-stereo-60ms.opus` | 500 Hz for 1.5 s at 48 kHz, `-ac 2 -b:a 32k -frame_duration 60` (stereo, packets longer than one 255-byte segment) |
| `oggfixture-damaged.ogg` | `oggfixture-tone-300-pages.ogg` with byte 736 (inside its fourth page) inverted, so that page fails its checksum |

Each has a pre-skip of 312 samples. The expected lengths in the tests are the final granule position less the pre-skip.
The file name is not `README.md` because every file in `Tests/` is copied into the test bundle, and resource names must be unique.
