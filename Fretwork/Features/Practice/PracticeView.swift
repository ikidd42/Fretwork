import SwiftUI

/// Practice tab: metronome with scale and chord progression modes.
struct PracticeView: View {
    let detector: any PitchDetector
    let chordDetector: (any ChordDetector)?

    @State private var vm: PracticeViewModel

    init(detector: any PitchDetector, chordDetector: (any ChordDetector)? = nil) {
        self.detector = detector
        self.chordDetector = chordDetector
        self._vm = State(initialValue: PracticeViewModel(
            detector: detector,
            chordDetector: chordDetector
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: mode picker + key/scale
            topControls
                .padding(.horizontal, Theme.Metrics.pagePadding)
                .padding(.top, Theme.Metrics.controlSpacing)

            Divider()
                .padding(.top, 8)

            // Main content area
            ScrollView {
                VStack(spacing: Theme.Metrics.sectionSpacing) {
                    // Beat indicator
                    beatIndicator
                        .padding(.top, Theme.Metrics.sectionSpacing)

                    // Mode-specific content
                    modeContent

                    // Metronome controls
                    metronomeControls

                    // Speed trainer
                    speedTrainerSection

                    // Scoring
                    if vm.mode != .freeMetronome {
                        scoringSection
                    }
                }
                .padding(.horizontal, Theme.Metrics.pagePadding)
                .padding(.bottom, Theme.Metrics.pagePadding)
            }
        }
        .task {
            await vm.start()
        }
        .onDisappear {
            vm.stop()
        }
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack(spacing: 16) {
            // Mode picker
            Picker("Mode", selection: $vm.mode) {
                ForEach(PracticeViewModel.PracticeMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)

            Spacer()

            // Key picker (for scale & chord modes)
            if vm.mode != .freeMetronome {
                HStack(spacing: 8) {
                    Text("Key")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)

                    Picker("Root", selection: $vm.selectedRoot) {
                        ForEach(PitchClass.allCases, id: \.self) { pc in
                            Text(pc.sharpName).tag(pc)
                        }
                    }
                    .frame(width: 60)
                }
            }

            if vm.mode == .scalePractice {
                Picker("Scale", selection: $vm.selectedScale) {
                    ForEach(Scale.catalog, id: \.id) { scale in
                        Text(scale.name).tag(scale)
                    }
                }
                .frame(width: 160)
            }
        }
    }

    // MARK: - Beat Indicator

    private var beatIndicator: some View {
        VStack(spacing: 12) {
            // Beat dots
            HStack(spacing: 8) {
                ForEach(1...vm.beatsPerMeasure, id: \.self) { beat in
                    BeatDot(
                        beat: beat,
                        currentBeat: vm.currentBeat,
                        isAccent: beat == 1,
                        isPlaying: vm.playState != .stopped,
                        isCountIn: vm.playState == .countingIn
                    )
                }
            }

            // Count-in label
            if vm.playState == .countingIn {
                Text("Count in: \(vm.countInBeatsRemaining)")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            // BPM display
            Text("\(Int(vm.bpm)) BPM")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.primaryText)
                .contentTransition(.numericText())

            // Play/Stop button
            Button {
                vm.toggleMetronome()
            } label: {
                Image(systemName: vm.playState != .stopped ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(vm.playState != .stopped ? Theme.Color.farOutOfTune : Theme.Color.accent)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    // MARK: - Mode Content

    @ViewBuilder
    private var modeContent: some View {
        switch vm.mode {
        case .freeMetronome:
            EmptyView()

        case .scalePractice:
            scalePracticeContent

        case .chordProgression:
            chordProgressionContent
        }
    }

    // MARK: - Scale Practice

    private var scalePracticeContent: some View {
        VStack(spacing: 12) {
            if let target = vm.targetNote {
                HStack(spacing: 20) {
                    // Target note
                    VStack(spacing: 4) {
                        Text("Play")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text(target.pitchClass.sharpName)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(noteColor)
                    }

                    // Arrow showing sequence position
                    VStack(spacing: 4) {
                        Text("Position")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text("\(vm.scaleNoteIndex + 1) / \(vm.scaleSequence.count)")
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }

                    // What the player is playing
                    VStack(spacing: 4) {
                        Text("Playing")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text(vm.activePitchClass?.sharpName ?? "—")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(vm.activePitchClass != nil
                                             ? Theme.Color.primaryText
                                             : Theme.Color.secondaryText)
                    }
                }
            }

            // Scale note sequence preview
            scaleSequencePreview
        }
        .padding(Theme.Metrics.cardPadding)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private var noteColor: Color {
        guard vm.playState == .playing else { return Theme.Color.accent }
        if let correct = vm.lastNoteCorrect {
            return correct ? Theme.Color.inTune : Theme.Color.outOfTune
        }
        return Theme.Color.accent
    }

    private var scaleSequencePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(vm.scaleSequence.enumerated()), id: \.offset) { index, note in
                    Text(note.pitchClass.sharpName)
                        .font(index == vm.scaleNoteIndex
                               ? Theme.Font.heading
                               : Theme.Font.body)
                        .foregroundStyle(index == vm.scaleNoteIndex
                                         ? Theme.Color.accent
                                         : Theme.Color.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            index == vm.scaleNoteIndex
                            ? Theme.Color.accent.opacity(0.15)
                            : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
        }
    }

    // MARK: - Chord Progression

    private var chordProgressionContent: some View {
        VStack(spacing: 16) {
            // Progression picker
            Picker("Progression", selection: $vm.selectedProgression) {
                ForEach(ChordProgression.catalog) { prog in
                    Text(prog.name).tag(prog)
                }
            }
            .frame(maxWidth: 300)

            // Current and next chord display
            if !vm.resolvedChords.isEmpty {
                HStack(spacing: 40) {
                    // Current chord
                    VStack(spacing: 4) {
                        Text("Play")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text(vm.targetChord?.name ?? "—")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(chordColor)

                        // Beat countdown within chord
                        let remaining = vm.selectedProgression.beatsPerChord - vm.beatsOnCurrentChord
                        Text("\(remaining) beat\(remaining == 1 ? "" : "s") left")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }

                    // Divider
                    Rectangle()
                        .fill(Theme.Color.secondaryText.opacity(0.3))
                        .frame(width: 1, height: 60)

                    // Next chord
                    VStack(spacing: 4) {
                        Text("Next")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text(vm.nextChord?.name ?? "—")
                            .font(.system(size: 32, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }

                    // Detected chord
                    VStack(spacing: 4) {
                        Text("Detected")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text(vm.detectedChord?.name ?? "—")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundStyle(vm.detectedChord != nil
                                             ? Theme.Color.primaryText
                                             : Theme.Color.secondaryText)
                    }
                }

                // Chord progression timeline
                chordTimeline
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private var chordColor: Color {
        guard vm.playState == .playing else { return Theme.Color.accent }
        if let correct = vm.lastChordCorrect {
            return correct ? Theme.Color.inTune : Theme.Color.outOfTune
        }
        return Theme.Color.accent
    }

    private var chordTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(vm.resolvedChords.enumerated()), id: \.offset) { index, chord in
                    Text(chord.name)
                        .font(index == vm.chordIndex
                               ? Theme.Font.heading
                               : Theme.Font.body)
                        .foregroundStyle(index == vm.chordIndex
                                         ? Theme.Color.accent
                                         : Theme.Color.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            index == vm.chordIndex
                            ? Theme.Color.accent.opacity(0.15)
                            : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
            }
        }
    }

    // MARK: - Metronome Controls

    private var metronomeControls: some View {
        VStack(spacing: 12) {
            // BPM slider
            HStack {
                Text("Tempo")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(width: 60, alignment: .leading)

                Slider(value: $vm.bpm, in: 40...300, step: 1)

                // Tap-tempo and fine-tune buttons
                HStack(spacing: 4) {
                    Button { vm.bpm = max(40, vm.bpm - 1) } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)

                    Button { vm.bpm = min(300, vm.bpm + 1) } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                // Time signature
                HStack(spacing: 8) {
                    Text("Beats")
                        .font(Theme.Font.body)
                        .fixedSize()
                        .foregroundStyle(Theme.Color.secondaryText)

                    Picker("Beats per measure", selection: $vm.beatsPerMeasure) {
                        ForEach([2, 3, 4, 5, 6, 7, 8], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }

                Spacer()

                // Click sound
                HStack(spacing: 8) {
                    Text("Sound")
                        .font(Theme.Font.body)
                        .fixedSize()
                        .foregroundStyle(Theme.Color.secondaryText)

                    Picker("Click sound", selection: $vm.clickSound) {
                        ForEach(AudioMetronome.ClickSound.allCases, id: \.self) { sound in
                            Text(sound.rawValue.capitalized).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                Spacer()

                // Volume
                HStack(spacing: 8) {
                    Text("Volume")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.secondaryText)

                    Slider(value: $vm.metronomeVolume, in: 0...1)
                        .frame(width: 100)
                }

                Spacer()

                // Loop toggle
                Toggle(isOn: $vm.loopEnabled) {
                    Label("Loop", systemImage: "repeat")
                }
                .toggleStyle(.button)
            }

            // Drum track row
            HStack(spacing: 12) {
                Toggle(isOn: $vm.useDrumTrack) {
                    Label("Drum Track", systemImage: "waveform.path")
                }
                .toggleStyle(.switch)
                .frame(width: 180)

                if vm.useDrumTrack {
                    Picker("Pattern", selection: $vm.selectedDrumPattern) {
                        ForEach(DrumPattern.catalog) { pattern in
                            Text(pattern.name).tag(pattern)
                        }
                    }
                    .frame(width: 160)
                }

                Spacer()
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    // MARK: - Speed Trainer

    private var speedTrainerSection: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $vm.speedTrainerEnabled) {
                HStack {
                    Image(systemName: "hare")
                    Text("Speed Trainer")
                        .font(Theme.Font.body)
                    Text("— auto-increase BPM after successful loops")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }

            if vm.speedTrainerEnabled {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Increment:")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Picker("BPM increment", selection: $vm.bpmIncrement) {
                            ForEach([2.0, 5.0, 10.0, 15.0, 20.0], id: \.self) { inc in
                                Text("+\(Int(inc))").tag(inc)
                            }
                        }
                        .frame(width: 70)
                    }

                    HStack(spacing: 4) {
                        Text("Max:")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Picker("Max BPM", selection: $vm.maxBpm) {
                            ForEach([150.0, 200.0, 250.0, 300.0], id: \.self) { max in
                                Text("\(Int(max))").tag(max)
                            }
                        }
                        .frame(width: 70)
                    }

                    if vm.successfulLoops > 0 {
                        Text("\(vm.successfulLoops) streak")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.inTune)
                    }
                }
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    // MARK: - Scoring

    private var scoringSection: some View {
        HStack(spacing: 20) {
            // Accuracy
            VStack(spacing: 4) {
                Text("Accuracy")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
                Text("\(Int(vm.accuracy * 100))%")
                    .font(Theme.Font.heading)
                    .foregroundStyle(accuracyColor)
            }

            VStack(spacing: 4) {
                Text("Correct")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
                Text("\(vm.correctBeats) / \(vm.totalBeats)")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.primaryText)
            }

            if vm.speedTrainerEnabled {
                VStack(spacing: 4) {
                    Text("Starting BPM")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                    Text("\(Int(vm.bpm))")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.primaryText)
                }
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private var accuracyColor: Color {
        let acc = vm.accuracy
        if acc >= 0.9 { return Theme.Color.inTune }
        if acc >= 0.7 { return Theme.Color.nearInTune }
        if acc >= 0.5 { return Theme.Color.outOfTune }
        return Theme.Color.farOutOfTune
    }
}

// MARK: - Beat Dot

private struct BeatDot: View {
    let beat: Int
    let currentBeat: Int
    let isAccent: Bool
    let isPlaying: Bool
    let isCountIn: Bool

    private var isActive: Bool {
        isPlaying && beat == currentBeat
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(isActive ? 1.3 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }

    private var dotSize: CGFloat {
        isAccent ? 20 : 14
    }

    private var dotColor: Color {
        if isActive {
            return isCountIn
                ? Theme.Color.nearInTune
                : (isAccent ? Theme.Color.accent : Theme.Color.inTune)
        }
        return Theme.Color.secondaryText.opacity(0.3)
    }
}

#Preview {
    PracticeView(detector: MockPitchDetector())
}
