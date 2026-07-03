import Foundation
import Observation

/// Drives the flash cards UI: deck selection, card progression, pitch matching,
/// scoring, and sequence trail tracking.
@MainActor
@Observable
final class FlashCardsViewModel {

    // MARK: - Configuration

    enum StrictnessMode: String, CaseIterable, Identifiable {
        case lenient
        case strict

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .lenient: "Lenient"
            case .strict:  "Strict"
            }
        }

        var description: String {
            switch self {
            case .lenient: "Show answer and move on"
            case .strict:  "Must play the correct note"
            }
        }
    }

    var strictness: StrictnessMode = .lenient

    // MARK: - Deck / card state

    private(set) var availableDecks: [FlashCardDeck] = []
    private(set) var selectedDeck: FlashCardDeck?
    private(set) var currentCardIndex: Int = 0
    private(set) var isSessionActive: Bool = false

    var currentCard: FlashCard? {
        guard let deck = selectedDeck,
              currentCardIndex < deck.cards.count else { return nil }
        return deck.cards[currentCardIndex]
    }

    var progress: (current: Int, total: Int) {
        let total = selectedDeck?.cards.count ?? 0
        return (min(currentCardIndex + 1, total), total)
    }

    // MARK: - Hint

    var showHint: Bool = false

    /// Data the hint fretboard needs to display for the current card.
    struct HintData {
        /// All pitch classes to show on the fretboard (e.g. full scale).
        let scalePitchClasses: Set<PitchClass>
        /// The specific target note(s) to emphasize.
        let targetPitchClasses: Set<PitchClass>
        /// Root of the scale/interval for visual emphasis.
        let root: PitchClass?
        /// Degree labels for scale-based hints.
        let degreeMap: [PitchClass: String]
        /// Description shown above the hint fretboard.
        let label: String
    }

    var hintData: HintData? {
        guard let card = currentCard else { return nil }

        switch card.type {
        case .scaleDegree:
            // Show the full scale with the target degree highlighted.
            return scaleDegreeHint(card: card)
        case .scaleSequence:
            // Show the full scale.
            return scaleSequenceHint(card: card)
        case .noteID:
            // Show where the answer note appears on the fretboard.
            return noteIDHint(card: card)
        case .interval:
            // Show the root and the target interval note.
            return intervalHint(card: card)
        case .chordID:
            // Show the chord tones on the fretboard.
            return chordIDHint(card: card)
        }
    }

    private func scaleDegreeHint(card: FlashCard) -> HintData? {
        guard let root = card.root,
              let scale = card.scale,
              let target = card.expectedPitchClass else { return nil }

        let pcs = scale.pitchClasses(in: root)
        let degrees = DeckGenerator.scaleDegreeLabels(for: scale)
        var degreeMap: [PitchClass: String] = [:]
        for (i, pc) in pcs.enumerated() {
            degreeMap[pc] = degrees[i]
        }
        return HintData(
            scalePitchClasses: Set(pcs),
            targetPitchClasses: [target],
            root: root,
            degreeMap: degreeMap,
            label: "\(root.sharpName) \(scale.name)"
        )
    }

    private func scaleSequenceHint(card: FlashCard) -> HintData? {
        // The sequence contains all the scale's pitch classes.
        let pcs = Set(card.expectedSequence)
        let root = card.root ?? card.expectedSequence.first ?? .c
        return HintData(
            scalePitchClasses: pcs,
            targetPitchClasses: pcs,
            root: root,
            degreeMap: [:],
            label: card.prompt
        )
    }

    private func noteIDHint(card: FlashCard) -> HintData? {
        guard let target = card.expectedPitchClass else { return nil }
        return HintData(
            scalePitchClasses: Set([target]),
            targetPitchClasses: Set([target]),
            root: target,
            degreeMap: [:],
            label: "All \(target.sharpName) notes"
        )
    }

    private func intervalHint(card: FlashCard) -> HintData? {
        guard let target = card.expectedPitchClass else { return nil }
        let rootPC = card.root ?? .c
        return HintData(
            scalePitchClasses: Set([rootPC, target]),
            targetPitchClasses: Set([target]),
            root: rootPC,
            degreeMap: [rootPC: "R", target: card.answerDescription],
            label: "\(rootPC.sharpName) → \(target.sharpName)"
        )
    }

    private func chordIDHint(card: FlashCard) -> HintData? {
        guard let chord = card.expectedChord else { return nil }
        let pcs = Set(chord.pitchClasses)
        var degreeMap: [PitchClass: String] = [:]
        degreeMap[chord.root] = "R"
        for (i, pc) in chord.pitchClasses.enumerated() where i > 0 {
            let interval = chord.quality.intervals[i]
            degreeMap[pc] = Interval(semitones: interval).shortName
        }
        return HintData(
            scalePitchClasses: pcs,
            targetPitchClasses: pcs,
            root: chord.root,
            degreeMap: degreeMap,
            label: chord.name
        )
    }

    // MARK: - Scoring

    private(set) var correctCount: Int = 0
    private(set) var incorrectCount: Int = 0
    private(set) var totalAttempts: Int = 0

    var scorePercent: Int {
        guard totalAttempts > 0 else { return 0 }
        return Int(Double(correctCount) / Double(totalAttempts) * 100)
    }

    // MARK: - Sequence trail (for scaleSequence cards)

    /// Index into `currentCard.expectedSequence` — how far along the user is.
    private(set) var sequencePosition: Int = 0

    /// Tracks which positions in the sequence have been completed.
    private(set) var sequenceTrail: [SequenceStep] = []

    struct SequenceStep: Identifiable {
        let id = UUID()
        let pitchClass: PitchClass
        let isCorrect: Bool
    }

    // MARK: - Feedback state

    enum Feedback: Equatable {
        case none
        case holding(progress: Double)
        case correct
        case incorrect(expected: String, got: String)
        case revealed(answer: String)
    }

    private(set) var feedback: Feedback = .none

    /// Brief delay before auto-advancing after correct/revealed answer.
    private var advanceTask: Task<Void, Never>?

    // MARK: - Hold-to-confirm

    /// Seconds the user must hold the correct note to confirm it.
    let holdDuration: Double = 0.6
    /// Shorter hold for sequence notes to keep flow going.
    let sequenceHoldDuration: Double = 0.3

    /// When the user started holding the current correct note, or nil.
    private var holdStartTime: Date?
    /// The pitch class being held for confirmation.
    private var holdingPitchClass: PitchClass?

    /// When true, the card won't advance until the detected pitch drops out
    /// (silence / below threshold). Prevents a held note from bleeding into
    /// the next card.
    private var waitingForSilence: Bool = false

    /// Require sustained silence — not just a single dip below threshold.
    /// Tracks when we first saw silence. Advance only after this duration.
    private let silenceDuration: Double = 0.2
    private var silenceStartTime: Date?

    // MARK: - Live pitch detection

    private(set) var permission: AudioPermission.Status = .undetermined
    private(set) var isListening: Bool = false
    private(set) var lastError: String?
    private(set) var activePitchClass: PitchClass?

    private var smoothedFrequency: Double?

    // Tunables (match tuner/fretboard)
    var amplitudeThreshold: Double = DetectedPitch.defaultAmplitudeThreshold
    var smoothing: Double = 0.6
    var minFrequency: Double = 30
    var maxFrequency: Double = 4000

    // MARK: - Chord detection (for chordID cards)

    /// The chord currently being detected, if any.
    private(set) var detectedChord: Chord?
    private(set) var chordConfidence: Double = 0

    /// Stability gate for chords: same chord for N consecutive readings.
    private var candidateChordForCard: Chord?
    private var candidateChordCardCount: Int = 0
    private let chordConfirmationsNeeded = 4

    /// Hold-to-confirm for chord cards.
    private var holdingChord: Chord?
    private var chordHoldStartTime: Date?
    let chordHoldDuration: Double = 1.0  // chords need longer hold

    /// A wrong chord only counts against the player after it has been
    /// continuously detected for this long. The attack of a strum
    /// legitimately reads as partial voicings while the strings arrive
    /// (~100 ms) and the analyzer's smoothing settles — without this
    /// grace, cards were failed by their own strum transient.
    let wrongChordGraceDuration: Double = 0.6
    private var wrongChordCandidate: Chord?
    private var wrongChordStartTime: Date?

    // MARK: - Dependencies

    private let detector: any PitchDetector
    private let chordDetector: (any ChordDetector)?

    init(detector: any PitchDetector, chordDetector: (any ChordDetector)? = nil) {
        self.detector = detector
        self.chordDetector = chordDetector
        availableDecks = DeckGenerator.allDecks()
    }

    // MARK: - Lifecycle

    func start() async {
        permission = AudioPermission.current
        if permission == .undetermined {
            permission = await AudioPermission.request()
        }
        guard permission == .granted else { return }

        detector.onPitch = { [weak self] reading in
            Task { @MainActor [weak self] in
                self?.ingest(reading)
            }
        }

        chordDetector?.onChord = { [weak self] detected in
            Task { @MainActor [weak self] in
                self?.ingestChord(detected)
            }
        }

        do {
            try detector.start()
            isListening = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isListening = false
        }
    }

    func stop() {
        isListening = false
        smoothedFrequency = nil
        activePitchClass = nil
        detectedChord = nil
        chordConfidence = 0
        advanceTask?.cancel()
    }

    // MARK: - Session control

    func selectDeck(_ deck: FlashCardDeck) {
        selectedDeck = deck
        resetSession()
    }

    func startSession() {
        guard selectedDeck != nil else { return }
        resetSession()
        isSessionActive = true
    }

    func endSession() {
        isSessionActive = false
        advanceTask?.cancel()
    }

    /// Return to the deck picker, clearing all session state.
    func returnToDecks() {
        endSession()
        selectedDeck = nil
        resetSession()
    }

    func nextCard() {
        guard let deck = selectedDeck else { return }
        advanceTask?.cancel()
        feedback = .none
        showHint = false
        sequencePosition = 0
        sequenceTrail = []
        resetHold()
        resetChordHold()
        lastMatchedPitch = nil
        lastSequenceRegistered = nil
        waitingForSilence = false
        silenceStartTime = nil
        candidateChordForCard = nil
        candidateChordCardCount = 0
        wrongChordCandidate = nil
        wrongChordStartTime = nil

        if currentCardIndex + 1 < deck.cards.count {
            currentCardIndex += 1
        } else {
            // End of deck
            isSessionActive = false
        }
    }

    func skipCard() {
        guard let card = currentCard else { return }
        feedback = .revealed(answer: card.answerDescription)
        scheduleAdvance()
    }

    func restartDeck() {
        resetSession()
        isSessionActive = true
    }

    private func resetSession() {
        currentCardIndex = 0
        correctCount = 0
        incorrectCount = 0
        totalAttempts = 0
        sequencePosition = 0
        sequenceTrail = []
        feedback = .none
        advanceTask?.cancel()
        resetHold()
        resetChordHold()
        lastMatchedPitch = nil
        lastSequenceRegistered = nil
        waitingForSilence = false
        silenceStartTime = nil
        candidateChordForCard = nil
        candidateChordCardCount = 0
        wrongChordCandidate = nil
        wrongChordStartTime = nil
    }

    // MARK: - Pitch matching

    /// Debounce: ignore repeated triggers of the same pitch class.
    private var lastMatchedPitch: PitchClass?
    /// Timestamp of last match, to allow re-triggering after a pause.
    private var lastMatchTime: Date = .distantPast

    /// Stability gate: the same pitch class must be detected for this many
    /// consecutive readings before we accept it. At ~128 frames / 48 kHz
    /// the IOProc fires every ~2.7 ms, so 4 confirmations ≈ 11 ms — long
    /// enough to ride out attack transients, short enough to feel instant.
    private let confirmationsNeeded = 4
    private var candidatePitch: PitchClass?
    private var candidateCount: Int = 0

    private func ingest(_ reading: DetectedPitch) {
        guard reading.amplitude > amplitudeThreshold,
              reading.frequency.isFinite,
              reading.frequency > minFrequency,
              reading.frequency < maxFrequency
        else {
            activePitchClass = nil
            candidatePitch = nil
            candidateCount = 0
            // Reset match debounce after silence so the same note can be re-played.
            if Date().timeIntervalSince(lastMatchTime) > 0.5 {
                lastMatchedPitch = nil
            }
            // Silence clears the last registered sequence note so that
            // repeated pitch classes (e.g. root at octave) can re-trigger.
            lastSequenceRegistered = nil

            // If we confirmed a card and were waiting for the note to stop,
            // require sustained silence before advancing. A single amplitude
            // dip isn't enough — the note must truly die out.
            if waitingForSilence {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                }
                if let start = silenceStartTime,
                   Date().timeIntervalSince(start) >= silenceDuration {
                    waitingForSilence = false
                    silenceStartTime = nil
                    nextCard()
                }
            }
            return
        }

        // A note is detected — reset the silence timer.
        silenceStartTime = nil

        // EMA smoothing
        if let current = smoothedFrequency {
            let ratio = reading.frequency / current
            if ratio > 1.04 || ratio < 0.96 {
                smoothedFrequency = reading.frequency
            } else {
                smoothedFrequency = current * smoothing + reading.frequency * (1 - smoothing)
            }
        } else {
            smoothedFrequency = reading.frequency
        }

        guard let f = smoothedFrequency, let result = Note.nearest(to: f) else { return }
        let pc = result.note.pitchClass
        activePitchClass = pc

        // ── Stability gate: require N consecutive readings of the same
        //    pitch class before accepting. This prevents attack transients
        //    and unconverged EMA values from triggering wrong matches.
        if pc == candidatePitch {
            candidateCount += 1
        } else {
            candidatePitch = pc
            candidateCount = 1
        }
        guard candidateCount >= confirmationsNeeded else { return }

        // Only process if session is active and not already showing final feedback.
        guard isSessionActive else { return }
        switch feedback {
        case .correct, .incorrect, .revealed: return
        case .none, .holding: break
        }

        evaluateInput(pc)
    }

    private func evaluateInput(_ played: PitchClass) {
        guard let card = currentCard else { return }

        switch card.type {
        case .scaleSequence:
            evaluateSequenceInput(played, card: card)
        case .scaleDegree, .noteID, .interval:
            evaluateSingleInput(played, card: card)
        case .chordID:
            // Chord cards are handled by ingestChord, not single-note pitch.
            break
        }
    }

    // MARK: - Single-note hold-to-confirm

    private func evaluateSingleInput(_ played: PitchClass, card: FlashCard) {
        guard let expected = card.expectedPitchClass else { return }

        if played == expected {
            // Correct note — start or continue holding.
            if holdingPitchClass == played, let start = holdStartTime {
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(elapsed / holdDuration, 1.0)
                feedback = .holding(progress: progress)

                if progress >= 1.0 {
                    // Confirmed!
                    totalAttempts += 1
                    correctCount += 1
                    feedback = .correct
                    resetHold()
                    lastMatchedPitch = played
                    lastMatchTime = Date()
                    scheduleAdvance()
                }
            } else {
                // Start a new hold.
                holdingPitchClass = played
                holdStartTime = Date()
                feedback = .holding(progress: 0)
            }
        } else {
            // Wrong note — only penalize if they were committed (held briefly).
            if holdingPitchClass != played {
                resetHold()

                // Debounce: don't penalize the same wrong note repeatedly.
                if played == lastMatchedPitch && Date().timeIntervalSince(lastMatchTime) < 0.5 {
                    return
                }

                totalAttempts += 1
                incorrectCount += 1
                lastMatchedPitch = played
                lastMatchTime = Date()

                if strictness == .lenient {
                    feedback = .incorrect(
                        expected: expected.sharpName,
                        got: played.sharpName
                    )
                    scheduleAdvance(delay: 1.5)
                } else {
                    feedback = .incorrect(
                        expected: expected.sharpName,
                        got: played.sharpName
                    )
                    advanceTask?.cancel()
                    advanceTask = Task {
                        try? await Task.sleep(for: .seconds(1.0))
                        guard !Task.isCancelled else { return }
                        feedback = .none
                    }
                }
            }
        }
    }

    // MARK: - Sequence (fluid, no hold)

    /// The last pitch class that was registered as a sequence step. Used to
    /// detect note *changes* — we only advance when we hear a different note
    /// (or after silence resets this). This lets the user sustain each note
    /// naturally without double-triggering, while still handling repeated
    /// pitch classes in the scale (e.g. root appears at octave boundaries).
    private var lastSequenceRegistered: PitchClass?

    private func evaluateSequenceInput(_ played: PitchClass, card: FlashCard) {
        guard sequencePosition < card.expectedSequence.count else { return }
        let expected = card.expectedSequence[sequencePosition]

        // Don't evaluate until the note changes from whatever was last
        // registered. This prevents a sustained note from re-triggering.
        // Exception: if the expected note equals the last registered note
        // (repeated pitch class in sequence, e.g. octave root), we require
        // a silence gap first — handled by the silence branch clearing
        // lastSequenceRegistered.
        if played == lastSequenceRegistered { return }

        if played == expected {
            // Correct — register immediately, advance.
            sequenceTrail.append(SequenceStep(pitchClass: played, isCorrect: true))
            sequencePosition += 1
            lastSequenceRegistered = played
            feedback = .none

            if sequencePosition >= card.expectedSequence.count {
                // Completed the full sequence!
                totalAttempts += 1
                correctCount += 1
                feedback = .correct
                scheduleAdvance()
            }
        } else {
            // Wrong note.
            lastSequenceRegistered = played

            if strictness == .lenient {
                // Log it as wrong but keep waiting for the right note.
                // Don't advance the sequence position — just show feedback
                // briefly so the user knows they missed.
                sequenceTrail.append(SequenceStep(pitchClass: played, isCorrect: false))
                incorrectCount += 1
                feedback = .incorrect(
                    expected: expected.sharpName,
                    got: played.sharpName
                )
                advanceTask?.cancel()
                advanceTask = Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    guard !Task.isCancelled else { return }
                    feedback = .none
                    // Remove the wrong step so the trail stays clean.
                    if let last = sequenceTrail.last, !last.isCorrect {
                        sequenceTrail.removeLast()
                    }
                }
            } else {
                // Strict: same — show error, keep waiting for the right note.
                feedback = .incorrect(
                    expected: expected.sharpName,
                    got: played.sharpName
                )
                incorrectCount += 1
                advanceTask?.cancel()
                advanceTask = Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled else { return }
                    feedback = .none
                }
            }
        }
    }

    private func resetHold() {
        holdingPitchClass = nil
        holdStartTime = nil
    }

    private func resetChordHold() {
        holdingChord = nil
        chordHoldStartTime = nil
    }

    private func scheduleAdvance(delay: Double = 1.0) {
        advanceTask?.cancel()
        // Prefer advancing once the note stops ringing so it doesn't bleed
        // into the next card — but cap the wait. If the player keeps making
        // sound (noodling after a wrong answer), advance after `delay` anyway.
        waitingForSilence = true
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, waitingForSilence else { return }
            waitingForSilence = false
            silenceStartTime = nil
            nextCard()
        }
    }

    // MARK: - Chord ingestion (for chordID cards)

    private func ingestChord(_ detected: DetectedChord?) {
        // Update the displayed chord regardless of card type.
        if let detected {
            detectedChord = detected.chord
            chordConfidence = detected.confidence
        } else {
            detectedChord = nil
            chordConfidence = 0
            candidateChordForCard = nil
            candidateChordCardCount = 0
            wrongChordCandidate = nil
            wrongChordStartTime = nil
            // Chord released — if waiting for silence, treat as silence.
            if waitingForSilence {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                }
                if let start = silenceStartTime,
                   Date().timeIntervalSince(start) >= silenceDuration {
                    waitingForSilence = false
                    silenceStartTime = nil
                    nextCard()
                }
            }
            return
        }

        // Only evaluate chord for chordID cards during active sessions.
        guard isSessionActive,
              let card = currentCard,
              card.type == .chordID,
              let detected else { return }

        // Don't evaluate if we're showing final feedback.
        switch feedback {
        case .correct, .incorrect, .revealed: return
        case .none, .holding: break
        }

        // Reset silence timer since we have a chord.
        silenceStartTime = nil

        evaluateChordInput(detected, card: card)
    }

    private func evaluateChordInput(_ detected: DetectedChord, card: FlashCard) {
        guard let expectedChord = card.expectedChord else { return }

        // Stability gate: require consecutive readings of the same chord.
        if detected.chord == candidateChordForCard {
            candidateChordCardCount += 1
        } else {
            candidateChordForCard = detected.chord
            candidateChordCardCount = 1
        }
        guard candidateChordCardCount >= chordConfirmationsNeeded else { return }

        if detected.chord == expectedChord {
            // Correct chord — hold-to-confirm.
            wrongChordCandidate = nil
            wrongChordStartTime = nil
            if holdingChord == detected.chord, let start = chordHoldStartTime {
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(elapsed / chordHoldDuration, 1.0)
                feedback = .holding(progress: progress)

                if progress >= 1.0 {
                    totalAttempts += 1
                    correctCount += 1
                    feedback = .correct
                    resetChordHold()
                    scheduleAdvance()
                }
            } else {
                holdingChord = detected.chord
                chordHoldStartTime = Date()
                feedback = .holding(progress: 0)
            }
        } else {
            // Wrong chord — but only if *sustained*. Strum attacks read as
            // partial voicings for the first ~100 ms, so a wrong chord must
            // ring continuously for the grace duration before it counts.
            if wrongChordCandidate != detected.chord {
                wrongChordCandidate = detected.chord
                wrongChordStartTime = Date()
                return
            }
            guard let start = wrongChordStartTime,
                  Date().timeIntervalSince(start) >= wrongChordGraceDuration else { return }
            wrongChordCandidate = nil
            wrongChordStartTime = nil

            resetChordHold()

            totalAttempts += 1
            incorrectCount += 1

            if strictness == .lenient {
                feedback = .incorrect(
                    expected: expectedChord.name,
                    got: detected.chord.name
                )
                scheduleAdvance(delay: 1.5)
            } else {
                feedback = .incorrect(
                    expected: expectedChord.name,
                    got: detected.chord.name
                )
                advanceTask?.cancel()
                advanceTask = Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    guard !Task.isCancelled else { return }
                    feedback = .none
                }
            }
        }
    }
}
