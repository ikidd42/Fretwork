import Foundation
import QuartzCore

/// A pitch detector that emits a programmable sequence of pitches.
///
/// Useful for SwiftUI previews and unit tests so nothing has to plug in a guitar
/// to verify UI behavior. The `LivePitchDetector` is the production implementation.
///
/// `nonisolated` so its DispatchQueue-based timer callback compiles cleanly under
/// the project's default-MainActor isolation.
nonisolated
final class MockPitchDetector: PitchDetector, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MockPitchDetector")
    private var timer: DispatchSourceTimer?
    private var index = 0

    /// Sequence of pitches emitted in order, looping.
    var script: [DetectedPitch]
    /// Time between emitted pitches.
    var interval: TimeInterval

    private(set) var isRunning: Bool = false
    var onPitch: (@Sendable (DetectedPitch) -> Void)?

    init(script: [DetectedPitch] = MockPitchDetector.defaultScript, interval: TimeInterval = 0.05) {
        self.script = script
        self.interval = interval
    }

    func start() throws {
        guard !isRunning else { return }
        isRunning = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.script.isEmpty else { return }
            let item = self.script[self.index % self.script.count]
            self.index += 1
            // Stamp each emission with the current time so amplitude smoothing
            // in the UI behaves as it would in production.
            let stamped = DetectedPitch(
                frequency: item.frequency,
                amplitude: item.amplitude,
                timestamp: CACurrentMediaTime()
            )
            self.onPitch?(stamped)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }
}

extension MockPitchDetector {
    /// A meandering A4 ± 30 cents — feels like a tuner being slowly bent into pitch.
    static let defaultScript: [DetectedPitch] = {
        let base = 440.0
        return (0..<60).map { i in
            let cents = sin(Double(i) * 0.2) * 30
            let f = base * pow(2, cents / 1200)
            return DetectedPitch(frequency: f, amplitude: 0.4, timestamp: 0)
        }
    }()
}
