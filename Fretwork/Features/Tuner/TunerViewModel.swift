import Foundation
import Observation

/// Drives the tuner UI from a `PitchDetector`.
///
/// Behavior:
/// - Below an amplitude threshold, readings are ignored — the display freezes
///   instead of swinging wildly when no note is being played.
/// - Frequency is smoothed with an exponential moving average so the display
///   doesn't jitter on every detector callback.
/// - When the input frequency jumps by more than ~70 cents (likely a new note,
///   not jitter), smoothing resets so the display tracks the new note quickly.
@MainActor
@Observable
final class TunerViewModel {

    // MARK: - Output state (read by SwiftUI)

    private(set) var permission: AudioPermission.Status = .undetermined
    private(set) var isListening: Bool = false
    private(set) var lastError: String?

    /// Smoothed frequency from above-threshold readings. `nil` while we have no signal.
    private(set) var smoothedFrequency: Double?

    var smoothedNote: Note? {
        guard let f = smoothedFrequency, let r = Note.nearest(to: f) else { return nil }
        return r.note
    }

    var smoothedCentsOff: Double {
        guard let f = smoothedFrequency, let r = Note.nearest(to: f) else { return 0 }
        return r.centsOff
    }

    var frequencyDisplay: String {
        guard let f = smoothedFrequency else { return "— Hz" }
        return String(format: "%.1f Hz", f)
    }

    // MARK: - Tunables

    /// Below this amplitude (detector's normalized scale) we treat the input as silence.
    /// Lower = more sensitive but more false positives from string noise / room hum.
    var amplitudeThreshold: Double = DetectedPitch.defaultAmplitudeThreshold

    /// Exponential smoothing factor in [0, 1). Higher = smoother / slower to react.
    var smoothing: Double = 0.6

    /// Lowest frequency we'll consider a valid musical reading (~ low B on a 7-string).
    var minFrequency: Double = 30

    /// Highest frequency we'll consider valid (high E + a few octaves of harmonics).
    var maxFrequency: Double = 4000

    // MARK: - Dependencies

    private let detector: any PitchDetector

    init(detector: any PitchDetector) {
        self.detector = detector
    }

    // MARK: - Lifecycle

    func start() async {
        permission = AudioPermission.current
        if permission == .undetermined {
            permission = await AudioPermission.request()
        }
        guard permission == .granted else { return }

        detector.onPitch = { [weak self] reading in
            // Detector callbacks fire off the main thread; hop before touching state.
            Task { @MainActor in
                self?.ingest(reading)
            }
        }

        do {
            try detector.start()
            isListening = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isListening = false
        }
    }

    func stop() {
        // Don't call detector.stop() — the detector is shared and stays
        // running across tab switches. Just reset local state.
        isListening = false
        smoothedFrequency = nil
    }

    // MARK: - Private

    private func ingest(_ reading: DetectedPitch) {
        guard reading.amplitude > amplitudeThreshold,
              reading.frequency.isFinite,
              reading.frequency > minFrequency,
              reading.frequency < maxFrequency
        else { return }

        if let current = smoothedFrequency {
            let ratio = reading.frequency / current
            // ~70-cent jump => treat as a new note, snap to it instead of lerping.
            if ratio > 1.04 || ratio < 0.96 {
                smoothedFrequency = reading.frequency
            } else {
                smoothedFrequency = current * smoothing + reading.frequency * (1 - smoothing)
            }
        } else {
            smoothedFrequency = reading.frequency
        }
    }
}
