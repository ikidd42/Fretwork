import SwiftUI

/// Root window: a sidebar of feature sections plus a detail pane, with a
/// global Audio button in the toolbar that opens the input/monitoring controls.
struct RootView: View {
    let pitchDetector: any PitchDetector
    let chordDetector: (any ChordDetector)?
    @Bindable var audioSettings: AudioSettings

    @State private var selection: AppSection? = .tuner
    @State private var showingAudioPopover = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.background)
        }
        .navigationTitle("Fretwork")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                audioToolbarButton
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .tuner {
        case .tuner:
            TunerView(detector: pitchDetector)
        case .flashCards:
            FlashCardsView(detector: pitchDetector, chordDetector: chordDetector)
        case .fretboard:
            FretboardView(detector: pitchDetector, chordDetector: chordDetector)
        case .practice:
            PracticeView(detector: pitchDetector, chordDetector: chordDetector)
        }
    }

    private var audioToolbarButton: some View {
        Button {
            showingAudioPopover.toggle()
        } label: {
            Label("Audio", systemImage: audioToolbarSymbol)
        }
        .help("Input device and monitoring")
        .popover(isPresented: $showingAudioPopover, arrowEdge: .top) {
            AudioControlsView(settings: audioSettings)
        }
    }

    /// A subtle hint that monitoring is on, so the user knows audio is being
    /// routed even when the popover is closed.
    private var audioToolbarSymbol: String {
        audioSettings.isMonitoringEnabled
            ? "waveform.circle.fill"
            : "waveform.circle"
    }
}

#Preview {
    RootView(
        pitchDetector: MockPitchDetector(),
        chordDetector: MockChordDetector(),
        audioSettings: AudioSettings()
    )
}
