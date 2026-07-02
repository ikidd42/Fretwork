import Foundation

/// A scale defined by its semitone pattern from the root.
///
/// Modes are ordinary scales — there's nothing magical distinguishing
/// a mode from a "scale" beyond a label. `Dorian` is just a scale that
/// happens to share notes with the major scale a step below its root.
nonisolated
struct Scale: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Semitones above the root, always starting with 0 and ending below 12.
    let intervals: [Int]

    init(id: String, name: String, intervals: [Int]) {
        self.id = id
        self.name = name
        self.intervals = intervals
    }

    /// Pitch classes of this scale rooted at `root`.
    func pitchClasses(in root: PitchClass) -> [PitchClass] {
        intervals.map { root.transposed(by: $0) }
    }

    /// Ascending notes of this scale starting at `root`, one octave.
    func notes(rootedAt root: Note) -> [Note] {
        intervals.map { root.transposed(by: Interval(semitones: $0)) }
    }
}

// MARK: - Catalog

nonisolated extension Scale {
    // Diatonic
    static let major          = Scale(id: "major",          name: "Major",            intervals: [0, 2, 4, 5, 7, 9, 11])
    static let naturalMinor   = Scale(id: "natural-minor",  name: "Natural Minor",    intervals: [0, 2, 3, 5, 7, 8, 10])
    static let harmonicMinor  = Scale(id: "harmonic-minor", name: "Harmonic Minor",   intervals: [0, 2, 3, 5, 7, 8, 11])
    static let melodicMinor   = Scale(id: "melodic-minor",  name: "Melodic Minor",    intervals: [0, 2, 3, 5, 7, 9, 11])

    // Modes (of major)
    static let ionian         = Scale(id: "ionian",     name: "Ionian",     intervals: [0, 2, 4, 5, 7, 9, 11])
    static let dorian         = Scale(id: "dorian",     name: "Dorian",     intervals: [0, 2, 3, 5, 7, 9, 10])
    static let phrygian       = Scale(id: "phrygian",   name: "Phrygian",   intervals: [0, 1, 3, 5, 7, 8, 10])
    static let lydian         = Scale(id: "lydian",     name: "Lydian",     intervals: [0, 2, 4, 6, 7, 9, 11])
    static let mixolydian     = Scale(id: "mixolydian", name: "Mixolydian", intervals: [0, 2, 4, 5, 7, 9, 10])
    static let aeolian        = Scale(id: "aeolian",    name: "Aeolian",    intervals: [0, 2, 3, 5, 7, 8, 10])
    static let locrian        = Scale(id: "locrian",    name: "Locrian",    intervals: [0, 1, 3, 5, 6, 8, 10])

    // Pentatonic / blues
    static let majorPentatonic = Scale(id: "major-pentatonic", name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9])
    static let minorPentatonic = Scale(id: "minor-pentatonic", name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10])
    static let blues           = Scale(id: "blues",            name: "Blues",            intervals: [0, 3, 5, 6, 7, 10])

    /// Default catalog used by flash-card decks and pickers.
    static let catalog: [Scale] = [
        .major, .naturalMinor, .harmonicMinor, .melodicMinor,
        .ionian, .dorian, .phrygian, .lydian, .mixolydian, .aeolian, .locrian,
        .majorPentatonic, .minorPentatonic, .blues
    ]
}
