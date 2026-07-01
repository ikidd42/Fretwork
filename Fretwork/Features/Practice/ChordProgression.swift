import Foundation

/// A chord progression defined as scale-degree numerals (Roman numeral analysis).
///
/// Each step is a `Degree` — a 1-based scale degree + chord quality — so the
/// same progression works in any key. Resolve to concrete `Chord` values with
/// `chords(in:scale:)`.
struct ChordProgression: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let degrees: [Degree]
    /// Beats to hold each chord. Defaults to 4 (one measure in 4/4).
    let beatsPerChord: Int

    init(id: String, name: String, degrees: [Degree], beatsPerChord: Int = 4) {
        self.id = id
        self.name = name
        self.degrees = degrees
        self.beatsPerChord = beatsPerChord
    }

    /// A single step in the progression.
    struct Degree: Hashable, Sendable {
        /// 1-based scale degree (1 = tonic, 4 = subdominant, 5 = dominant…).
        let scaleDegree: Int
        let quality: ChordQuality
        /// Roman numeral label, e.g. "I", "ii", "V7".
        let label: String
    }

    /// Resolve this progression to concrete chords in the given key.
    func chords(in root: PitchClass, scale: Scale = .major) -> [Chord] {
        let scalePCs = scale.pitchClasses(in: root)
        return degrees.map { degree in
            let index = (degree.scaleDegree - 1) % scalePCs.count
            let chordRoot = scalePCs[index]
            return Chord(root: chordRoot, quality: degree.quality)
        }
    }
}

// MARK: - Catalog

extension ChordProgression {

    // Helper to build degrees concisely
    private static func deg(_ n: Int, _ q: ChordQuality, _ label: String) -> Degree {
        Degree(scaleDegree: n, quality: q, label: label)
    }

    static let oneForFiveOne = ChordProgression(
        id: "I-IV-V-I",
        name: "I – IV – V – I",
        degrees: [
            deg(1, .major, "I"),
            deg(4, .major, "IV"),
            deg(5, .major, "V"),
            deg(1, .major, "I"),
        ]
    )

    static let twoFiveOne = ChordProgression(
        id: "ii-V-I",
        name: "ii – V – I",
        degrees: [
            deg(2, .minor, "ii"),
            deg(5, .major, "V"),
            deg(1, .major, "I"),
        ]
    )

    static let oneSixFourFive = ChordProgression(
        id: "I-vi-IV-V",
        name: "I – vi – IV – V",
        degrees: [
            deg(1, .major, "I"),
            deg(6, .minor, "vi"),
            deg(4, .major, "IV"),
            deg(5, .major, "V"),
        ]
    )

    static let oneFiveSixFour = ChordProgression(
        id: "I-V-vi-IV",
        name: "I – V – vi – IV",
        degrees: [
            deg(1, .major, "I"),
            deg(5, .major, "V"),
            deg(6, .minor, "vi"),
            deg(4, .major, "IV"),
        ]
    )

    static let twelveBarBlues = ChordProgression(
        id: "12-bar-blues",
        name: "12-Bar Blues",
        degrees: [
            deg(1, .dominant7, "I7"),
            deg(1, .dominant7, "I7"),
            deg(1, .dominant7, "I7"),
            deg(1, .dominant7, "I7"),
            deg(4, .dominant7, "IV7"),
            deg(4, .dominant7, "IV7"),
            deg(1, .dominant7, "I7"),
            deg(1, .dominant7, "I7"),
            deg(5, .dominant7, "V7"),
            deg(4, .dominant7, "IV7"),
            deg(1, .dominant7, "I7"),
            deg(5, .dominant7, "V7"),
        ]
    )

    static let minorOneForFive = ChordProgression(
        id: "i-iv-v-i",
        name: "i – iv – v – i (minor)",
        degrees: [
            deg(1, .minor, "i"),
            deg(4, .minor, "iv"),
            deg(5, .minor, "v"),
            deg(1, .minor, "i"),
        ]
    )

    static let catalog: [ChordProgression] = [
        .oneForFiveOne,
        .twoFiveOne,
        .oneSixFourFive,
        .oneFiveSixFour,
        .twelveBarBlues,
        .minorOneForFive,
    ]
}
