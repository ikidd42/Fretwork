import Foundation

/// One of the twelve pitch classes (a note's identity ignoring octave).
///
/// `rawValue` is the number of semitones above C, so equality and arithmetic
/// modulo 12 work directly: `PitchClass(rawValue: 7) == .g`.
nonisolated
enum PitchClass: Int, CaseIterable, Hashable, Sendable {
    case c = 0
    case cSharp
    case d
    case dSharp
    case e
    case f
    case fSharp
    case g
    case gSharp
    case a
    case aSharp
    case b

    /// Name using sharps, e.g. `"C#"`, `"F#"`.
    var sharpName: String {
        switch self {
        case .c:       "C"
        case .cSharp:  "C#"
        case .d:       "D"
        case .dSharp:  "D#"
        case .e:       "E"
        case .f:       "F"
        case .fSharp:  "F#"
        case .g:       "G"
        case .gSharp:  "G#"
        case .a:       "A"
        case .aSharp:  "A#"
        case .b:       "B"
        }
    }

    /// Name using flats, e.g. `"Db"`, `"Gb"`.
    var flatName: String {
        switch self {
        case .c:       "C"
        case .cSharp:  "Db"
        case .d:       "D"
        case .dSharp:  "Eb"
        case .e:       "E"
        case .f:       "F"
        case .fSharp:  "Gb"
        case .g:       "G"
        case .gSharp:  "Ab"
        case .a:       "A"
        case .aSharp:  "Bb"
        case .b:       "B"
        }
    }

    func name(preferring accidental: Accidental = .sharp) -> String {
        accidental == .sharp ? sharpName : flatName
    }

    /// Transpose by a (positive or negative) number of semitones, wrapping at the octave.
    func transposed(by semitones: Int) -> PitchClass {
        let mod = ((rawValue + semitones) % 12 + 12) % 12
        return PitchClass(rawValue: mod)!
    }
}

nonisolated
enum Accidental: Hashable, Sendable {
    case sharp
    case flat
}
