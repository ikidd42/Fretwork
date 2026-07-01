import Foundation
import Observation

/// User-facing audio preferences: input/output device choices, whether to
/// monitor the signal, and at what gain.
///
/// Persisted to `UserDefaults`. SwiftUI views read this directly (it's
/// `@Observable`); they should call the mutating methods on it rather than
/// poking the controller, so persistence and the audio engine stay in sync.
@MainActor
@Observable
final class AudioSettings {

    // MARK: - Public state

    private(set) var inputDeviceID: String?
    private(set) var outputDeviceID: String?
    private(set) var isMonitoringEnabled: Bool
    private(set) var monitorGain: Double

    // MARK: - Dependencies

    private weak var controller: (any AudioDeviceController)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.inputDeviceID = defaults.string(forKey: Keys.inputDeviceID)
        self.outputDeviceID = defaults.string(forKey: Keys.outputDeviceID)
        self.isMonitoringEnabled = defaults.bool(forKey: Keys.isMonitoringEnabled)
        self.monitorGain = (defaults.object(forKey: Keys.monitorGain) as? Double) ?? 1.0
    }

    // MARK: - Binding

    /// Connect to the audio controller and push current settings into it.
    /// Idempotent — safe to call again if the controller is recreated.
    func bind(controller: any AudioDeviceController) {
        self.controller = controller

        // Apply persisted device choices best-effort. If a device is gone
        // (interface unplugged since last launch) we skip it rather than
        // refusing to start; the user re-picks from the popover.
        if let id = inputDeviceID,
           controller.availableInputDevices.contains(where: { $0.id == id }) {
            try? controller.setInputDevice(id: id)
        }
        if let id = outputDeviceID,
           controller.availableOutputDevices.contains(where: { $0.id == id }) {
            try? controller.setOutputDevice(id: id)
        }

        controller.setMonitoring(enabled: isMonitoringEnabled, gain: monitorGain)
    }

    // MARK: - Mutators

    func setInputDevice(id: String) {
        inputDeviceID = id
        defaults.set(id, forKey: Keys.inputDeviceID)
        do {
            try controller?.setInputDevice(id: id)
        } catch {
            // TODO: surface through a banner. Logged silently for now.
        }
    }

    func setOutputDevice(id: String) {
        outputDeviceID = id
        defaults.set(id, forKey: Keys.outputDeviceID)
        do {
            try controller?.setOutputDevice(id: id)
        } catch {
            // TODO: surface through a banner. Logged silently for now.
        }
    }

    func setMonitoring(enabled: Bool) {
        isMonitoringEnabled = enabled
        defaults.set(enabled, forKey: Keys.isMonitoringEnabled)
        controller?.setMonitoring(enabled: enabled, gain: monitorGain)
    }

    func setMonitorGain(_ gain: Double) {
        monitorGain = gain
        defaults.set(gain, forKey: Keys.monitorGain)
        controller?.setMonitoring(enabled: isMonitoringEnabled, gain: gain)
    }

    // MARK: - Convenience for views

    /// Snapshot of devices to display in pickers. Recomputed each access so a
    /// freshly-plugged interface shows up without an explicit refresh.
    var availableInputDevices: [AudioDevice] {
        controller?.availableInputDevices ?? []
    }

    var availableOutputDevices: [AudioDevice] {
        controller?.availableOutputDevices ?? []
    }

    private enum Keys {
        static let inputDeviceID       = "audio.inputDeviceID"
        static let outputDeviceID      = "audio.outputDeviceID"
        static let isMonitoringEnabled = "audio.isMonitoringEnabled"
        static let monitorGain         = "audio.monitorGain"
    }
}
