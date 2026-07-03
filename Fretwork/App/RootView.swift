import SwiftUI

/// Root window: a sidebar of feature sections plus a detail pane, with a
/// global Audio button in the toolbar that opens the input/monitoring controls.
struct RootView: View {
    let pitchDetector: any PitchDetector
    let chordDetector: (any ChordDetector)?
    @Bindable var audioSettings: AudioSettings
    /// Owned by the App so the Go menu's ⌘1–⌘4 shortcuts can drive it.
    @Binding var selection: AppSection?

    @State private var showingAudioPopover = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FretboardSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 290)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailBackground)
        }
        // The sidebar header already says "Fretwork"; the window title
        // tracks the active section instead.
        .navigationTitle((selection ?? .tuner).title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                sidebarToggleButton
            }
            ToolbarItem(placement: .primaryAction) {
                audioToolbarButton
            }
        }
    }

    /// The stage behind every page: deep indigo falling darker toward the
    /// bottom, with a faint cool glow up top — like stage lighting on a
    /// dark backdrop. Content cards float on `Theme.Color.surface` lifts.
    private var detailBackground: some View {
        LinearGradient(
            colors: [Theme.Color.backgroundTop, Theme.Color.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: .init(x: 0.5, y: -0.1),
                startRadius: 0,
                endRadius: 560
            )
        )
        .ignoresSafeArea()
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        } label: {
            Label("Toggle Sidebar", systemImage: "sidebar.left")
        }
        .help("Hide or show the sidebar")
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
    @Previewable @State var selection: AppSection? = .tuner
    return RootView(
        pitchDetector: MockPitchDetector(),
        chordDetector: MockChordDetector(),
        audioSettings: AudioSettings(),
        selection: $selection
    )
}
