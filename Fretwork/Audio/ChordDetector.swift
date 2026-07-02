import Foundation

/// A detected chord from the audio input.
nonisolated
struct DetectedChord: Sendable, Hashable {
    let chord: Chord
    /// Confidence score in [0, 1] — higher means stronger match.
    let confidence: Double
    let timestamp: TimeInterval
}

/// Abstraction over a real-time chord detection source.
///
/// Parallel to `PitchDetector` but for polyphonic input. The default
/// implementation is `LiveChordDetector` (FFT chromagram + template matching).
nonisolated
protocol ChordDetector: AnyObject, Sendable {
    var isRunning: Bool { get }

    func start() throws
    func stop()

    /// Set this *before* calling `start()`. Invoked off the main actor —
    /// hop to `@MainActor` in the closure if updating SwiftUI state.
    var onChord: (@Sendable (DetectedChord?) -> Void)? { get set }
}

/// Mock for previews and tests.
final class MockChordDetector: ChordDetector, @unchecked Sendable {
    var isRunning: Bool = false
    var onChord: (@Sendable (DetectedChord?) -> Void)?
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}
