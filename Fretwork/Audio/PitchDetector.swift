import Foundation

/// A single pitch reading from the audio input.
///
/// `amplitude` is on a normalized [0, 1]-ish scale. `frequency` may be
/// 0 or NaN when the detector has no signal — consumers must guard.
nonisolated
struct DetectedPitch: Sendable, Hashable {
    let frequency: Double
    let amplitude: Double
    let timestamp: TimeInterval
}

extension DetectedPitch {
    /// Shared default for the `amplitudeThreshold` gate used by every
    /// pitch-consuming ViewModel (Tuner, Fretboard, FlashCards, Practice).
    /// Below this RMS, a reading is treated as silence and dropped.
    ///
    /// Matches `ChordAnalyzer.amplitudeThreshold` (0.02) — the previous
    /// 0.05 default was more than double that for the same underlying RMS
    /// signal, and was cutting out real plucks on thinner strings (D, G,
    /// B, high E) whose energy is comparable to low E/A. See
    /// `PitchAnalyzerTests` for the diagnostic that confirmed YIN itself
    /// is accurate across the guitar range and RMS doesn't depend on
    /// frequency — the fixed threshold was simply too high.
    static let defaultAmplitudeThreshold: Double = 0.02
}

/// Abstraction over a real-time pitch source.
///
/// The default implementation is `LivePitchDetector` (Core Audio HAL-backed);
/// `MockPitchDetector` provides a scripted stream for previews and tests.
nonisolated
protocol PitchDetector: AnyObject, Sendable {
    var isRunning: Bool { get }

    /// Begin streaming detected pitches. Throws if the engine can't start
    /// (e.g. no audio input device, denied permission upstream).
    func start() throws

    /// Stop streaming. Safe to call when not running.
    func stop()

    /// Set this *before* calling `start()`. Invoked off the main actor —
    /// if you need to update SwiftUI state, hop with `Task { @MainActor in … }`.
    var onPitch: (@Sendable (DetectedPitch) -> Void)? { get set }
}

enum PitchDetectorError: Error, LocalizedError {
    case noAudioInput
    case engineFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noAudioInput:
            "No audio input device is available. Plug in your interface and check System Settings → Sound."
        case .engineFailed(let underlying):
            "Audio engine failed to start: \(underlying.localizedDescription)"
        }
    }
}
