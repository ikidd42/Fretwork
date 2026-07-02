import Foundation

/// Pure data model of a fretted instrument's geometry: which note sits at every
/// `(string, fret)` location for a given tuning. Knows nothing about drawing.
///
/// `string` indexes are 0-based from the lowest pitch up — string 0 is low E in standard.
nonisolated
struct Fretboard: Hashable, Sendable {
    let tuning: Tuning
    let fretCount: Int

    init(tuning: Tuning = .standard, fretCount: Int = 22) {
        self.tuning = tuning
        self.fretCount = fretCount
    }

    var stringCount: Int { tuning.stringCount }

    /// Note at `(string, fret)`. Open string is fret 0.
    func note(string: Int, fret: Int) -> Note {
        precondition((0..<stringCount).contains(string), "string index out of range")
        precondition((0...fretCount).contains(fret), "fret index out of range")
        return tuning.openStrings[string].transposed(by: Interval(semitones: fret))
    }

    /// Every `(string, fret)` position where the given pitch class appears.
    func positions(of pitchClass: PitchClass) -> [Position] {
        var result: [Position] = []
        for s in 0..<stringCount {
            for f in 0...fretCount {
                if note(string: s, fret: f).pitchClass == pitchClass {
                    result.append(Position(string: s, fret: f))
                }
            }
        }
        return result
    }

    /// Every position whose pitch class is in `pitchClasses`.
    func positions(in pitchClasses: Set<PitchClass>) -> [Position] {
        pitchClasses.flatMap { positions(of: $0) }
    }

    struct Position: Hashable, Sendable {
        let string: Int
        let fret: Int
    }
}
