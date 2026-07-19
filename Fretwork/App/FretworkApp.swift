import SwiftUI

/// App entry point.
///
/// The single live pitch detector and the user's audio preferences are owned
/// here and passed down explicitly. Subviews can't accidentally instantiate
/// their own audio engines.
///
/// Launch with `--demo` to swap the hardware detectors for scripted mocks —
/// the tuner/fretboard come alive without a guitar or mic permission, which
/// is how screenshots and UI demos are produced.
@main
struct FretworkApp: App {
    private let demoMode = ProcessInfo.processInfo.arguments.contains("--demo")

    @State private var pitchDetector: any PitchDetector
    @State private var chordDetector: (any ChordDetector)?
    @State private var audioSettings = AudioSettings()
    @State private var selection: AppSection? = .tuner

    init() {
        if demoMode {
            _pitchDetector = State(initialValue: MockPitchDetector())
            _chordDetector = State(initialValue: MockChordDetector())
        } else {
            // One object plays both roles: monophonic pitch and polyphonic
            // chord detection share the same Core Audio input pipeline.
            let live = LivePitchDetector()
            _pitchDetector = State(initialValue: live)
            _chordDetector = State(initialValue: live)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                pitchDetector: pitchDetector,
                chordDetector: chordDetector,
                audioSettings: audioSettings,
                selection: $selection
            )
            .frame(
                minWidth: 780, idealWidth: 1120,
                minHeight: 560, idealHeight: 760
            )
            // The brand theme is dark indigo throughout; forcing dark
            // appearance keeps native controls (pickers, toggles,
            // popovers) legible on it regardless of the system setting.
            .preferredColorScheme(.dark)
            .task {
                // Idempotent — pushes persisted settings into the audio engine
                // and connects the controller for future updates. Demo mocks
                // aren't device controllers, so they skip binding.
                if let controller = pitchDetector as? any AudioDeviceController {
                    audioSettings.bind(controller: controller)
                }
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // ⌘1–⌘4 jump between sidebar sections, mirrored in a Go menu.
            CommandMenu("Go") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { selection = section }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")),
                            modifiers: .command
                        )
                }
            }
        }
    }
}
