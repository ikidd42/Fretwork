import Foundation

/// A chord type independent of root — defined by its interval stack.
struct ChordQuality: Hashable, Sendable, Identifiable {
    let id: String
    /// Human-readable name, e.g. `"Minor 7"`.
    let name: String
    /// Suffix appended to the root letter, e.g. `""`, `"m"`, `"7"`, `"maj7"`.
    let symbol: String
    /// Semitones above the root.
    let intervals: [Int]

    init(id: String, name: String, symbol: String, intervals: [Int]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.intervals = intervals
    }
}

extension ChordQuality {
    // Triads
    static let major       = ChordQuality(id: "maj",  name: "Major",       symbol: "",     intervals: [0, 4, 7])
    static let minor       = ChordQuality(id: "min",  name: "Minor",       symbol: "m",    intervals: [0, 3, 7])
    static let diminished  = ChordQuality(id: "dim",  name: "Diminished",  symbol: "dim",  intervals: [0, 3, 6])
    static let augmented   = ChordQuality(id: "aug",  name: "Augmented",   symbol: "aug",  intervals: [0, 4, 8])
    static let suspended2  = ChordQuality(id: "sus2", name: "Suspended 2", symbol: "sus2", intervals: [0, 2, 7])
    static let suspended4  = ChordQuality(id: "sus4", name: "Suspended 4", symbol: "sus4", intervals: [0, 5, 7])

    // Sevenths
    static let dominant7   = ChordQuality(id: "7",     name: "Dominant 7",  symbol: "7",     intervals: [0, 4, 7, 10])
    static let major7      = ChordQuality(id: "maj7",  name: "Major 7",     symbol: "maj7",  intervals: [0, 4, 7, 11])
    static let minor7      = ChordQuality(id: "m7",    name: "Minor 7",     symbol: "m7",    intervals: [0, 3, 7, 10])
    static let minor7b5    = ChordQuality(id: "m7b5",  name: "Half-Dim 7",  symbol: "m7♭5",  intervals: [0, 3, 6, 10])
    static let diminished7 = ChordQuality(id: "dim7",  name: "Diminished 7",symbol: "dim7",  intervals: [0, 3, 6, 9])
    static let minorMajor7 = ChordQuality(id: "mMaj7", name: "Minor/Major 7",symbol: "mMaj7",intervals: [0, 3, 7, 11])

    static let catalog: [ChordQuality] = [
        .major, .minor, .diminished, .augmented, .suspended2, .suspended4,
        .dominant7, .major7, .minor7, .minor7b5, .diminished7, .minorMajor7
    ]
}

/// A specific chord — root pitch class + quality.
struct Chord: Hashable, Sendable, Identifiable {
    let root: PitchClass
    let quality: ChordQuality

    var id: String { "\(root.sharpName)-\(quality.id)" }

    var name: String {
        root.sharpName + quality.symbol
    }

    var pitchClasses: [PitchClass] {
        quality.intervals.map { root.transposed(by: $0) }
    }

    /// Concrete notes voiced upward from a starting note (basic close voicing).
    func notes(rootedAt rootNote: Note) -> [Note] {
        quality.intervals.map { rootNote.transposed(by: Interval(semitones: $0)) }
    }
}
