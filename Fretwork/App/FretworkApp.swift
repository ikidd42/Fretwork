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

    var body: some Scene {
        WindowGroup {
            RootView(
                pitchDetector: pitchDetector,
                chordDetector: pitchDetector,
                audioSettings: audioSettings
            )
            .frame(minWidth: 720, minHeight: 480)
            .task {
                // Idempotent — pushes persisted settings into the audio engine
                // and connects the controller for future updates.
                audioSettings.bind(controller: pitchDetector)
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
    }
}
