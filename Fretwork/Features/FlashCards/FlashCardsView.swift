import SwiftUI

/// Flash cards practice screen: pick a deck, play through cards, get scored.
///
/// The session view is staged like a recital: a progress hairline up top,
/// the prompt in pearl at center, a fixed-height feedback zone (so the
/// layout never jumps), and the hint fretboard sliding in below.
struct FlashCardsView: View {
    @State private var viewModel: FlashCardsViewModel

    init(detector: any PitchDetector, chordDetector: (any ChordDetector)? = nil) {
        _viewModel = State(wrappedValue: FlashCardsViewModel(
            detector: detector,
            chordDetector: chordDetector
        ))
    }

    var body: some View {
        Group {
            if viewModel.isSessionActive {
                sessionView
            } else if viewModel.selectedDeck != nil {
                resultsView
            } else {
                deckPickerView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Deck picker

    private var deckPickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Flash Cards")
                        .font(Theme.Font.title)
                        .pearlStatic()

                    Text("Choose a deck — strict mode makes you play the answer, and the app listens.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.secondaryText)
                }

                // Mode selection
                HStack(spacing: 12) {
                    Picker("Mode", selection: $viewModel.strictness) {
                        ForEach(FlashCardsViewModel.StrictnessMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .labelsHidden()

                    Text(viewModel.strictness.description)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)

                    Spacer()
                }

                // Group decks by type
                ForEach(CardType.allCases) { type in
                    let decks = viewModel.availableDecks.filter { $0.type == type }
                    if !decks.isEmpty {
                        deckSection(type: type, decks: decks)
                    }
                }
            }
            .padding(Theme.Metrics.cardPadding)
        }
    }

    private func deckSection(type: CardType, decks: [FlashCardDeck]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                MicroLabel(type.displayName)
                Text("— \(type.description)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.tertiaryText)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12)
            ], spacing: 12) {
                ForEach(decks) { deck in
                    deckCard(deck)
                }
            }
        }
        .padding(.top, 2)
    }

    @State private var hoveredDeckID: FlashCardDeck.ID?

    private func deckCard(_ deck: FlashCardDeck) -> some View {
        let isHovered = hoveredDeckID == deck.id

        return Button {
            viewModel.selectDeck(deck)
            viewModel.startSession()
        } label: {
            HStack(spacing: 12) {
                // Deck icon bubble: pearl glyph on a mint-tinted squircle.
                Image(systemName: deck.type.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .pearlStatic()
                    .frame(width: 38, height: 38)
                    .background(
                        Theme.Color.accentSoft,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(deck.name)
                        .font(Theme.Font.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(deck.cards.count) CARDS")
                        .font(Theme.Font.microLabel)
                        .tracking(1.2)
                        .foregroundStyle(Theme.Color.tertiaryText)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? Theme.Color.accent : Theme.Color.tertiaryText.opacity(0.5))
            }
            .padding(12)
            .background(
                isHovered ? Theme.Color.surfaceRaised : Theme.Color.surface,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard, style: .continuous)
                    .strokeBorder(
                        isHovered ? Theme.Color.accent.opacity(0.45) : Theme.Color.hairline,
                        lineWidth: 1
                    )
            )
            .offset(y: isHovered ? -2 : 0)
            .animation(.snappy(duration: 0.18), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredDeckID = inside ? deck.id : (hoveredDeckID == deck.id ? nil : hoveredDeckID)
        }
    }

    // MARK: - Active session

    private var sessionView: some View {
        VStack(spacing: 0) {
            // Progress hairline across the very top of the stage.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Color.track.opacity(0.5))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.Color.accentDeep, Theme.Color.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, Theme.Metrics.pagePadding)
            .padding(.top, 10)
            .animation(.snappy(duration: 0.3), value: viewModel.progress.current)

            sessionHeader
                .padding(.horizontal, Theme.Metrics.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if let card = viewModel.currentCard {
                cardView(card)
                    .padding(.horizontal, Theme.Metrics.pagePadding)
                    .id(card.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            // Hint fretboard
            if viewModel.showHint, let hint = viewModel.hintData {
                HintFretboardView(hint: hint)
                    .padding(.horizontal, Theme.Metrics.pagePadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 8)

            sessionControls
                .padding(.horizontal, Theme.Metrics.pagePadding)
                .padding(.bottom, Theme.Metrics.pagePadding)
        }
        .animation(.snappy(duration: 0.3), value: viewModel.currentCard?.id)
    }

    private var progressFraction: CGFloat {
        let total = max(viewModel.progress.total, 1)
        return CGFloat(viewModel.progress.current) / CGFloat(total)
    }

    private var sessionHeader: some View {
        HStack {
            // Deck + progress
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel(viewModel.selectedDeck?.name ?? "")
                Text("Card \(viewModel.progress.current) of \(viewModel.progress.total)")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.Color.primaryText)
                    .monospacedDigit()
            }

            Spacer()

            // Score
            HStack(spacing: 8) {
                PillBadge(text: "\(viewModel.correctCount)", symbol: "checkmark", tint: Theme.Color.inTune)
                PillBadge(text: "\(viewModel.incorrectCount)", symbol: "xmark", tint: Theme.Color.farOutOfTune)
            }

            Spacer()

            // Live note / chord indicator
            if viewModel.isListening {
                if viewModel.currentCard?.type == .chordID {
                    PillBadge(
                        text: viewModel.detectedChord?.name ?? "—",
                        symbol: "guitars.fill",
                        tint: viewModel.detectedChord != nil ? Theme.Color.inTune : Theme.Color.secondaryText
                    )
                } else {
                    PillBadge(
                        text: viewModel.activePitchClass?.sharpName ?? "—",
                        symbol: "circle.fill",
                        tint: viewModel.activePitchClass != nil ? Theme.Color.inTune : Theme.Color.secondaryText
                    )
                }
            } else {
                Text(" ")
            }
        }
    }

    // MARK: - Card view

    @ViewBuilder
    private func cardView(_ card: FlashCard) -> some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            // Prompt
            Text(card.prompt)
                .font(Theme.Font.title)
                .pearlShimmer()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
                .padding(.top, 8)

            // Sequence trail (for sequence cards)
            if card.type == .scaleSequence {
                sequenceTrailView(card: card)
            }

            // Feedback — fixed height so the stage never jumps between states.
            feedbackView
                .frame(height: 84)
        }
        .frame(maxWidth: .infinity)
    }

    private func sequenceTrailView(card: FlashCard) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(card.expectedSequence.enumerated()), id: \.offset) { index, pc in
                        let state = sequenceNoteState(index: index)
                        sequenceNoteView(pc: pc, state: state)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: viewModel.sequencePosition) { _, newPos in
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(newPos, anchor: .center)
                }
            }
        }
        .frame(height: 52)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
                .strokeBorder(Theme.Color.hairline, lineWidth: 1)
        )
        .frame(maxWidth: 560)
    }

    private enum SequenceNoteState {
        case completed
        case completedWrong
        case current
        case upcoming
    }

    private func sequenceNoteState(index: Int) -> SequenceNoteState {
        if index < viewModel.sequenceTrail.count {
            return viewModel.sequenceTrail[index].isCorrect ? .completed : .completedWrong
        } else if index == viewModel.sequencePosition {
            return .current
        }
        return .upcoming
    }

    private func sequenceNoteView(pc: PitchClass, state: SequenceNoteState) -> some View {
        let bgColor: Color
        let textColor: Color

        switch state {
        case .completed:
            bgColor = Theme.Color.inTune.opacity(0.85)
            textColor = Theme.Color.onAccent
        case .completedWrong:
            bgColor = Theme.Color.farOutOfTune.opacity(0.65)
            textColor = .white
        case .current:
            bgColor = Theme.Color.accent
            textColor = Theme.Color.onAccent
        case .upcoming:
            bgColor = Theme.Color.primaryText.opacity(0.07)
            textColor = Theme.Color.secondaryText
        }

        return Text(pc.sharpName)
            .font(.system(size: 12, weight: state == .current ? .bold : .medium, design: .rounded))
            .foregroundStyle(textColor)
            .frame(width: 32, height: 36)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(state == .current ? 1.15 : 1.0)
            .animation(.spring(response: 0.2), value: state == .current)
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackView: some View {
        switch viewModel.feedback {
        case .none:
            VStack(spacing: 6) {
                Image(systemName: viewModel.currentCard?.type == .chordID ? "guitars" : "music.note")
                    .font(.system(size: 18))
                    .pearlStatic(intensity: 0.7)
                Text(viewModel.currentCard?.type == .chordID
                     ? "Play the chord and hold it"
                     : "Play the note and hold it")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

        case .holding(let progress):
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Theme.Color.track, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(Theme.Color.inTune, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Color.inTune)
                        .monospacedDigit()
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel("Hold", color: Theme.Color.inTune)
                    Text("Keep it ringing…")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }

        case .correct:
            VStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Color.inTune)
                    .shadow(color: Theme.Color.inTune.opacity(0.5), radius: 10)
                Text("Correct")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Color.inTune)
            }
            .transition(.scale(scale: 0.7).combined(with: .opacity))

        case .incorrect(let expected, let got):
            VStack(spacing: 4) {
                Label("Not quite", systemImage: "xmark.circle.fill")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Color.farOutOfTune)
                Text("Expected \(expected) · heard \(got)")
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

        case .revealed(let answer):
            VStack(spacing: 4) {
                MicroLabel("Answer")
                Text(answer)
                    .font(Theme.Font.heading)
                    .pearlStatic()
            }
        }
    }

    // MARK: - Session controls

    private var sessionControls: some View {
        HStack(spacing: 12) {
            Button("End Session") {
                viewModel.endSession()
            }
            .buttonStyle(.bordered)

            Spacer()

            // Strictness toggle (accessible during session)
            Picker("Mode", selection: $viewModel.strictness) {
                ForEach(FlashCardsViewModel.StrictnessMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .labelsHidden()

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.showHint.toggle()
                }
            } label: {
                Label("Hint", systemImage: viewModel.showHint ? "eye.fill" : "eye")
            }
            .buttonStyle(.bordered)
            .tint(viewModel.showHint ? Theme.Color.accent : nil)
            .help("Show notes on fretboard")

            Button("Skip") {
                viewModel.skipCard()
            }
            .buttonStyle(.bordered)

            Button("Next") {
                viewModel.nextCard()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.currentCard == nil)
        }
        .padding(12)
        .stageCard(padding: 0)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 18) {
            Spacer()

            MicroLabel("Session Complete")

            Text(viewModel.selectedDeck?.name ?? "")
                .font(Theme.Font.title)
                .pearlStatic()

            // Score ring
            ZStack {
                Circle()
                    .strokeBorder(Theme.Color.track, lineWidth: 9)
                    .frame(width: 156, height: 156)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.scorePercent) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor.opacity(0.55), scoreColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270 * CGFloat(viewModel.scorePercent) / 100 - 90)
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: 156, height: 156)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: scoreColor.opacity(0.4), radius: 8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.scorePercent)

                VStack(spacing: 2) {
                    Text("\(viewModel.scorePercent)%")
                        .font(Theme.Font.heroNumber)
                        .pearlStatic()
                        .monospacedDigit()
                    Text("\(viewModel.correctCount) / \(viewModel.totalAttempts)")
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 8)

            HStack(spacing: 24) {
                Button("Back to Decks") {
                    viewModel.returnToDecks()
                }
                .buttonStyle(.bordered)

                Button("Retry Deck") {
                    viewModel.restartDeck()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreColor: Color {
        let pct = viewModel.scorePercent
        if pct >= 80 { return Theme.Color.inTune }
        if pct >= 50 { return Theme.Color.nearInTune }
        return Theme.Color.farOutOfTune
    }
}

// MARK: - Preview

#Preview {
    FlashCardsView(detector: MockPitchDetector())
        .frame(width: 860, height: 640)
}
