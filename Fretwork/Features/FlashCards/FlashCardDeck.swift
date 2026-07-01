import Foundation

// MARK: - Card types

/// A single flash card with a prompt and one or more expected answers.
struct FlashCard: Identifiable, Hashable, Sendable {
    let id = UUID()
    let type: CardType
    let prompt: String
    /// Human-readable answer description, e.g. "E" or "E4".
    let answerDescription: String
    /// The pitch class(es) accepted as correct. For single-note cards this has
    /// one element; for sequences it's the full ordered sequence.
    let expectedSequence: [PitchClass]
    /// For chord ID cards: the expected chord (root + quality).
    let expectedChord: Chord?

    /// Convenience for single-answer cards.
    var expectedPitchClass: PitchClass? { expectedSequence.first }

    /// Standard init for pitch-based cards.
    init(type: CardType, prompt: String, answerDescription: String, expectedSequence: [PitchClass]) {
        self.type = type
        self.prompt = prompt
        self.answerDescription = answerDescription
        self.expectedSequence = expectedSequence
        self.expectedChord = nil
    }

    /// Init for chord ID cards.
    init(type: CardType, prompt: String, answerDescription: String, expectedChord: Chord) {
        self.type = type
        self.prompt = prompt
        self.answerDescription = answerDescription
        self.expectedSequence = expectedChord.pitchClasses
        self.expectedChord = expectedChord
    }
}

enum CardType: String, Hashable, Sendable, CaseIterable, Identifiable {
    case scaleDegree
    case scaleSequence
    case noteID
    case interval
    case chordID

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scaleDegree:   "Scale Degrees"
        case .scaleSequence: "Scale Sequences"
        case .noteID:        "Note ID"
        case .interval:      "Intervals"
        case .chordID:       "Chord ID"
        }
    }

    var symbolName: String {
        switch self {
        case .scaleDegree:   "music.note"
        case .scaleSequence: "music.note.list"
        case .noteID:        "guitars"
        case .interval:      "arrow.up.right"
        case .chordID:       "pianokeys"
        }
    }

    var description: String {
        switch self {
        case .scaleDegree:   "Play the requested scale degree"
        case .scaleSequence: "Play a full scale ascending or descending"
        case .noteID:        "Name the note at a fretboard position"
        case .interval:      "Play a note at the given interval"
        case .chordID:       "Play the requested chord"
        }
    }
}

// MARK: - Deck

/// A named collection of flash cards with metadata.
struct FlashCardDeck: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: CardType
    let cards: [FlashCard]

    static func == (lhs: FlashCardDeck, rhs: FlashCardDeck) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Deck generator

/// Creates flash card decks from the MusicTheory catalog.
enum DeckGenerator {

    /// All available pre-built decks.
    static func allDecks(tuning: Tuning = .standard) -> [FlashCardDeck] {
        var decks: [FlashCardDeck] = []
        decks.append(contentsOf: scaleDegreeDecks())
        decks.append(contentsOf: scaleSequenceDecks())
        decks.append(contentsOf: noteIDDecks(tuning: tuning))
        decks.append(contentsOf: intervalDecks())
        decks.append(contentsOf: chordIDDecks())
        return decks
    }

    // MARK: - Scale degree cards

    /// One deck per scale: "Play the Nth degree of [Root] [Scale]".
    static func scaleDegreeDecks() -> [FlashCardDeck] {
        let roots: [PitchClass] = [.c, .g, .d, .a, .e, .f, .aSharp, .dSharp]
        let scales: [Scale] = [.major, .naturalMinor, .majorPentatonic, .minorPentatonic, .blues, .dorian, .mixolydian]

        return scales.map { scale in
            let cards = roots.flatMap { root -> [FlashCard] in
                let pcs = scale.pitchClasses(in: root)
                let degrees = scaleDegreeLabels(for: scale)
                return pcs.enumerated().map { i, pc in
                    FlashCard(
                        type: .scaleDegree,
                        prompt: "Play the \(degrees[i]) of \(root.sharpName) \(scale.name)",
                        answerDescription: pc.sharpName,
                        expectedSequence: [pc]
                    )
                }
            }
            return FlashCardDeck(
                id: "scale-degree-\(scale.id)",
                name: "\(scale.name) Degrees",
                type: .scaleDegree,
                cards: cards.shuffled()
            )
        }
    }

    // MARK: - Scale sequence cards

    /// "Play [Root] [Scale] ascending/descending over N octaves."
    static func scaleSequenceDecks() -> [FlashCardDeck] {
        let roots: [PitchClass] = [.c, .g, .d, .a, .e, .f]
        let scales: [Scale] = [.major, .naturalMinor, .majorPentatonic, .minorPentatonic, .blues]

        var cards: [FlashCard] = []
        for scale in scales {
            for root in roots {
                // Ascending 2 octaves
                let ascending = scaleSequence(root: root, scale: scale, octaves: 2, descending: false)
                cards.append(FlashCard(
                    type: .scaleSequence,
                    prompt: "Play \(root.sharpName) \(scale.name) ascending (2 octaves)",
                    answerDescription: ascending.map(\.sharpName).joined(separator: " "),
                    expectedSequence: ascending
                ))
                // Descending 2 octaves
                let descending = scaleSequence(root: root, scale: scale, octaves: 2, descending: true)
                cards.append(FlashCard(
                    type: .scaleSequence,
                    prompt: "Play \(root.sharpName) \(scale.name) descending (2 octaves)",
                    answerDescription: descending.map(\.sharpName).joined(separator: " "),
                    expectedSequence: descending
                ))
            }
        }

        return [FlashCardDeck(
            id: "scale-sequences",
            name: "Scale Sequences",
            type: .scaleSequence,
            cards: cards.shuffled()
        )]
    }

    /// Generates the pitch class sequence for a scale over N octaves.
    private static func scaleSequence(root: PitchClass, scale: Scale,
                                       octaves: Int, descending: Bool) -> [PitchClass] {
        let oneOctave = scale.pitchClasses(in: root)
        var sequence: [PitchClass] = []
        for _ in 0..<octaves {
            sequence.append(contentsOf: oneOctave)
        }
        // Add the final root to complete the run.
        sequence.append(root)
        if descending { sequence.reverse() }
        return sequence
    }

    // MARK: - Note ID cards

    /// "What note is at string N, fret N?"
    static func noteIDDecks(tuning: Tuning) -> [FlashCardDeck] {
        let fb = Fretboard(tuning: tuning)
        let maxFret = 12  // Keep it practical
        var cards: [FlashCard] = []

        for s in 0..<fb.stringCount {
            let stringLabel = tuning.openStrings[s].pitchClass.sharpName
            for f in 0...maxFret {
                let note = fb.note(string: s, fret: f)
                let fretLabel = f == 0 ? "open" : "fret \(f)"
                cards.append(FlashCard(
                    type: .noteID,
                    prompt: "What note is on the \(stringLabel) string, \(fretLabel)?",
                    answerDescription: note.pitchClass.sharpName,
                    expectedSequence: [note.pitchClass]
                ))
            }
        }

        return [FlashCardDeck(
            id: "note-id-\(tuning.id)",
            name: "Note ID (\(tuning.name))",
            type: .noteID,
            cards: cards.shuffled()
        )]
    }

    // MARK: - Interval cards

    /// "Play a [interval] above [note]."
    static func intervalDecks() -> [FlashCardDeck] {
        let intervals: [(Interval, String)] = [
            (.minorSecond, "minor 2nd"),
            (.majorSecond, "major 2nd"),
            (.minorThird, "minor 3rd"),
            (.majorThird, "major 3rd"),
            (.perfectFourth, "perfect 4th"),
            (.tritone, "tritone"),
            (.perfectFifth, "perfect 5th"),
            (.minorSixth, "minor 6th"),
            (.majorSixth, "major 6th"),
            (.minorSeventh, "minor 7th"),
            (.majorSeventh, "major 7th"),
            (.perfectOctave, "octave"),
        ]
        let roots: [PitchClass] = PitchClass.allCases

        var cards: [FlashCard] = []
        for (interval, name) in intervals {
            for root in roots {
                let target = root.transposed(by: interval.semitones)
                cards.append(FlashCard(
                    type: .interval,
                    prompt: "Play a \(name) above \(root.sharpName)",
                    answerDescription: target.sharpName,
                    expectedSequence: [target]
                ))
            }
        }

        return [FlashCardDeck(
            id: "intervals",
            name: "Interval Training",
            type: .interval,
            cards: cards.shuffled()
        )]
    }

    // MARK: - Chord ID cards

    /// "Play a [Chord]" — detected via chord analyzer, not single-note pitch.
    static func chordIDDecks() -> [FlashCardDeck] {
        // Common guitar chord roots (open chords + barre-friendly keys)
        let roots: [PitchClass] = [.c, .d, .e, .f, .g, .a, .b,
                                    .cSharp, .fSharp, .aSharp]

        // Triads deck
        let triadQualities: [ChordQuality] = [.major, .minor, .diminished, .augmented,
                                               .suspended2, .suspended4]
        var triadCards: [FlashCard] = []
        for root in roots {
            for quality in triadQualities {
                let chord = Chord(root: root, quality: quality)
                triadCards.append(FlashCard(
                    type: .chordID,
                    prompt: "Play \(chord.name)",
                    answerDescription: chord.name,
                    expectedChord: chord
                ))
            }
        }

        // Seventh chords deck
        let seventhQualities: [ChordQuality] = [.dominant7, .major7, .minor7,
                                                  .minor7b5, .diminished7]
        var seventhCards: [FlashCard] = []
        for root in roots {
            for quality in seventhQualities {
                let chord = Chord(root: root, quality: quality)
                seventhCards.append(FlashCard(
                    type: .chordID,
                    prompt: "Play \(chord.name)",
                    answerDescription: chord.name,
                    expectedChord: chord
                ))
            }
        }

        return [
            FlashCardDeck(
                id: "chord-triads",
                name: "Chord Triads",
                type: .chordID,
                cards: triadCards.shuffled()
            ),
            FlashCardDeck(
                id: "chord-sevenths",
                name: "Seventh Chords",
                type: .chordID,
                cards: seventhCards.shuffled()
            )
        ]
    }

    // MARK: - Helpers

    /// Same degree label logic as FretboardViewModel, extracted for reuse.
    static func scaleDegreeLabels(for scale: Scale) -> [String] {
        let majorIntervals = Scale.major.intervals

        if scale.intervals.count == majorIntervals.count {
            return scale.intervals.enumerated().map { index, semitones in
                let natural = majorIntervals[index]
                if semitones == natural     { return "\(index + 1)" }
                if semitones == natural - 1 { return "b\(index + 1)" }
                if semitones == natural + 1 { return "#\(index + 1)" }
                return "\(index + 1)"
            }
        }

        return scale.intervals.map { semitones in
            if let mi = majorIntervals.firstIndex(of: semitones) {
                return "\(mi + 1)"
            }
            if let mi = majorIntervals.firstIndex(of: semitones + 1) {
                return "b\(mi + 1)"
            }
            if let mi = majorIntervals.firstIndex(of: semitones - 1) {
                return "#\(mi + 1)"
            }
            return "?"
        }
    }
}
