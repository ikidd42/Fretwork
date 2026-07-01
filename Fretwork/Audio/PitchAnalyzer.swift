import Foundation
import Accelerate
import AVFoundation

/// YIN-based pitch detector for monophonic audio.
///
/// Implements the algorithm from de Cheveigné & Kawahara, *YIN, a fundamental
/// frequency estimator for speech and music* (JASA, 2002). Maintains a
/// sliding window of recent samples and on each `analyze` call runs:
///
/// 1. Difference function `d(τ) = Σ (x[i] - x[i+τ])²`
/// 2. Cumulative mean normalized difference `d'(τ)` — robust against
///    octave errors that plain autocorrelation makes
/// 3. Absolute threshold to pick the first local minimum below a confidence cutoff
/// 4. Parabolic interpolation around the chosen `τ` for sub-sample accuracy
///
/// `nonisolated` so it can be driven from the audio thread under the
/// project's default-MainActor isolation.
nonisolated
final class PitchAnalyzer: @unchecked Sendable {

    /// Length of the analysis window. 2048 samples at 48 kHz spans ~43 ms,
    /// roughly 3.5 cycles of the guitar's low E (82 Hz) — enough for a
    /// stable difference function without making the loop expensive.
    let windowSize: Int

    /// YIN absolute threshold for the period detection. The paper recommends
    /// 0.10–0.15. Lower → more confident match required. Higher → more
    /// permissive but more octave errors.
    var threshold: Float = 0.15

    // MARK: - Storage (preallocated to avoid audio-thread allocations)

    private var workBuffer: [Float]      // circular write buffer
    private var linearBuffer: [Float]    // linearized snapshot for analysis
    private var diffWork: [Float]        // scratch for vDSP_vsub output
    private var d: [Float]               // difference function values
    private var dPrime: [Float]          // cumulative mean normalized values

    private var writePosition: Int = 0
    private var samplesAccumulated: Int = 0

    init(windowSize: Int = 2048) {
        self.windowSize = windowSize
        self.workBuffer   = [Float](repeating: 0, count: windowSize)
        self.linearBuffer = [Float](repeating: 0, count: windowSize)
        self.diffWork     = [Float](repeating: 0, count: windowSize)
        self.d            = [Float](repeating: 0, count: windowSize)
        self.dPrime       = [Float](repeating: 1, count: windowSize)
    }

    /// Append the buffer's samples and, if the window is full, return the
    /// estimated fundamental frequency (Hz) and RMS amplitude.
    func analyze(_ buffer: AVAudioPCMBuffer) -> (frequency: Double, amplitude: Double)? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let sampleRate = buffer.format.sampleRate
        let samples = channelData[0]

        // Append new samples into the circular buffer.
        for i in 0..<frameLength {
            workBuffer[(writePosition + i) % windowSize] = samples[i]
        }
        writePosition = (writePosition + frameLength) % windowSize
        samplesAccumulated = min(samplesAccumulated + frameLength, windowSize)

        guard samplesAccumulated >= windowSize else { return nil }

        // Linearize circular → contiguous so vDSP can work over it.
        for i in 0..<windowSize {
            linearBuffer[i] = workBuffer[(writePosition + i) % windowSize]
        }

        // RMS for amplitude (and for the caller's silence threshold).
        var rms: Float = 0
        vDSP_rmsqv(linearBuffer, 1, &rms, vDSP_Length(windowSize))

        // Range of plausible fundamental periods.
        let minTau = max(2, Int(sampleRate / 1500))   // 1500 Hz upper bound
        let maxTau = min(windowSize / 2, Int(sampleRate / 70))  // 70 Hz lower bound
        guard maxTau > minTau else { return nil }

        // ── Step 1: d(τ) = Σ (x[i] - x[i+τ])² for τ in 1...maxTau
        let analysisLength = windowSize - maxTau
        linearBuffer.withUnsafeMutableBufferPointer { lin in
            diffWork.withUnsafeMutableBufferPointer { diff in
                for tau in 1...maxTau {
                    vDSP_vsub(
                        lin.baseAddress!, 1,
                        lin.baseAddress!.advanced(by: tau), 1,
                        diff.baseAddress!, 1,
                        vDSP_Length(analysisLength)
                    )
                    var sum: Float = 0
                    vDSP_dotpr(
                        diff.baseAddress!, 1,
                        diff.baseAddress!, 1,
                        &sum,
                        vDSP_Length(analysisLength)
                    )
                    d[tau] = sum
                }
            }
        }

        // ── Step 2: cumulative mean normalized difference
        // d'(τ) = d(τ) · τ / Σ d(j) for j = 1..τ
        dPrime[0] = 1
        var runningSum: Float = 0
        for tau in 1...maxTau {
            runningSum += d[tau]
            dPrime[tau] = runningSum > 0 ? d[tau] * Float(tau) / runningSum : 1
        }

        // ── Step 3: find the first τ in [minTau, maxTau] where d'(τ) < threshold,
        // then walk down to the local minimum. Fall back to the global min.
        var bestTau = -1
        var tau = minTau
        while tau <= maxTau {
            if dPrime[tau] < threshold {
                while tau + 1 <= maxTau && dPrime[tau + 1] < dPrime[tau] {
                    tau += 1
                }
                bestTau = tau
                break
            }
            tau += 1
        }
        if bestTau < 0 {
            var minVal: Float = .infinity
            for t in minTau...maxTau where dPrime[t] < minVal {
                minVal = dPrime[t]
                bestTau = t
            }
        }
        guard bestTau > 0, bestTau < maxTau else { return nil }

        // ── Step 4: parabolic interpolation for sub-sample τ
        var refinedTau = Double(bestTau)
        if bestTau > 1 {
            let y1 = Double(dPrime[bestTau - 1])
            let y2 = Double(dPrime[bestTau])
            let y3 = Double(dPrime[bestTau + 1])
            let denom = y1 - 2 * y2 + y3
            if denom != 0 {
                refinedTau = Double(bestTau) + 0.5 * (y1 - y3) / denom
            }
        }

        return (sampleRate / refinedTau, Double(rms))
    }

    /// Reset accumulated state. Call when the input device or stream
    /// changes so stale samples don't leak into the next window.
    func reset() {
        for i in 0..<windowSize { workBuffer[i] = 0 }
        writePosition = 0
        samplesAccumulated = 0
    }
}
