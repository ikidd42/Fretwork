import Foundation

/// A guitar tuning — the open-string pitches from low (string 6) to high (string 1).
///
/// `openStrings[0]` is the lowest string. Standard tuning is E2 A2 D3 G3 B3 E4.
nonisolated
struct Tuning: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let openStrings: [Note]

    init(id: String, name: String, openStrings: [Note]) {
        self.id = id
        self.name = name
        self.openStrings = openStrings
    }

    var stringCount: Int { openStrings.count }
}

nonisolated extension Tuning {
    static let standard = Tuning(
        id: "standard",
        name: "Standard (EADGBE)",
        openStrings: [
            Note(pitchClass: .e, octave: 2),
            Note(pitchClass: .a, octave: 2),
            Note(pitchClass: .d, octave: 3),
            Note(pitchClass: .g, octave: 3),
            Note(pitchClass: .b, octave: 3),
            Note(pitchClass: .e, octave: 4),
        ]
    )

    static let dropD = Tuning(
        id: "drop-d",
        name: "Drop D (DADGBE)",
        openStrings: [
            Note(pitchClass: .d, octave: 2),
            Note(pitchClass: .a, octave: 2),
            Note(pitchClass: .d, octave: 3),
            Note(pitchClass: .g, octave: 3),
            Note(pitchClass: .b, octave: 3),
            Note(pitchClass: .e, octave: 4),
        ]
    )

    static let dadgad = Tuning(
        id: "dadgad",
        name: "DADGAD",
        openStrings: [
            Note(pitchClass: .d, octave: 2),
            Note(pitchClass: .a, octave: 2),
            Note(pitchClass: .d, octave: 3),
            Note(pitchClass: .g, octave: 3),
            Note(pitchClass: .a, octave: 3),
            Note(pitchClass: .d, octave: 4),
        ]
    )

    static let openG = Tuning(
        id: "open-g",
        name: "Open G (DGDGBD)",
        openStrings: [
            Note(pitchClass: .d, octave: 2),
            Note(pitchClass: .g, octave: 2),
            Note(pitchClass: .d, octave: 3),
            Note(pitchClass: .g, octave: 3),
            Note(pitchClass: .b, octave: 3),
            Note(pitchClass: .d, octave: 4),
        ]
    )

    static let halfStepDown = Tuning(
        id: "half-step-down",
        name: "Eb Standard",
        openStrings: [
            Note(pitchClass: .dSharp, octave: 2),
            Note(pitchClass: .gSharp, octave: 2),
            Note(pitchClass: .cSharp, octave: 3),
            Note(pitchClass: .fSharp, octave: 3),
            Note(pitchClass: .aSharp, octave: 3),
            Note(pitchClass: .dSharp, octave: 4),
        ]
    )

    static let catalog: [Tuning] = [.standard, .dropD, .dadgad, .openG, .halfStepDown]
}
