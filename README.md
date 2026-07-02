# Fretwork

<!-- CI badge — uncomment and fix the path after pushing to GitHub:
[![CI](https://github.com/OWNER/Fretwork/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/Fretwork/actions/workflows/ci.yml)
-->

A native macOS guitar practice app: real-time tuner, live chord detection,
interactive fretboard, flash-card drills, and a metronome with synthesized
drums. Built with SwiftUI on a hand-rolled Core Audio engine — **zero
package dependencies**.

<!-- TODO: hero screenshot / demo GIF -->

## Features

- **Tuner** — sub-5-cent accuracy across the guitar range, driven by a YIN
  pitch detector fed directly from a Core Audio HAL IOProc at ~2.7 ms
  latency.
- **Chord detection** — FFT chromagram matched against templates for 144
  chords (12 roots × 12 qualities), with harmonic sieving and hysteresis to
  stay stable on a decaying strum.
- **Fretboard** — every note of any key/scale across 22 frets, live
  highlighting of what you're playing, five tunings, detected chords
  overlaid in place.
- **Flash cards** — scale degrees, note identification, intervals, chord
  qualities; strict mode requires you to *play* the answer, and the app
  hears whether you did.
- **Practice** — guided scale runs and chord changes against a metronome
  with a speed trainer and synthesized kick/snare/hat patterns.

## Architecture

```
MusicTheory (pure data: Note, Scale, Chord, Tuning, Fretboard)
    ↑
Audio (engine: PitchAnalyzer, ChordAnalyzer, LivePitchDetector, AudioMetronome)
    ↑
Features (MVVM: @Observable ViewModels + SwiftUI views per tab)
```

Three decisions carry most of the interesting weight:

**HAL IOProc instead of `installTap`.** `AVAudioEngine.installTap` batches
USB-interface audio into ~100 ms bursts, which is unusable for a tuner.
Registering an `AudioDeviceIOProc` on the input device directly delivers
every hardware buffer (128 frames ≈ 2.7 ms at 48 kHz) — the same approach
DAWs use. Monitoring playback is a separate `AVAudioEngine` whose player
node is fed from the IOProc callback.

**YIN, implemented from the paper.** Pitch detection follows de Cheveigné &
Kawahara, *YIN, a fundamental frequency estimator for speech and music*
(JASA 2002): cumulative-mean-normalized difference function, absolute
threshold, parabolic interpolation for sub-sample period accuracy. The
implementation is ~150 lines of vDSP in
[`PitchAnalyzer.swift`](Fretwork/Audio/PitchAnalyzer.swift).

**Chromagram chord matching with a harmonic sieve.** The chord detector
FFTs a 4096-sample window, picks spectral peaks (parabolic interpolation
recovers true frequencies from 11.7 Hz-wide bins — coarser than a semitone
in the low range), suppresses peaks that sit at 3× a stronger peak (3rd
harmonics inject a phantom fifth), folds the survivors into a 12-bin pitch
class profile, and cosine-matches against chord templates with hysteresis.
Every one of those clauses exists because a test failed without it — see
below.

**Concurrency model.** ViewModels are `@MainActor @Observable`; audio
classes are `nonisolated` with NSLock-guarded state, snapshot-per-callback
on the IO thread, and locks never held across blocking Core Audio calls.
The project builds warning-free under Swift's default-MainActor isolation.

## The DSP is tested — and the tests found the bugs

The test suite synthesizes audio (pure sines, harmonic-rich decaying
plucks, strummed open-voicing chords with string inharmonicity and detune)
and feeds it through the analyzers in 128-frame chunks, exactly as the HAL
delivers it. Two real field bugs were diagnosed this way:

1. **"The tuner doesn't hear my D string."** Tests proved YIN was accurate
   at every string frequency and that RMS doesn't depend on frequency — so
   the fault had to be the amplitude gate, which turned out to be a
   hardcoded threshold duplicated across four ViewModels, more than double
   the value the chord detector used for the same signal.
   ([`PitchAnalyzerTests.swift`](FretworkTests/PitchAnalyzerTests.swift))

2. **"Em keeps flickering to Bsus4."** Synthesized strums reproduced it:
   Em's open voicing has three E strings and two B strings but only one G,
   and the B strings' 3rd harmonic is F# — when the G string's energy
   dipped below the chromagram's noise gate, {E, B, F#} is literally Bsus4.
   The fix was three-part: peak-picking with interpolated frequencies,
   the 3rd-harmonic sieve, and sqrt-compressing the chromagram so a
   softly-struck third can't fall out of the gate.
   ([`ChordAnalyzerTests.swift`](FretworkTests/ChordAnalyzerTests.swift))

Run them:

```sh
xcodebuild test -project Fretwork.xcodeproj -scheme Fretwork -destination 'platform=macOS'
```

## Building

- macOS 14.6+, Xcode 26+
- `open Fretwork.xcodeproj`, hit Run. No packages to resolve.
- The app asks for microphone access on first launch of any listening tab.

## How it was built

Fretwork is a solo project built in close collaboration with Claude Code.
The workflow: a standing code-review document, session-to-session handoff
notes, test-driven bug hunts (write the failing test that reproduces the
symptom, then fix), and hardware verification on a real guitar as the
final gate for anything the tests can't hear. The commit history on the
fix branches reads as a log of that process.

## Known limitations

- The microphone stays hot from the first listening tab until quit (single
  shared detector by design; stopping on window close is planned).
- The metronome schedules clicks from a dedicated thread; sample-accurate
  `scheduleBuffer(at:)` scheduling would remove residual jitter.
- Flash-card hint fretboards always render standard tuning.
- App Sandbox is currently disabled; enabling it with the audio-input
  entitlement is on the roadmap.

## License

[MIT](LICENSE)
