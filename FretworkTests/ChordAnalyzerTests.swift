import XCTest
import AVFoundation
@testable import Fretwork

/// Feeds synthesized guitar chords through `ChordAnalyzer` in the same
/// 128-frame chunks the HAL IOProc delivers, to characterize why chord
/// detection struggles in practice. Chords are built from real open-position
/// voicings (one decaying harmonic-rich pluck per string), not abstract
/// triads, so octave doubling and harmonic content match what the analyzer
/// sees from an actual guitar.
final class ChordAnalyzerTests: XCTestCase {

    private let sampleRate: Double = 48_000
    private let chunkSize = 128

    // MARK: - Open-position voicings (string fundamentals, low to high)

    private static let openVoicings: [(chord: Chord, frequencies: [Double])] = [
        (Chord(root: .e, quality: .major),
         [82.41, 123.47, 164.81, 207.65, 246.94, 329.63]),        // E B E G# B E
        (Chord(root: .e, quality: .minor),
         [82.41, 123.47, 164.81, 196.00, 246.94, 329.63]),        // E B E G B E
        (Chord(root: .a, quality: .major),
         [110.00, 164.81, 220.00, 277.18, 329.63]),               // A E A C# E
        (Chord(root: .a, quality: .minor),
         [110.00, 164.81, 220.00, 261.63, 329.63]),               // A E A C E
        (Chord(root: .d, quality: .major),
         [146.83, 220.00, 293.66, 369.99]),                       // D A D F#
        (Chord(root: .g, quality: .major),
         [98.00, 123.47, 146.83, 196.00, 246.94, 392.00]),        // G B D G B G
        (Chord(root: .c, quality: .major),
         [130.81, 164.81, 196.00, 261.63, 329.63]),               // C E G C E
    ]

    // MARK: - Signal generation

    private func format() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    /// One plucked string with a realistic harmonic series. Freshly plucked
    /// guitar strings have 2nd/3rd harmonics comparable to the fundamental
    /// (especially picked near the bridge), and higher harmonics decay
    /// faster — so the early attack is bright, then mellows. This matters:
    /// weak-harmonic fixtures hide real failure modes like Em wavering to
    /// Bsus4 (the B strings' 3rd harmonic is F#).
    /// `onset` staggers strings to simulate a strum. `detuneCents` models
    /// imperfect tuning; string stiffness makes real harmonics slightly
    /// sharp (inharmonicity), modeled with coefficient B ≈ 4e-4.
    private func pluckedString(fundamental: Double, amplitude: Double, onset: Double,
                               duration: Double, detuneCents: Double = 0,
                               into samples: inout [Double]) {
        let startSample = Int(onset * sampleRate)
        let n = min(samples.count - startSample, Int(duration * sampleRate))
        guard n > 0 else { return }
        let f0 = fundamental * pow(2, detuneCents / 1200)
        let inharmonicity = 4e-4
        let harmonicAmplitudes: [Double] = [1.0, 0.9, 0.7, 0.4, 0.25]
        let totalWeight = harmonicAmplitudes.reduce(0, +)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            var v = 0.0
            for (h, a) in harmonicAmplitudes.enumerated() {
                let order = Double(h + 1)
                let fh = order * f0 * (1 + inharmonicity * order * order).squareRoot()
                // Higher harmonics decay faster: base 2/s + 1.2/s per order.
                let decay = 2.0 + 1.2 * Double(h)
                v += a * exp(-t * decay) * sin(2 * .pi * fh * t)
            }
            samples[startSample + i] += amplitude * v / totalWeight
        }
    }

    /// A strummed chord: one pluck per string, 12 ms apart, normalized to a
    /// target peak so string count doesn't change overall level.
    /// `amplitudes`/`detunes` model an uneven, imperfectly tuned strum;
    /// defaults are a clean even strum.
    private func strummedChord(frequencies: [Double], peak: Float = 0.3, duration: Double = 1.0,
                               amplitudes: [Double]? = nil, detunes: [Double]? = nil) -> [Float] {
        var mix = [Double](repeating: 0, count: Int(sampleRate * duration))
        for (i, f) in frequencies.enumerated() {
            pluckedString(fundamental: f,
                          amplitude: amplitudes?[i] ?? 1.0,
                          onset: Double(i) * 0.012,
                          duration: duration,
                          detuneCents: detunes?[i] ?? 0,
                          into: &mix)
        }
        let maxAbs = mix.map(abs).max() ?? 1
        guard maxAbs > 0 else { return mix.map { Float($0) } }
        let scale = Double(peak) / maxAbs
        return mix.map { Float($0 * scale) }
    }

    private func chunk(_ samples: [Float]) -> [AVAudioPCMBuffer] {
        let fmt = format()
        var buffers: [AVAudioPCMBuffer] = []
        var i = 0
        while i < samples.count {
            let len = min(chunkSize, samples.count - i)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(len)) else { break }
            buf.frameLength = AVAudioFrameCount(len)
            let dst = buf.floatChannelData![0]
            for j in 0..<len { dst[j] = samples[i + j] }
            buffers.append(buf)
            i += len
        }
        return buffers
    }

    /// Runs a signal through a fresh analyzer and tallies every reported chord.
    private func detections(for samples: [Float]) -> (all: [(chord: Chord, confidence: Double)], tally: [Chord: Int]) {
        let analyzer = ChordAnalyzer()
        var all: [(chord: Chord, confidence: Double)] = []
        var tally: [Chord: Int] = [:]
        for buffer in chunk(samples) {
            if let result = analyzer.analyze(buffer, sampleRate: sampleRate) {
                all.append(result)
                tally[result.chord, default: 0] += 1
            }
        }
        return (all, tally)
    }

    // MARK: - Baseline

    func testSilenceReportsNoChord() {
        let silence = [Float](repeating: 0, count: Int(sampleRate * 0.5))
        let (all, _) = detections(for: silence)
        XCTAssertTrue(all.isEmpty, "silence should never classify as a chord")
    }

    /// Easiest possible input: equal-amplitude pure sine triad, no harmonics,
    /// no octave doubling. If this fails, template matching itself is broken.
    func testPureSineTriadsClassifyCorrectly() {
        let triads: [(chord: Chord, frequencies: [Double])] = [
            (Chord(root: .a, quality: .major), [220.00, 277.18, 329.63]),   // A3 C#4 E4
            (Chord(root: .a, quality: .minor), [220.00, 261.63, 329.63]),   // A3 C4 E4
            (Chord(root: .c, quality: .major), [261.63, 329.63, 392.00]),   // C4 E4 G4
        ]
        for (expected, frequencies) in triads {
            let n = Int(sampleRate * 0.5)
            var mix = [Float](repeating: 0, count: n)
            for f in frequencies {
                for i in 0..<n {
                    mix[i] += 0.1 * Float(sin(2 * .pi * f * Double(i) / sampleRate))
                }
            }
            let (all, tally) = detections(for: mix)
            guard let winner = tally.max(by: { $0.value < $1.value })?.key else {
                XCTFail("\(expected.name): no chord ever detected from a clean triad")
                continue
            }
            XCTAssertEqual(winner, expected,
                "\(expected.name): classified as \(winner.name) (\(all.count) detections, tally \(tally.mapValues { $0 }))")
        }
    }

    // MARK: - Realistic strummed chords

    /// The production scenario: strummed open voicings with harmonics and
    /// octave doubling. Majority vote over the whole strum should match.
    func testStrummedOpenChordsClassifyCorrectly() {
        for (expected, frequencies) in Self.openVoicings {
            let samples = strummedChord(frequencies: frequencies)
            let (all, tally) = detections(for: samples)
            guard let winner = tally.max(by: { $0.value < $1.value })?.key else {
                XCTFail("\(expected.name): no chord ever detected from a strummed voicing")
                continue
            }
            let correct = tally[expected] ?? 0
            let total = all.count
            XCTAssertEqual(winner, expected,
                "\(expected.name): majority was \(winner.name) — \(correct)/\(total) frames correct, tally \(Dictionary(uniqueKeysWithValues: tally.map { ($0.key.name, $0.value) }))")
        }
    }

    /// Regression for the reported waver: a sustained chord must not flicker
    /// to other chords as its harmonic balance evolves during the decay
    /// (e.g. Em drifting to Bsus4 because the B strings' 3rd harmonic is F#).
    /// The expected chord should dominate, and no foreign chord should hold
    /// the output long enough to be visible in the UI.
    func testSustainedStrumDoesNotWaverToOtherChords() {
        for (expected, frequencies) in Self.openVoicings {
            let samples = strummedChord(frequencies: frequencies, duration: 1.5)
            let (all, tally) = detections(for: samples)
            let correct = tally[expected] ?? 0
            let total = all.count
            XCTAssertGreaterThan(total, 0, "\(expected.name): nothing detected")
            guard total > 0 else { continue }
            XCTAssertGreaterThanOrEqual(Double(correct) / Double(total), 0.9,
                "\(expected.name): only \(correct)/\(total) frames correct — wavered to \(Dictionary(uniqueKeysWithValues: tally.filter { $0.key != expected }.map { ($0.key.name, $0.value) }))")

            // Longest consecutive run of any foreign chord — a run of ~10
            // frames is enough for the fretboard flow to confirm the wrong chord.
            var worstRun = 0, run = 0
            var runChord: Chord?
            for (chord, _) in all {
                if chord == expected {
                    run = 0; runChord = nil
                } else if chord == runChord {
                    run += 1; worstRun = max(worstRun, run)
                } else {
                    runChord = chord; run = 1; worstRun = max(worstRun, run)
                }
            }
            XCTAssertLessThan(worstRun, 10,
                "\(expected.name): a foreign chord held the output for \(worstRun) consecutive frames")
        }
    }

    /// The real-world case Ian hit: a sloppy Em strum where the chord's
    /// *third* is underrepresented — Em's open voicing has three E strings
    /// and two B strings but only one G, and if that string is hit softly
    /// the chromagram is dominated by {E, B} plus the B strings' F# third
    /// harmonic, which is exactly Bsus4 {B, E, F#}. Applies the same sloppy
    /// profile (weak third, uneven levels, ±4 cents detune) to every voicing.
    func testSloppyStrumWithWeakThirdStillClassifiesCorrectly() {
        for (expected, frequencies) in Self.openVoicings {
            let third = expected.pitchClasses[1]
            let amplitudes = frequencies.enumerated().map { (i, f) -> Double in
                let pc = ((Int(round(12 * log2(f / 440))) % 12) + 12 + 9) % 12
                if pc == third.rawValue { return 0.45 }         // weak third
                return i.isMultiple(of: 2) ? 1.0 : 0.8          // uneven strum
            }
            let detunes = frequencies.indices.map { Double([2, -4, 1, -2, 4, -1][$0 % 6]) }
            let samples = strummedChord(frequencies: frequencies, duration: 1.5,
                                        amplitudes: amplitudes, detunes: detunes)
            let (all, tally) = detections(for: samples)
            let correct = tally[expected] ?? 0
            let total = all.count
            guard let winner = tally.max(by: { $0.value < $1.value })?.key else {
                XCTFail("\(expected.name): nothing detected from a sloppy strum")
                continue
            }
            XCTAssertEqual(winner, expected,
                "\(expected.name): majority was \(winner.name) — \(correct)/\(total) correct, tally \(Dictionary(uniqueKeysWithValues: tally.map { ($0.key.name, $0.value) }))")
            // No foreign chord should hold the output for a UI-visible streak.
            var worstRun = 0, run = 0
            var runChord: Chord?
            for (chord, _) in all {
                if chord == expected { run = 0; runChord = nil }
                else if chord == runChord { run += 1; worstRun = max(worstRun, run) }
                else { runChord = chord; run = 1; worstRun = max(worstRun, run) }
            }
            XCTAssertLessThan(worstRun, 10,
                "\(expected.name): a foreign chord held for \(worstRun) consecutive frames — tally \(Dictionary(uniqueKeysWithValues: tally.map { ($0.key.name, $0.value) }))")
        }
    }

    /// A chord should be reported reasonably quickly after the strum starts,
    /// not only after seconds of accumulation — the fretboard/practice flows
    /// require `chordConfirmationsNeeded` (10) consecutive matching frames.
    func testStrummedChordDetectedWithinHalfASecond() {
        for (expected, frequencies) in Self.openVoicings {
            let samples = strummedChord(frequencies: frequencies, duration: 0.5)
            let (all, tally) = detections(for: samples)
            let correct = tally[expected] ?? 0
            XCTAssertGreaterThanOrEqual(correct, 10,
                "\(expected.name): only \(correct) matching frames in 0.5 s (need 10 consecutive for the UI to confirm); all detections: \(Dictionary(uniqueKeysWithValues: tally.map { ($0.key.name, $0.value) })), total \(all.count)")
        }
    }
}
