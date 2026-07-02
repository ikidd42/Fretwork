import Foundation
import Accelerate
import AVFoundation

/// FFT-based chord detector for polyphonic guitar audio.
///
/// Pipeline:
/// 1. Accumulate samples into a sliding window (4096 samples ≈ 85 ms at 48 kHz)
/// 2. Apply a Hann window to reduce spectral leakage
/// 3. FFT → magnitude spectrum
/// 4. Map harmonics to a 12-bin chromagram (pitch class energy profile)
/// 5. Cosine similarity against chord templates → best match
///
/// The larger window (vs PitchAnalyzer's 2048) gives better frequency
/// resolution for separating chord tones — at 48 kHz each FFT bin spans
/// ~11.7 Hz, enough to distinguish adjacent notes in the guitar range.
///
/// `nonisolated` so it can run on the audio IO thread.
nonisolated
final class ChordAnalyzer: @unchecked Sendable {

    // MARK: - Configuration

    let windowSize: Int
    /// Minimum confidence to report a chord. Below this → no chord detected.
    var confidenceThreshold: Float = 0.65
    /// Minimum RMS amplitude to attempt analysis. Silence → no chord.
    var amplitudeThreshold: Float = 0.02

    // MARK: - FFT setup

    private let fftSetup: vDSP_DFT_Setup
    private let halfN: Int

    // MARK: - Preallocated buffers

    private var workBuffer: [Float]       // circular write buffer
    private var windowedBuffer: [Float]   // windowed snapshot for FFT
    private var hannWindow: [Float]       // precomputed Hann window
    private var realPart: [Float]         // FFT real output
    private var imagPart: [Float]         // FFT imaginary output
    private var magnitudes: [Float]       // magnitude spectrum
    private var chromagram: [Float]       // 12-bin pitch class energy
    private var peakFrequencies: [Double] // interpolated spectral peak freqs
    private var peakEnergies: [Float]     // energy per spectral peak

    private var writePosition: Int = 0
    private var samplesAccumulated: Int = 0

    // MARK: - Templates

    private let templates: [ChordTemplate]

    // MARK: - Temporal smoothing

    /// Exponential moving average of the chromagram across frames.
    /// Smooths out transients so chords are detected more stably.
    private var smoothedChromagram: [Float]
    private let chromaSmoothingFactor: Float = 0.7  // 0 = no smoothing, 1 = full memory

    // MARK: - Hysteresis

    /// The last reported chord. A new chord must beat it by `hysteresisMargin`
    /// in cosine similarity to replace it. Prevents flickering.
    private var lastReportedChord: Chord?
    private var lastReportedScore: Float = 0
    private let hysteresisMargin: Float = 0.04  // new chord must score 4% higher

    init(windowSize: Int = 4096) {
        self.windowSize = windowSize
        self.halfN = windowSize / 2

        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(windowSize),
            .FORWARD
        ) else {
            fatalError("Failed to create DFT setup for window size \(windowSize)")
        }
        self.fftSetup = setup

        self.workBuffer      = [Float](repeating: 0, count: windowSize)
        self.windowedBuffer  = [Float](repeating: 0, count: windowSize)
        self.hannWindow      = [Float](repeating: 0, count: windowSize)
        self.realPart        = [Float](repeating: 0, count: windowSize)
        self.imagPart        = [Float](repeating: 0, count: windowSize)
        self.magnitudes      = [Float](repeating: 0, count: halfN)
        self.chromagram      = [Float](repeating: 0, count: 12)
        self.smoothedChromagram = [Float](repeating: 0, count: 12)
        self.peakFrequencies = [Double](repeating: 0, count: Self.maxPeaks)
        self.peakEnergies    = [Float](repeating: 0, count: Self.maxPeaks)

        // Precompute Hann window
        vDSP_hann_window(&hannWindow, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

        // Build chord templates
        self.templates = ChordTemplate.buildAll()
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }

    /// Append new audio samples and, if the window is full, return the best
    /// matching chord (or nil if nothing passes the confidence threshold).
    func analyze(_ buffer: AVAudioPCMBuffer, sampleRate: Double) -> (chord: Chord, confidence: Double)? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let samples = channelData[0]

        // Append into circular buffer
        for i in 0..<frameLength {
            workBuffer[(writePosition + i) % windowSize] = samples[i]
        }
        writePosition = (writePosition + frameLength) % windowSize
        samplesAccumulated = min(samplesAccumulated + frameLength, windowSize)

        guard samplesAccumulated >= windowSize else { return nil }

        // Linearize circular → contiguous
        for i in 0..<windowSize {
            windowedBuffer[i] = workBuffer[(writePosition + i) % windowSize]
        }

        // RMS check — skip silent frames
        var rms: Float = 0
        vDSP_rmsqv(windowedBuffer, 1, &rms, vDSP_Length(windowSize))
        guard rms > amplitudeThreshold else {
            // Decay the smoothed chromagram toward zero during silence
            var decay: Float = 0.5
            vDSP_vsmul(smoothedChromagram, 1, &decay, &smoothedChromagram, 1, 12)
            return nil
        }

        // ── Step 1: Apply Hann window ──────────────────────────────────
        vDSP_vmul(windowedBuffer, 1, hannWindow, 1, &windowedBuffer, 1, vDSP_Length(windowSize))

        // ── Step 2: FFT ────────────────────────────────────────────────
        // Pack real signal into split complex format for DFT
        for i in 0..<windowSize {
            realPart[i] = windowedBuffer[i]
            imagPart[i] = 0
        }

        vDSP_DFT_Execute(fftSetup, realPart, imagPart, &realPart, &imagPart)

        // ── Step 3: Magnitude spectrum (first half only — symmetric) ───
        // |X[k]| = sqrt(re² + im²)
        realPart.withUnsafeMutableBufferPointer { re in
            imagPart.withUnsafeMutableBufferPointer { im in
                magnitudes.withUnsafeMutableBufferPointer { mag in
                    var split = DSPSplitComplex(
                        realp: re.baseAddress!,
                        imagp: im.baseAddress!
                    )
                    // vDSP_zvabs computes magnitudes from split complex
                    vDSP_zvabs(&split, 1, mag.baseAddress!, 1, vDSP_Length(halfN))
                }
            }
        }

        // ── Step 4: Build chromagram ───────────────────────────────────
        buildChromagram(sampleRate: sampleRate)

        // ── Step 5: Match against templates ────────────────────────────
        return matchChord()
    }

    /// Reset accumulated state — call when the audio stream restarts.
    func reset() {
        for i in 0..<windowSize { workBuffer[i] = 0 }
        writePosition = 0
        samplesAccumulated = 0
        for i in 0..<12 {
            smoothedChromagram[i] = 0
        }
        lastReportedChord = nil
        lastReportedScore = 0
    }

    // MARK: - Chromagram

    /// Maps FFT magnitudes into 12 pitch class energy bins.
    ///
    /// Finds local maxima (spectral peaks) and assigns each peak's energy to
    /// the pitch class of its **parabolically interpolated** frequency —
    /// not the bin center. This matters: at 48 kHz / 4096 the bins are
    /// ~11.7 Hz apart, wider than a semitone below ~330 Hz, so a low note
    /// straddling two bins (e.g. A3 at 220 Hz between bins at 210.9 and
    /// 222.7 Hz) would otherwise smear main-lobe energy into a *neighboring*
    /// pitch class (here G#) and systematically misclassify chords
    /// (majors read as maj7, etc.). Interpolation recovers the true peak
    /// frequency to sub-bin accuracy, the same way `PitchAnalyzer` refines τ.
    ///
    /// We focus on the guitar range (~70 Hz to ~2000 Hz) to avoid noise from
    /// very low rumble or high-frequency content that isn't musically relevant.
    private static let maxPeaks = 128

    /// Attenuation applied to peaks identified as overtones of a stronger
    /// lower peak. Not zero — a genuine unison with another string's
    /// harmonic keeps a foothold.
    private let harmonicAttenuation: Float = 0.15

    private func buildChromagram(sampleRate: Double) {
        // Reset chromagram bins
        for i in 0..<12 { chromagram[i] = 0 }

        let binResolution = sampleRate / Double(windowSize)

        // Focus on guitar fundamentals: ~70 Hz (drop D low) to ~2000 Hz.
        // Limiting the upper range reduces harmonic contamination that
        // causes confusion between chords sharing similar overtones.
        let minBin = max(2, Int(70.0 / binResolution))
        let maxBin = min(halfN - 2, Int(2000.0 / binResolution))
        guard maxBin > minBin else { return }

        // ── Pass 1: collect spectral peaks ─────────────────────────────
        var peakCount = 0
        for k in minBin...maxBin {
            let mag = magnitudes[k]
            // Local maximum test (>= on the right so plateaus register once).
            guard mag > magnitudes[k - 1], mag >= magnitudes[k + 1], mag > 0 else { continue }
            guard peakCount < Self.maxPeaks else { break }

            // Parabolic interpolation around the peak for sub-bin frequency.
            let y1 = Double(magnitudes[k - 1])
            let y2 = Double(mag)
            let y3 = Double(magnitudes[k + 1])
            let denom = y1 - 2 * y2 + y3
            var refinedBin = Double(k)
            if denom != 0 {
                let delta = 0.5 * (y1 - y3) / denom
                if abs(delta) <= 1 { refinedBin += delta }
            }
            let frequency = refinedBin * binResolution
            guard frequency > 0 else { continue }

            // Sum energy across the peak's 3-bin neighborhood so a tone that
            // straddles two bins isn't undercounted, and weight by energy
            // (magnitude squared) to emphasize strong tones.
            peakFrequencies[peakCount] = frequency
            peakEnergies[peakCount] = Float(y1 * y1 + y2 * y2 + y3 * y3)
            peakCount += 1
        }

        // ── Pass 2: harmonic sieve, then accumulate pitch classes ──────
        // A peak sitting at ~3× the frequency of a comparably strong lower
        // peak is 3rd-harmonic overtone energy, not a played note — and it
        // lands a *fifth* above the source's pitch class, injecting a
        // phantom note (e.g. sustained Em: the B strings' 3rd harmonic is
        // F#, and {E, B, F#} reads as Bsus4 whenever the single G string is
        // weaker than the doubled E/B strings). Even harmonics (2×, 4×) are
        // deliberately NOT sieved: they fold onto the same pitch class as
        // their fundamental, so they add legitimate reinforcement — octave-
        // doubled roots are what anchor open-voicing classification.
        for i in 0..<peakCount {
            let f = peakFrequencies[i]
            var isOvertone = false
            let sub = f / 3
            for j in 0..<peakCount where j != i {
                // ±60 cents absorbs detuning, string inharmonicity
                // (stiff strings run harmonics slightly sharp), and
                // interpolation error.
                let cents = abs(1200 * log2(peakFrequencies[j] / sub))
                if cents < 60, peakEnergies[j] >= peakEnergies[i] * 0.5 {
                    isOvertone = true
                    break
                }
            }

            // Map frequency to pitch class using 12-TET
            // semitones from A4 (440 Hz) = 12 × log2(f/440)
            let semitones = 12.0 * log2(f / 440.0)
            let pitchClassIndex = ((Int(round(semitones)) % 12) + 12 + 9) % 12
            // +9 because A is pitch class 9 (counting from C=0)

            let energy = isOvertone ? peakEnergies[i] * harmonicAttenuation : peakEnergies[i]
            chromagram[pitchClassIndex] += energy
        }

        // Compress energy → amplitude scale. Raw energy (mag²) quadratically
        // over-weights doubled strings and octave-reinforced roots, so a
        // softly struck third (one string, ~10-15% of the peak bin) hovers
        // at the noise gate and flickers in and out as harmonic beating
        // modulates the peak — visible as A wavering to Esus4 mid-decay.
        // sqrt preserves ordering while keeping weak chord tones in play.
        for i in 0..<12 { chromagram[i] = chromagram[i].squareRoot() }

        // Normalize chromagram to [0, 1]
        var maxVal: Float = 0
        vDSP_maxv(chromagram, 1, &maxVal, 12)
        if maxVal > 0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(chromagram, 1, &scale, &chromagram, 1, 12)
        }

        // Noise gate: zero out bins below 10% of the peak. This keeps
        // only the strongest pitch classes, suppressing spectral leakage
        // and sympathetic string resonance that confuse template matching.
        // (Was 15% — too aggressive once the harmonic sieve cleaned up the
        // chromagram: a softly-struck third on a single string sits around
        // 10–15% of a doubled root's energy and was getting zeroed,
        // leaving {root, fifth} to misread as a sus chord.)
        var peakVal: Float = 0
        vDSP_maxv(chromagram, 1, &peakVal, 12)
        let gate = peakVal * 0.10
        for i in 0..<12 {
            if chromagram[i] < gate { chromagram[i] = 0 }
        }

        // Re-normalize after gating
        var maxAfterGate: Float = 0
        vDSP_maxv(chromagram, 1, &maxAfterGate, 12)
        if maxAfterGate > 0 {
            var s = 1.0 / maxAfterGate
            vDSP_vsmul(chromagram, 1, &s, &chromagram, 1, 12)
        }

        // Apply temporal smoothing (EMA)
        for i in 0..<12 {
            smoothedChromagram[i] = chromaSmoothingFactor * smoothedChromagram[i]
                                  + (1 - chromaSmoothingFactor) * chromagram[i]
        }
    }

    // MARK: - Template matching

    /// Find the best matching chord template via cosine similarity,
    /// with hysteresis to prevent flickering between similar chords.
    private func matchChord() -> (chord: Chord, confidence: Double)? {
        var bestChord: Chord?
        var bestScore: Float = -1
        var secondBestScore: Float = -1

        for template in templates {
            let score = cosineSimilarity(smoothedChromagram, template.profile)
            if score > bestScore {
                secondBestScore = bestScore
                bestScore = score
                bestChord = template.chord
            } else if score > secondBestScore {
                secondBestScore = score
            }
        }

        guard let chord = bestChord, bestScore >= confidenceThreshold else {
            lastReportedChord = nil
            lastReportedScore = 0
            return nil
        }

        // Require the best match to be clearly ahead of the runner-up.
        // If the gap is too small, the classification is ambiguous.
        let gap = bestScore - secondBestScore
        guard gap > 0.02 else {
            // Ambiguous — stick with whatever was last reported.
            if let last = lastReportedChord {
                // Re-score the last chord to see if it's still viable.
                if let tpl = templates.first(where: { $0.chord == last }) {
                    let lastScore = cosineSimilarity(smoothedChromagram, tpl.profile)
                    if lastScore >= confidenceThreshold {
                        return (last, Double(lastScore))
                    }
                }
            }
            return nil
        }

        // Hysteresis: if we already have a chord, the new one must beat it
        // by a margin to take over. This prevents oscillation.
        if let last = lastReportedChord, chord != last {
            if let tpl = templates.first(where: { $0.chord == last }) {
                let lastScore = cosineSimilarity(smoothedChromagram, tpl.profile)
                if bestScore < lastScore + hysteresisMargin {
                    // Current chord still competitive — keep it.
                    lastReportedScore = lastScore
                    return (last, Double(lastScore))
                }
            }
        }

        lastReportedChord = chord
        lastReportedScore = bestScore
        return (chord, Double(bestScore))
    }

    /// Cosine similarity between two 12-element vectors.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, 12)
        vDSP_dotpr(a, 1, a, 1, &normA, 12)
        vDSP_dotpr(b, 1, b, 1, &normB, 12)

        let denom = sqrt(normA * normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
    }
}

// MARK: - Chord templates

/// A chromagram template for a specific chord. Built from the chord's pitch
/// classes with harmonic weighting to match real guitar spectra.
///
/// `nonisolated` — built and matched on the audio IO thread.
nonisolated
struct ChordTemplate {
    let chord: Chord
    /// 12-element normalized profile: energy expected in each pitch class bin.
    let profile: [Float]

    /// Build templates for all common guitar chords across all 12 roots.
    static func buildAll() -> [ChordTemplate] {
        let qualities: [ChordQuality] = [
            .major, .minor, .dominant7, .major7, .minor7,
            .diminished, .augmented, .suspended2, .suspended4,
            .minor7b5, .diminished7, .minorMajor7
        ]

        var templates: [ChordTemplate] = []

        for root in PitchClass.allCases {
            for quality in qualities {
                let chord = Chord(root: root, quality: quality)
                let profile = buildProfile(for: chord)
                templates.append(ChordTemplate(chord: chord, profile: profile))
            }
        }

        return templates
    }

    /// Create a 12-bin chromagram profile for a chord.
    ///
    /// Uses only the fundamental chord tones with a slight boost to the root.
    /// Previous approach included harmonic overtones (3rd, 5th harmonics)
    /// which spread energy into neighboring pitch class bins, making
    /// unrelated chords (e.g. Amaj7 vs A#m7b5) score nearly identically.
    /// Cleaner templates = more discriminative matching.
    private static func buildProfile(for chord: Chord) -> [Float] {
        var profile = [Float](repeating: 0, count: 12)

        let pcs = chord.pitchClasses
        for (i, pc) in pcs.enumerated() {
            let bin = pc.rawValue
            if i == 0 {
                // Root gets extra weight — it's the strongest note in a
                // strummed guitar chord and anchors the classification.
                profile[bin] = 1.0
            } else {
                profile[bin] = 0.7
            }
        }

        // Normalize so the max bin is 1.0
        var maxVal: Float = 0
        for v in profile { maxVal = max(maxVal, v) }
        if maxVal > 0 {
            for i in 0..<12 { profile[i] /= maxVal }
        }

        return profile
    }
}
