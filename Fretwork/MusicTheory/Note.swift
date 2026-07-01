import Foundation

/// A specific pitch — pitch class plus octave (scientific pitch notation).
///
/// `Note(pitchClass: .a, octave: 4)` is concert A (440 Hz).
struct Note: Hashable, Sendable {
    let pitchClass: PitchClass
    let octave: Int

    /// MIDI note number — C-1 = 0, C4 = 60, A4 = 69.
    var midiNumber: Int {
        (octave + 1) * 12 + pitchClass.rawValue
    }

    /// Frequency in Hz at A4 = 440, equal temperament.
    var frequency: Double {
        Self.referenceFrequency * pow(2, Double(midiNumber - Self.referenceMidi) / 12)
    }

    func name(preferring accidental: Accidental = .sharp) -> String {
        "\(pitchClass.name(preferring: accidental))\(octave)"
    }

    /// Tuning reference. Exposed so a future "tune to A=442" preference can change it.
    static let referenceFrequency: Double = 440
    static let referenceMidi: Int = 69

    /// Closest equal-tempered note to a given frequency, plus the deviation in cents
    /// (positive = sharp, negative = flat). `centsOff` is in `[-50, 50)`.
    static func nearest(to frequency: Double) -> (note: Note, centsOff: Double)? {
        guard frequency > 0 else { return nil }
        let midi = Double(referenceMidi) + 12 * log2(frequency / referenceFrequency)
        let rounded = Int(midi.rounded())
        let centsOff = (midi - Double(rounded)) * 100
        let pcRaw = ((rounded % 12) + 12) % 12
        guard let pc = PitchClass(rawValue: pcRaw) else { return nil }
        let octave = (rounded / 12) - 1
        return (Note(pitchClass: pc, octave: octave), centsOff)
    }
}

extension Note: Comparable {
    static func < (lhs: Note, rhs: Note) -> Bool {
        lhs.midiNumber < rhs.midiNumber
    }
}
