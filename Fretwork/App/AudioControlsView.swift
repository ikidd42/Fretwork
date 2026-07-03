import SwiftUI

/// Compact audio settings UI. Designed to live inside a toolbar popover.
///
/// Bindings are constructed manually rather than via `@Bindable`'s `$` syntax,
/// because `AudioSettings` exposes its state read-only and routes mutations
/// through methods that also persist + push to the audio engine.
struct AudioControlsView: View {
    @Bindable var settings: AudioSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio")
                .font(Theme.Font.heading)
                .pearlStatic()

            inputDeviceSection
            outputDeviceSection

            if let error = settings.lastError {
                Banner(text: error, tint: Theme.Color.outOfTune)
            }

            Divider()

            monitoringSection
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Input device

    private var inputDeviceSection: some View {
        deviceSection(
            label: "Input Device",
            devices: settings.availableInputDevices,
            emptyMessage: "No input devices found.",
            binding: inputDeviceBinding
        )
    }

    private var inputDeviceBinding: Binding<String?> {
        Binding(
            get: { settings.inputDeviceID ?? settings.availableInputDevices.first?.id },
            set: { id in if let id { settings.setInputDevice(id: id) } }
        )
    }

    // MARK: - Output device

    private var outputDeviceSection: some View {
        deviceSection(
            label: "Output Device",
            devices: settings.availableOutputDevices,
            emptyMessage: "No output devices found.",
            binding: outputDeviceBinding
        )
    }

    private var outputDeviceBinding: Binding<String?> {
        Binding(
            get: { settings.outputDeviceID ?? settings.availableOutputDevices.first?.id },
            set: { id in if let id { settings.setOutputDevice(id: id) } }
        )
    }

    // MARK: - Shared device picker

    private func deviceSection(
        label: String,
        devices: [AudioDevice],
        emptyMessage: String,
        binding: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)

            if devices.isEmpty {
                Text(emptyMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.outOfTune)
            } else {
                Picker(label, selection: binding) {
                    ForEach(devices) { device in
                        Text(deviceLabel(device)).tag(Optional(device.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private func deviceLabel(_ device: AudioDevice) -> String {
        device.channelCount > 1
            ? "\(device.name) — \(device.channelCount) ch"
            : device.name
    }

    // MARK: - Monitoring

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: monitoringBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hear input through output")
                        .font(Theme.Font.body)
                    Text("Routes the live signal to the output device above.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .toggleStyle(.switch)

            if settings.isMonitoringEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.1")
                        .foregroundStyle(Theme.Color.secondaryText)
                    Slider(value: gainBinding, in: 0...2)
                    Image(systemName: "speaker.wave.3")
                        .foregroundStyle(Theme.Color.secondaryText)
                }

                Text("If your output device is picking up the room (built-in mic + built-in speakers), expect feedback. Headphones avoid this.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { settings.isMonitoringEnabled },
            set: { settings.setMonitoring(enabled: $0) }
        )
    }

    private var gainBinding: Binding<Double> {
        Binding(
            get: { settings.monitorGain },
            set: { settings.setMonitorGain($0) }
        )
    }
}

#Preview {
    AudioControlsView(settings: AudioSettings())
}
