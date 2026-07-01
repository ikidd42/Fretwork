import SwiftUI

/// Flash cards practice screen: pick a deck, play through cards, get scored.
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
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                Text("Flash Cards")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.primaryText)

                Text("Choose a deck to practice")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)

                // Settings row
                HStack {
                    Picker("Mode", selection: $viewModel.strictness) {
                        ForEach(FlashCardsViewModel.StrictnessMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

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
        VStack(alignment: .leading, spacing: 8) {
            Label(type.displayName, systemImage: type.symbolName)
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.Color.primaryText)

            Text(type.description)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 180, maximum: 250), spacing: 12)
            ], spacing: 12) {
                ForEach(decks) { deck in
                    deckCard(deck)
                }
            }
        }
        .padding(.top, 8)
    }

    private func deckCard(_ deck: FlashCardDeck) -> some View {
        Button {
            viewModel.selectDeck(deck)
            viewModel.startSession()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(deck.name)
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.Color.primaryText)
                    .lineLimit(2)

                Text("\(deck.cards.count) cards")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active session

    private var sessionView: some View {
        VStack(spacing: 0) {
            sessionHeader
                .padding(.horizontal, Theme.Metrics.cardPadding)
                .padding(.top, Theme.Metrics.sectionSpacing)
                .padding(.bottom, 12)

            if let card = viewModel.currentCard {
                cardView(card)
                    .padding(.horizontal, Theme.Metrics.cardPadding)
                    .id(card.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            // Hint fretboard
            if viewModel.showHint, let hint = viewModel.hintData {
                HintFretboardView(hint: hint)
                    .padding(.horizontal, Theme.Metrics.cardPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()

            sessionControls
                .padding(Theme.Metrics.cardPadding)
        }
        .animation(.snappy(duration: 0.3), value: viewModel.currentCard?.id)
    }

    private var sessionHeader: some View {
        HStack {
            // Progress
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedDeck?.name ?? "")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)

                Text("Card \(viewModel.progress.current) of \(viewModel.progress.total)")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.Color.primaryText)
            }

            Spacer()

            // Score
            HStack(spacing: 16) {
                scoreChip(count: viewModel.correctCount, label: "Correct", color: Theme.Color.inTune)
                scoreChip(count: viewModel.incorrectCount, label: "Wrong", color: Theme.Color.farOutOfTune)
            }

            Spacer()

            // Live note / chord indicator
            if viewModel.isListening {
                if viewModel.currentCard?.type == .chordID {
                    // Show detected chord for chord ID cards
                    HStack(spacing: 6) {
                        Image(systemName: "guitars.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(viewModel.detectedChord != nil
                                             ? Theme.Color.inTune
                                             : Theme.Color.secondaryText.opacity(0.4))
                        Text(viewModel.detectedChord?.name ?? "—")
                            .font(Theme.Font.mono)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Color.primaryText)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.activePitchClass != nil
                                  ? Theme.Color.inTune
                                  : Theme.Color.secondaryText.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(viewModel.activePitchClass?.sharpName ?? "—")
                            .font(Theme.Font.mono)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Color.primaryText)
                    }
                }
            }
        }
    }

    private func scoreChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(Theme.Font.body.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    // MARK: - Card view

    @ViewBuilder
    private func cardView(_ card: FlashCard) -> some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            // Prompt
            Text(card.prompt)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)

            // Sequence trail (for sequence cards)
            if card.type == .scaleSequence {
                sequenceTrailView(card: card)
            }

            // Feedback
            feedbackView
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Metrics.cardPadding)
    }

    private func sequenceTrailView(card: FlashCard) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
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
        .frame(height: 56)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
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
            bgColor = Theme.Color.inTune.opacity(0.8)
            textColor = .white
        case .completedWrong:
            bgColor = Theme.Color.farOutOfTune.opacity(0.6)
            textColor = .white
        case .current:
            bgColor = Theme.Color.accent
            textColor = .white
        case .upcoming:
            bgColor = Theme.Color.primaryText.opacity(0.08)
            textColor = Theme.Color.secondaryText
        }

        return Text(pc.sharpName)
            .font(.system(size: 12, weight: state == .current ? .bold : .medium, design: .rounded))
            .foregroundStyle(textColor)
            .frame(width: 32, height: 36)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(state == .current ? 1.15 : 1.0)
            .animation(.spring(response: 0.2), value: state == .current)
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackView: some View {
        switch viewModel.feedback {
        case .none:
            Text(viewModel.currentCard?.type == .chordID
                 ? "Play the chord and hold!"
                 : "Play the note and hold!")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.secondaryText)

        case .holding(let progress):
            VStack(spacing: 8) {
                Text("Hold it...")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.Color.inTune)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))

                        Capsule()
                            .fill(Theme.Color.inTune)
                            .frame(width: geo.size.width * CGFloat(progress))
                            .animation(.linear(duration: 0.05), value: progress)
                    }
                }
                .frame(width: 200, height: 10)
            }

        case .correct:
            Label("Correct!", systemImage: "checkmark.circle.fill")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.Color.inTune)

        case .incorrect(let expected, let got):
            VStack(spacing: 4) {
                Label("Not quite", systemImage: "xmark.circle.fill")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Color.farOutOfTune)
                Text("Expected \(expected), heard \(got)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

        case .revealed(let answer):
            VStack(spacing: 4) {
                Text("Answer: \(answer)")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Color.accent)
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
            .frame(width: 180)

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.showHint.toggle()
                }
            } label: {
                Label("Hint", systemImage: viewModel.showHint
                      ? "eye.fill" : "eye")
            }
            .buttonStyle(.bordered)
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
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            Spacer()

            Text("Session Complete")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.primaryText)

            Text(viewModel.selectedDeck?.name ?? "")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.Color.secondaryText)

            // Score ring
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 8)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.scorePercent) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(viewModel.scorePercent)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("\(viewModel.correctCount)/\(viewModel.totalAttempts)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }

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
        .frame(width: 800, height: 600)
}
