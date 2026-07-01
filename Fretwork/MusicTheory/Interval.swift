import Foundation

/// A musical interval expressed in semitones.
struct Interval: Hashable, Sendable {
    let semitones: Int

    init(semitones: Int) {
        self.semitones = semitones
    }

    static let unison         = Interval(semitones: 0)
    static let minorSecond    = Interval(semitones: 1)
    static let majorSecond    = Interval(semitones: 2)
    static let minorThird     = Interval(semitones: 3)
    static let majorThird     = Interval(semitones: 4)
    static let perfectFourth  = Interval(semitones: 5)
    static let tritone        = Interval(semitones: 6)
    static let perfectFifth   = Interval(semitones: 7)
    static let minorSixth     = Interval(semitones: 8)
    static let majorSixth     = Interval(semitones: 9)
    static let minorSeventh   = Interval(semitones: 10)
    static let majorSeventh   = Interval(semitones: 11)
    static let perfectOctave  = Interval(semitones: 12)

    /// Short label for display in hints, e.g. "3", "b7", "5".
    /// Negative intervals are folded into the octave below (e.g. -3 → "6").
    var shortName: String {
        switch ((semitones % 12) + 12) % 12 {
        case 0:  "R"
        case 1:  "b2"
        case 2:  "2"
        case 3:  "b3"
        case 4:  "3"
        case 5:  "4"
        case 6:  "b5"
        case 7:  "5"
        case 8:  "b6"
        case 9:  "6"
        case 10: "b7"
        case 11: "7"
        default: "?"
        }
    }
}

extension Note {
    /// Note transposed by an interval. Octave handled automatically.
    func transposed(by interval: Interval) -> Note {
        let newMidi = midiNumber + interval.semitones
        let pcRaw = ((newMidi % 12) + 12) % 12
        let octave = (newMidi / 12) - 1
        return Note(pitchClass: PitchClass(rawValue: pcRaw)!, octave: octave)
    }
}
