import SwiftUI

/// Compact audio settings UI. Designed to live inside a toolbar popover.
///
/// Bindings are constructed manually rather than via `@Bindable`'s `$` syntax,
/// because `AudioSettings` exposes its state read-only and routes mutations
/// through methods that also persist + push to the audio engine.
struct AudioControlsView: View {
    @Bindable var settings: AudioSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Audio")
                    .font(Theme.Font.heading)
                    .pearlStatic()
                Spacer()
                if settings.isMonitoringEnabled {
                    PillBadge(text: "MONITORING", symbol: "waveform", tint: Theme.Color.accent)
                }
            }

            inputDeviceSection
            outputDeviceSection

            if let error = settings.lastError {
                Banner(text: error, tint: Theme.Color.outOfTune, symbol: "bolt.trianglebadge.exclamationmark.fill")
            }

            Divider().overlay(Theme.Color.hairline)

            monitoringSection
        }
        .padding(18)
        .frame(width: 380)
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
            MicroLabel(label)

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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
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
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.tertiaryText)
                    Slider(value: gainBinding, in: 0...2)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.nearInTune)
                    Text("Built-in mic + built-in speakers will feed back. Headphones avoid this.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
