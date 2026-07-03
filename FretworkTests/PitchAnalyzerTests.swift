import XCTest
import AVFoundation
@testable import Fretwork

/// Feeds synthesized guitar-string signals through `PitchAnalyzer` in the
/// same 128-frame chunks the HAL IOProc delivers (see
/// `LivePitchDetector.handleHALInput`), to isolate whether the "D/high E
/// don't register" bug is in YIN itself or in the amplitude gate that sits
/// in front of it in every ViewModel.
final class PitchAnalyzerTests: XCTestCase {

    private let sampleRate: Double = 48_000
    private let chunkSize = 128

    /// Standard tuning open-string frequencies (Hz).
    private let openStrings: [(name: String, hz: Double)] = [
        ("E2", 82.41),
        ("A2", 110.00),
        ("D3", 146.83),
        ("G3", 196.00),
        ("B3", 246.94),
        ("E4", 329.63),
    ]

    // MARK: - Signal generation

    private func format() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    /// Pure sine wave at constant amplitude.
    private func pureSine(frequency: Double, amplitude: Float, duration: Double) -> [Float] {
        let n = Int(sampleRate * duration)
        return (0..<n).map { i in
            amplitude * Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
    }

    /// Harmonic-rich plucked-string approximation: fundamental + 2nd/3rd
    /// harmonics under an exponential decay envelope.
    private func harmonicPluck(fundamental: Double, peakAmplitude: Float, duration: Double) -> [Float] {
        let n = Int(sampleRate * duration)
        let decayPerSecond = 3.0
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let envelope = exp(-t * decayPerSecond)
            let h1 = sin(2 * .pi * fundamental * t)
            let h2 = 0.5 * sin(2 * .pi * fundamental * 2 * t)
            let h3 = 0.25 * sin(2 * .pi * fundamental * 3 * t)
            return peakAmplitude * Float((h1 + h2 + h3) / 1.75 * envelope)
        }
    }

    /// Splits samples into 128-frame `AVAudioPCMBuffer`s, mirroring the HAL
    /// IOProc's delivery granularity.
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

    private func cents(detected: Double, expected: Double) -> Double {
        1200 * log2(detected / expected)
    }

    // MARK: - YIN accuracy: pure sines

    /// If YIN is accurate across the whole guitar range at a loud, clean
    /// amplitude, the analyzer itself is not the bug.
    func testPureSineDetectedWithinAFewCentsAcrossOpenStrings() {
        for string in openStrings {
            let analyzer = PitchAnalyzer()
            let samples = pureSine(frequency: string.hz, amplitude: 0.3, duration: 0.3)
            var lastResult: (frequency: Double, amplitude: Double)?
            for buffer in chunk(samples) {
                if let result = analyzer.analyze(buffer) {
                    lastResult = result
                }
            }
            guard let result = lastResult else {
                XCTFail("\(string.name): analyzer never produced a result")
                continue
            }
            let error = cents(detected: result.frequency, expected: string.hz)
            XCTAssertLessThan(abs(error), 5,
                "\(string.name): detected \(result.frequency) Hz vs expected \(string.hz) Hz (\(error) cents)")
        }
    }

    /// Same as above but at a quiet amplitude, to check YIN doesn't degrade
    /// for thin strings before amplitude alone would explain a miss.
    func testPureSineDetectedWithinAFewCentsAtLowAmplitude() {
        for string in openStrings {
            let analyzer = PitchAnalyzer()
            let samples = pureSine(frequency: string.hz, amplitude: 0.02, duration: 0.3)
            var lastResult: (frequency: Double, amplitude: Double)?
            for buffer in chunk(samples) {
                if let result = analyzer.analyze(buffer) {
                    lastResult = result
                }
            }
            guard let result = lastResult else {
                XCTFail("\(string.name): analyzer never produced a result at low amplitude")
                continue
            }
            let error = cents(detected: result.frequency, expected: string.hz)
            XCTAssertLessThan(abs(error), 10,
                "\(string.name): detected \(result.frequency) Hz vs expected \(string.hz) Hz (\(error) cents)")
        }
    }

    // MARK: - YIN accuracy: harmonic-rich decaying plucks

    func testHarmonicPluckDetectedWithinAFewCentsAcrossOpenStrings() {
        for string in openStrings {
            let analyzer = PitchAnalyzer()
            let samples = harmonicPluck(fundamental: string.hz, peakAmplitude: 0.3, duration: 0.5)
            var results: [(frequency: Double, amplitude: Double)] = []
            for buffer in chunk(samples) {
                if let result = analyzer.analyze(buffer) {
                    results.append(result)
                }
            }
            // Look at readings while the pluck is still loud (early in decay),
            // where a real detector would be expected to lock on.
            let strong = results.filter { $0.amplitude > 0.05 }
            guard let sample = strong.first else {
                XCTFail("\(string.name): no reading ever exceeded RMS 0.05 during a loud pluck")
                continue
            }
            let error = cents(detected: sample.frequency, expected: string.hz)
            XCTAssertLessThan(abs(error), 15,
                "\(string.name): detected \(sample.frequency) Hz vs expected \(string.hz) Hz (\(error) cents)")
        }
    }

    // MARK: - RMS gate diagnostic

    /// Reproduces the reported symptom: measures the RMS `PitchAnalyzer`
    /// reports for each open string at matched pluck amplitudes, and
    /// compares against the ViewModels' shared `amplitudeThreshold` (0.05).
    /// If RMS comes back essentially frequency-independent for a matched
    /// input amplitude, that confirms the gate — not YIN — is the bug: real
    /// plucks on thinner strings simply produce less energy and a fixed
    /// 0.05 threshold cuts them out.
    func testRMSAtMatchedAmplitudeIsFrequencyIndependent() {
        let amplitudeThreshold = 0.05 // mirrors TunerViewModel.amplitudeThreshold et al.
        let peakAmplitude: Float = 0.15 // a moderate, not-loud pluck

        var rmsByString: [String: Double] = [:]
        for string in openStrings {
            let analyzer = PitchAnalyzer()
            let samples = harmonicPluck(fundamental: string.hz, peakAmplitude: peakAmplitude, duration: 0.3)
            var peakRMS: Double = 0
            for buffer in chunk(samples) {
                if let result = analyzer.analyze(buffer) {
                    peakRMS = max(peakRMS, result.amplitude)
                }
            }
            rmsByString[string.name] = peakRMS
        }

        // The RMS values should all be in the same ballpark for a matched
        // input amplitude, regardless of fundamental frequency.
        let values = Array(rmsByString.values)
        let maxRMS = values.max() ?? 0
        let minRMS = values.min() ?? 0
        XCTAssertLessThan(maxRMS - minRMS, 0.03,
            "RMS should not vary wildly by string for matched input amplitude: \(rmsByString)")

        // Document whether this synthetic peak amplitude clears the gate —
        // informs whether a lower `amplitudeThreshold` alone would fix the
        // reported bug, independent of any real-world string energy gap.
        for (name, rms) in rmsByString.sorted(by: { $0.key < $1.key }) {
            XCTAssertGreaterThan(rms, 0,
                "\(name): expected a non-zero RMS reading")
            // Informational: not asserted pass/fail — surfaces in failure
            // messages above if the gate comparison ever needs revisiting.
            _ = rms > amplitudeThreshold
        }
    }

    // MARK: - Gate fix regression

    /// The bug: a fixed 0.05 `amplitudeThreshold` (duplicated across every
    /// pitch ViewModel) was gating out real, harmonic-rich plucks on the
    /// thinner strings. This reproduces a moderate pluck — much quieter
    /// than the "loud" 0.3-peak fixture above — that cleared YIN fine but
    /// would have been silently dropped by the old threshold.
    func testModeratePluckClearsNewThresholdButNotOldOne() {
        let oldThreshold = 0.05
        let newThreshold = DetectedPitch.defaultAmplitudeThreshold
        XCTAssertLessThan(newThreshold, oldThreshold,
            "regression fixture assumes the new default is more sensitive than the old 0.05")

        for string in openStrings {
            let analyzer = PitchAnalyzer()
            let samples = harmonicPluck(fundamental: string.hz, peakAmplitude: 0.08, duration: 0.3)
            var peakRMS: Double = 0
            for buffer in chunk(samples) {
                if let result = analyzer.analyze(buffer) {
                    peakRMS = max(peakRMS, result.amplitude)
                }
            }
            XCTAssertGreaterThan(peakRMS, newThreshold,
                "\(string.name): moderate pluck (RMS \(peakRMS)) should clear the new gate (\(newThreshold))")
            XCTAssertLessThan(peakRMS, oldThreshold,
                "\(string.name): fixture should be quiet enough that the old gate (\(oldThreshold)) would have dropped it (RMS \(peakRMS))")
        }
    }

    /// The two gates diverge *deliberately*: a single string is meaningful
    /// down to near-silence (pitch gate 0.02), but a chord's identity dies
    /// earlier in the decay — its single-string third fades first and the
    /// residue misreads as sus chords — so the chord gate sits higher.
    /// This test pins the relationship so neither drifts by accident
    /// (an unexplained 2.5× divergence here was the original tuner bug).
    func testChordGateIsStricterThanPitchGate() {
        let chordAnalyzer = ChordAnalyzer()
        XCTAssertGreaterThan(Double(chordAnalyzer.amplitudeThreshold),
                             DetectedPitch.defaultAmplitudeThreshold)
        XCTAssertLessThanOrEqual(Double(chordAnalyzer.amplitudeThreshold),
                                 DetectedPitch.defaultAmplitudeThreshold * 3,
            "chord gate drifted far above the pitch gate — revisit deliberately")
    }
}
