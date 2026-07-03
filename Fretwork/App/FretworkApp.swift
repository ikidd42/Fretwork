import SwiftUI

/// App entry point.
///
/// The single live pitch detector and the user's audio preferences are owned
/// here and passed down explicitly. Subviews can't accidentally instantiate
/// their own audio engines.
@main
struct FretworkApp: App {
    @State private var pitchDetector = LivePitchDetector()
    @State private var audioSettings = AudioSettings()
    @State private var selection: AppSection? = .tuner

    var body: some Scene {
        WindowGroup {
            RootView(
                pitchDetector: pitchDetector,
                chordDetector: pitchDetector,
                audioSettings: audioSettings,
                selection: $selection
            )
            .frame(minWidth: 720, minHeight: 480)
            // The brand theme is dark indigo throughout; forcing dark
            // appearance keeps native controls (pickers, toggles,
            // popovers) legible on it regardless of the system setting.
            .preferredColorScheme(.dark)
            .task {
                // Idempotent — pushes persisted settings into the audio engine
                // and connects the controller for future updates.
                audioSettings.bind(controller: pitchDetector)
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
