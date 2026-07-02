import Foundation
import AVFoundation

/// A drum pattern defined as a grid of hits across a measure.
///
/// Each `DrumPattern` contains tracks for kick, snare, and hi-hat, where
/// each track is a `[Bool]` array of length `subdivisions` (typically 8 or 16).
/// `true` at position `i` means that instrument sounds on that subdivision.
struct DrumPattern: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Number of subdivisions per measure (e.g. 8 = eighth notes in 4/4).
    let subdivisions: Int
    /// Kick drum hits.
    let kick: [Bool]
    /// Snare drum hits.
    let snare: [Bool]
    /// Hi-hat hits.
    let hiHat: [Bool]

    /// Total number of beats (for display). Typically 4 for 4/4 time.
    var beats: Int { subdivisions / 2 }
}

// MARK: - Catalog

extension DrumPattern {

    static let basic4_4 = DrumPattern(
        id: "basic-4/4",
        name: "Basic Rock",
        subdivisions: 8,
        kick:  [true,  false, false, false, true,  false, false, false],
        snare: [false, false, true,  false, false, false, true,  false],
        hiHat: [true,  true,  true,  true,  true,  true,  true,  true ]
    )

    static let pop = DrumPattern(
        id: "pop",
        name: "Pop",
        subdivisions: 8,
        kick:  [true,  false, false, true,  true,  false, false, false],
        snare: [false, false, true,  false, false, false, true,  false],
        hiHat: [true,  true,  true,  true,  true,  true,  true,  true ]
    )

    static let shuffle = DrumPattern(
        id: "shuffle",
        name: "Shuffle",
        subdivisions: 8,
        kick:  [true,  false, false, false, true,  false, false, false],
        snare: [false, false, true,  false, false, false, true,  false],
        hiHat: [true,  false, true,  true,  false, true,  true,  false]
    )

    static let blues = DrumPattern(
        id: "blues",
        name: "Blues",
        subdivisions: 8,
        kick:  [true,  false, false, true,  false, false, true,  false],
        snare: [false, false, true,  false, false, true,  false, false],
        hiHat: [true,  true,  true,  true,  true,  true,  true,  true ]
    )

    static let bossaNova = DrumPattern(
        id: "bossa-nova",
        name: "Bossa Nova",
        subdivisions: 8,
        kick:  [true,  false, false, true,  false, false, true,  false],
        snare: [false, false, false, false, false, false, false, false],
        hiHat: [true,  false, true,  false, true,  false, true,  false]
    )

    static let funk = DrumPattern(
        id: "funk",
        name: "Funk",
        subdivisions: 16,
        kick:  [true,  false, false, false, false, false, true,  false, false, true,  false, false, false, false, false, false],
        snare: [false, false, false, false, true,  false, false, false, false, false, false, false, true,  false, false, false],
        hiHat: [true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true ]
    )

    static let catalog: [DrumPattern] = [
        .basic4_4, .pop, .shuffle, .blues, .bossaNova, .funk
    ]
}

// MARK: - Drum sound synthesizer

/// Generates short percussive drum sounds using synthesis (no samples needed).
///
/// Each drum is a combination of sine waves with rapid envelope decay.
/// Surprisingly convincing for practice purposes.
///
/// `nonisolated` — pure functions of no shared state, called from
/// `AudioMetronome`'s nonisolated control plane.
nonisolated
enum DrumSynthesizer {

    static let sampleRate: Double = 44100

    private static var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    /// Synthesize a kick drum: low sine sweep with fast decay.
    static func kick() -> AVAudioPCMBuffer {
        let duration = 0.15
        let frameCount = Int(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                       frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Frequency sweep from 150 Hz down to 50 Hz
            let freq = 150.0 * exp(-10.0 * t) + 50.0
            let phase = 2.0 * Double.pi * freq * t
            let envelope = Float(exp(-8.0 * t))
            data[i] = 0.8 * envelope * Float(sin(phase))
        }
        return buffer
    }

    /// Synthesize a snare drum: noise burst + body tone.
    static func snare() -> AVAudioPCMBuffer {
        let duration = 0.12
        let frameCount = Int(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                       frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Body: 200 Hz tone
            let body = Float(sin(2.0 * Double.pi * 200.0 * t)) * Float(exp(-20.0 * t))
            // Noise: white noise with fast decay
            let noise = Float.random(in: -1...1) * Float(exp(-15.0 * t))
            data[i] = 0.4 * body + 0.5 * noise
        }
        return buffer
    }

    /// Synthesize a hi-hat: filtered noise burst.
    static func hiHat() -> AVAudioPCMBuffer {
        let duration = 0.05
        let frameCount = Int(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                       frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        // Simple high-frequency noise with very fast decay
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let noise = Float.random(in: -1...1)
            // High-pass approximation: mix with a high-frequency tone
            let hiFreq = Float(sin(2.0 * Double.pi * 8000.0 * t))
            let envelope = Float(exp(-30.0 * t))
            data[i] = 0.3 * envelope * (noise * 0.6 + hiFreq * 0.4)
        }
        return buffer
    }
}
