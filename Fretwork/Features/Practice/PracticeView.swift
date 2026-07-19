import SwiftUI

/// Practice tab: metronome with scale and chord progression modes.
///
/// The transport is the hero — a big play control with a pulsing ring while
/// running, the BPM readout in hero mono, and glowing beat dots. Everything
/// else lives in consistently-headed stage cards: the mode drill, the sound
/// rack, the speed trainer, and the score.
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
            topControls
                .padding(.horizontal, Theme.Metrics.pagePadding)
                .padding(.top, Theme.Metrics.controlSpacing)
                .padding(.bottom, 12)

            if vm.mode == .freeMetronome {
                // Free mode is just the rig — center it on the stage.
                VStack(spacing: Theme.Metrics.sectionSpacing) {
                    Spacer(minLength: 0)
                    transportCard
                    soundCard
                    speedTrainerCard
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Metrics.pagePadding)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Metrics.sectionSpacing) {
                        transportCard

                        modeContent

                        soundCard

                        speedTrainerCard

                        scoreCard
                    }
                    .padding(.horizontal, Theme.Metrics.pagePadding)
                    .padding(.bottom, Theme.Metrics.pagePadding)
                }
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
            .frame(maxWidth: 480)
            .labelsHidden()

            Spacer()

            // Key picker (for scale & chord modes)
            if vm.mode != .freeMetronome {
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel("Key")
                    Picker("Root", selection: $vm.selectedRoot) {
                        ForEach(PitchClass.allCases, id: \.self) { pc in
                            Text(pc.sharpName).tag(pc)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 62)
                }
            }

            if vm.mode == .scalePractice {
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel("Scale")
                    Picker("Scale", selection: $vm.selectedScale) {
                        ForEach(Scale.catalog, id: \.id) { scale in
                            Text(scale.name).tag(scale)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .stageCard(padding: 0)
    }

    // MARK: - Transport

    private var transportCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                PlayButton(isRunning: vm.playState != .stopped, action: vm.toggleMetronome)

                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("Tempo")
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(vm.bpm))")
                            .font(Theme.Font.heroNumber)
                            .foregroundStyle(Theme.Color.primaryText)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("BPM")
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }

                    transportStatus
                }

                Spacer()

                // Beat dots
                HStack(spacing: 10) {
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
                .padding(.trailing, 4)
            }

            // Tempo slider row
            HStack(spacing: 10) {
                Button { vm.bpm = max(40, vm.bpm - 1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)

                Slider(value: $vm.bpm, in: 40...300, step: 1)

                Button { vm.bpm = min(300, vm.bpm + 1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)

                Text("\(Int(vm.bpm))")
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .stageCard()
    }

    @ViewBuilder
    private var transportStatus: some View {
        switch vm.playState {
        case .stopped:
            Text("Ready when you are")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
        case .countingIn:
            Text("Count in · \(vm.countInBeatsRemaining)")
                .font(Theme.Font.caption.weight(.medium))
                .foregroundStyle(Theme.Color.nearInTune)
                .monospacedDigit()
        case .playing:
            Text("Bar \(vm.currentMeasure + 1)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)
                .monospacedDigit()
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
        VStack(spacing: 14) {
            if let target = vm.targetNote {
                HStack(spacing: 0) {
                    statColumn(label: "Play") {
                        Text(target.pitchClass.sharpName)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(noteColor)
                    }
                    statDivider
                    statColumn(label: "Position") {
                        Text("\(vm.scaleNoteIndex + 1) / \(vm.scaleSequence.count)")
                            .font(Theme.Font.statNumber)
                            .foregroundStyle(Theme.Color.primaryText)
                            .monospacedDigit()
                    }
                    statDivider
                    statColumn(label: "Heard") {
                        Text(vm.activePitchClass?.sharpName ?? "—")
                            .font(Theme.Font.statNumber)
                            .foregroundStyle(vm.activePitchClass != nil
                                             ? Theme.Color.primaryText
                                             : Theme.Color.tertiaryText)
                    }
                }
            } else {
                Text("Press play — the scale runs one note per beat, up and back down.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !vm.scaleSequence.isEmpty {
                scaleSequencePreview
            }
        }
        .stageCard()
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
            HStack(spacing: 5) {
                ForEach(Array(vm.scaleSequence.enumerated()), id: \.offset) { index, note in
                    let isCurrent = index == vm.scaleNoteIndex
                    Text(note.pitchClass.sharpName)
                        .font(.system(size: isCurrent ? 13 : 11,
                                      weight: isCurrent ? .bold : .medium,
                                      design: .rounded))
                        .foregroundStyle(isCurrent ? Theme.Color.onAccent : Theme.Color.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(
                            isCurrent ? Theme.Color.accent : Theme.Color.surface,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
            }
        }
    }

    // MARK: - Chord Progression

    private var chordProgressionContent: some View {
        VStack(spacing: 14) {
            HStack {
                MicroLabel("Progression")
                Picker("Progression", selection: $vm.selectedProgression) {
                    ForEach(ChordProgression.catalog) { prog in
                        Text(prog.name).tag(prog)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
                Spacer()
            }

            if !vm.resolvedChords.isEmpty {
                HStack(spacing: 0) {
                    statColumn(label: "Play") {
                        VStack(spacing: 2) {
                            Text(vm.targetChord?.name ?? "—")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(chordColor)
                            let remaining = vm.selectedProgression.beatsPerChord - vm.beatsOnCurrentChord
                            Text("\(remaining) beat\(remaining == 1 ? "" : "s") left")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.secondaryText)
                                .monospacedDigit()
                        }
                    }
                    statDivider
                    statColumn(label: "Next") {
                        Text(vm.nextChord?.name ?? "—")
                            .font(Theme.Font.statNumber)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    statDivider
                    statColumn(label: "Detected") {
                        Text(vm.detectedChord?.name ?? "—")
                            .font(Theme.Font.statNumber)
                            .foregroundStyle(vm.detectedChord != nil
                                             ? Theme.Color.primaryText
                                             : Theme.Color.tertiaryText)
                    }
                }

                chordTimeline
            } else {
                Text("Press play — chords change on the bar line.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .stageCard()
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
                    let isCurrent = index == vm.chordIndex
                    Text(chord.name)
                        .font(.system(size: isCurrent ? 15 : 13,
                                      weight: isCurrent ? .bold : .medium,
                                      design: .rounded))
                        .foregroundStyle(isCurrent ? Theme.Color.onAccent : Theme.Color.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isCurrent ? Theme.Color.accent : Theme.Color.surface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
            }
        }
    }

    // MARK: - Stat column helper

    private func statColumn<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            MicroLabel(label)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.Color.hairline)
            .frame(width: 1, height: 64)
    }

    // MARK: - Sound rack

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Sound")

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    MicroLabel("Beats")
                    Picker("Beats per measure", selection: $vm.beatsPerMeasure) {
                        ForEach([2, 3, 4, 5, 6, 7, 8], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 58)
                }

                Divider().frame(height: 22)

                HStack(spacing: 8) {
                    MicroLabel("Click")
                    Picker("Click sound", selection: $vm.clickSound) {
                        ForEach(AudioMetronome.ClickSound.allCases, id: \.self) { sound in
                            Text(sound.rawValue.capitalized).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                Divider().frame(height: 22)

                HStack(spacing: 8) {
                    MicroLabel("Volume")
                    Slider(value: $vm.metronomeVolume, in: 0...1)
                        .frame(width: 110)
                }

                Spacer()

                Toggle(isOn: $vm.loopEnabled) {
                    Label("Loop", systemImage: "repeat")
                }
                .toggleStyle(.button)
            }

            HStack(spacing: 12) {
                Toggle(isOn: $vm.useDrumTrack) {
                    Label("Drum Track", systemImage: "waveform.path")
                }
                .toggleStyle(.switch)

                if vm.useDrumTrack {
                    Picker("Pattern", selection: $vm.selectedDrumPattern) {
                        ForEach(DrumPattern.catalog) { pattern in
                            Text(pattern.name).tag(pattern)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Spacer()
            }
        }
        .stageCard()
    }

    // MARK: - Speed Trainer

    private var speedTrainerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $vm.speedTrainerEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "hare.fill")
                        .foregroundStyle(Theme.Color.accent)
                    Text("Speed Trainer")
                        .font(Theme.Font.body.weight(.medium))
                    Text("— BPM climbs after each clean loop")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .toggleStyle(.switch)

            if vm.speedTrainerEnabled {
                HStack(spacing: 18) {
                    HStack(spacing: 6) {
                        MicroLabel("Step")
                        Picker("BPM increment", selection: $vm.bpmIncrement) {
                            ForEach([2.0, 5.0, 10.0, 15.0, 20.0], id: \.self) { inc in
                                Text("+\(Int(inc))").tag(inc)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 66)
                    }

                    HStack(spacing: 6) {
                        MicroLabel("Max")
                        Picker("Max BPM", selection: $vm.maxBpm) {
                            ForEach([150.0, 200.0, 250.0, 300.0], id: \.self) { max in
                                Text("\(Int(max))").tag(max)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 72)
                    }

                    if vm.successfulLoops > 0 {
                        PillBadge(text: "\(vm.successfulLoops) streak", symbol: "flame.fill", tint: Theme.Color.inTune)
                    }

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stageCard()
    }

    // MARK: - Score

    private var scoreCard: some View {
        HStack(spacing: 0) {
            statColumn(label: "Accuracy") {
                Text("\(Int(vm.accuracy * 100))%")
                    .font(Theme.Font.statNumber)
                    .foregroundStyle(accuracyColor)
                    .monospacedDigit()
            }
            statDivider
            statColumn(label: "Correct") {
                Text("\(vm.correctBeats) / \(vm.totalBeats)")
                    .font(Theme.Font.statNumber)
                    .foregroundStyle(Theme.Color.primaryText)
                    .monospacedDigit()
            }
            if vm.speedTrainerEnabled {
                statDivider
                statColumn(label: "Tempo") {
                    Text("\(Int(vm.bpm))")
                        .font(Theme.Font.statNumber)
                        .foregroundStyle(Theme.Color.primaryText)
                        .monospacedDigit()
                }
            }
        }
        .stageCard()
    }

    private var accuracyColor: Color {
        let acc = vm.accuracy
        if acc >= 0.9 { return Theme.Color.inTune }
        if acc >= 0.7 { return Theme.Color.nearInTune }
        if acc >= 0.5 { return Theme.Color.outOfTune }
        return Theme.Color.farOutOfTune
    }
}

// MARK: - Play Button

/// The transport's centerpiece: a 68 pt disc, mint with a dark glyph when
/// armed, red-tinted when running, with a ring that breathes outward on the
/// running state (motion-disabled users get a static ring).
private struct PlayButton: View {
    let isRunning: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Breathing ring while running.
                Circle()
                    .stroke(Theme.Color.farOutOfTune.opacity(pulsing ? 0.0 : 0.5), lineWidth: 2)
                    .frame(width: 68, height: 68)
                    .scaleEffect(pulsing ? 1.35 : 1.0)
                    .opacity(isRunning ? 1 : 0)

                Circle()
                    .fill(
                        isRunning
                            ? LinearGradient(colors: [Theme.Color.farOutOfTune.opacity(0.9),
                                                      Theme.Color.farOutOfTune.opacity(0.7)],
                                             startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Theme.Color.accent, Theme.Color.accentDeep],
                                             startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: (isRunning ? Theme.Color.farOutOfTune : Theme.Color.accent).opacity(0.45),
                            radius: 14, y: 4)

                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isRunning ? .white : Theme.Color.onAccent)
                    .offset(x: isRunning ? 0 : 2)
            }
            .frame(width: 92, height: 92)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .onAppear { updatePulse() }
        .onChange(of: isRunning) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard isRunning, !reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
            pulsing = true
        }
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
            .shadow(color: isActive ? dotColor.opacity(0.8) : .clear, radius: 8)
            .scaleEffect(isActive ? 1.25 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }

    private var dotSize: CGFloat {
        isAccent ? 22 : 15
    }

    private var dotColor: Color {
        if isActive {
            return isCountIn
                ? Theme.Color.nearInTune
                : (isAccent ? Theme.Color.accent : Theme.Color.inTune)
        }
        return Theme.Color.secondaryText.opacity(0.28)
    }
}

#Preview {
    PracticeView(detector: MockPitchDetector())
        .frame(width: 860, height: 720)
}
