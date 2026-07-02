import Foundation

/// Configuration surface for the real-time audio engine: which devices to
/// route input and output through, plus input monitoring.
///
/// Kept separate from `PitchDetector` so the simple "feed me pitches"
/// protocol stays small. `LivePitchDetector` conforms to both;
/// `MockPitchDetector` only implements `PitchDetector` — there's no real
/// device behind a scripted stream.
nonisolated
protocol AudioDeviceController: AnyObject {

    // MARK: - Input device

    /// Currently available input devices, sorted for display.
    var availableInputDevices: [AudioDevice] { get }

    /// UID of the currently active input device, if known.
    var currentInputDeviceID: String? { get }

    /// Switch to a different input. Restarts the engine if it was running so
    /// the new device takes effect immediately. Throws if the device can't be
    /// found or the engine fails to restart.
    func setInputDevice(id: String) throws

    // MARK: - Output device

    /// Currently available output devices, sorted for display.
    var availableOutputDevices: [AudioDevice] { get }

    /// UID of the currently active output device, if known.
    var currentOutputDeviceID: String? { get }

    /// Switch to a different output device. Same behavior as
    /// `setInputDevice` regarding engine restart.
    func setOutputDevice(id: String) throws

    // MARK: - Monitoring (input passthrough to the chosen output)

    /// Whether the input is currently being routed to the output.
    var isMonitoringEnabled: Bool { get }

    /// Linear gain applied to the monitored signal. `1.0` is unity; the UI
    /// allows up to `2.0` for quiet inputs. Above 1 increases feedback risk.
    var monitorGain: Double { get }

    /// Update both monitoring state and gain in one call. Cheap; can be invoked
    /// from a slider's `onChange`.
    func setMonitoring(enabled: Bool, gain: Double)
}
