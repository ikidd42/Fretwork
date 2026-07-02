import XCTest
@testable import Fretwork

/// The MusicTheory layer is pure data — no audio, no UI — so these tests
/// pin down the arithmetic everything else leans on: MIDI/frequency
/// conversion, nearest-note resolution, transposition wrapping, scale and
/// chord spelling, and fretboard geometry.
final class MusicTheoryTests: XCTestCase {

    // MARK: - Note fundamentals

    func testMidiNumbersMatchScientificPitchNotation() {
        XCTAssertEqual(Note(pitchClass: .a, octave: 4).midiNumber, 69)
        XCTAssertEqual(Note(pitchClass: .c, octave: 4).midiNumber, 60)
        XCTAssertEqual(Note(pitchClass: .c, octave: -1).midiNumber, 0)
        XCTAssertEqual(Note(pitchClass: .e, octave: 2).midiNumber, 40)  // low E string
    }

    func testFrequencyAtEqualTemperamentReferences() {
        XCTAssertEqual(Note(pitchClass: .a, octave: 4).frequency, 440, accuracy: 1e-9)
        XCTAssertEqual(Note(pitchClass: .a, octave: 3).frequency, 220, accuracy: 1e-9)
        XCTAssertEqual(Note(pitchClass: .e, octave: 2).frequency, 82.407, accuracy: 0.001)
        XCTAssertEqual(Note(pitchClass: .c, octave: 4).frequency, 261.626, accuracy: 0.001)
    }

    // MARK: - Note.nearest

    /// Every note in the playable range must round-trip exactly through
    /// frequency → nearest, with ~0 cents deviation.
    func testNearestRoundTripsAcrossGuitarRange() {
        // E2 (midi 40) up past the 22nd fret of the high E (midi ~86).
        for midi in 30...100 {
            let pc = PitchClass(rawValue: ((midi % 12) + 12) % 12)!
            let note = Note(pitchClass: pc, octave: (midi / 12) - 1)
            guard let result = Note.nearest(to: note.frequency) else {
                XCTFail("nearest(to:) returned nil for \(note.name())")
                continue
            }
            XCTAssertEqual(result.note, note)
            XCTAssertEqual(result.centsOff, 0, accuracy: 1e-9)
        }
    }

    func testNearestReportsCentsDeviation() {
        // 25 cents sharp of A4.
        let sharp = 440.0 * pow(2, 25.0 / 1200)
        let result = Note.nearest(to: sharp)!
        XCTAssertEqual(result.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(result.centsOff, 25, accuracy: 1e-6)

        // 25 cents flat.
        let flat = 440.0 * pow(2, -25.0 / 1200)
        let flatResult = Note.nearest(to: flat)!
        XCTAssertEqual(flatResult.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(flatResult.centsOff, -25, accuracy: 1e-6)
    }

    func testNearestRejectsNonPositiveFrequencies() {
        XCTAssertNil(Note.nearest(to: 0))
        XCTAssertNil(Note.nearest(to: -440))
    }

    // MARK: - Transposition

    func testPitchClassTranspositionWrapsBothDirections() {
        XCTAssertEqual(PitchClass.b.transposed(by: 1), .c)
        XCTAssertEqual(PitchClass.c.transposed(by: -1), .b)
        XCTAssertEqual(PitchClass.e.transposed(by: 12), .e)
        XCTAssertEqual(PitchClass.g.transposed(by: -24), .g)
        XCTAssertEqual(PitchClass.a.transposed(by: 7), .e)
    }

    func testNoteTranspositionCarriesOctave() {
        let b3 = Note(pitchClass: .b, octave: 3)
        XCTAssertEqual(b3.transposed(by: .minorSecond), Note(pitchClass: .c, octave: 4))
        let c4 = Note(pitchClass: .c, octave: 4)
        XCTAssertEqual(c4.transposed(by: Interval(semitones: -1)), Note(pitchClass: .b, octave: 3))
        XCTAssertEqual(c4.transposed(by: .perfectOctave), Note(pitchClass: .c, octave: 5))
    }

    // MARK: - Interval.shortName

    func testIntervalShortNames() {
        XCTAssertEqual(Interval.unison.shortName, "R")
        XCTAssertEqual(Interval.minorThird.shortName, "b3")
        XCTAssertEqual(Interval.perfectFifth.shortName, "5")
        XCTAssertEqual(Interval.minorSeventh.shortName, "b7")
        XCTAssertEqual(Interval.perfectOctave.shortName, "R")
    }

    /// Regression for the branch fix: Swift's `%` keeps the sign, so
    /// negative intervals used to fall through to "?".
    func testIntervalShortNameFoldsNegativeSemitones() {
        XCTAssertEqual(Interval(semitones: -3).shortName, "6")   // down m3 = up M6
        XCTAssertEqual(Interval(semitones: -12).shortName, "R")
        XCTAssertEqual(Interval(semitones: -1).shortName, "7")
        XCTAssertEqual(Interval(semitones: -25).shortName, "7")
        for s in -36...36 {
            XCTAssertNotEqual(Interval(semitones: s).shortName, "?",
                "shortName should never be '?' (failed for \(s))")
        }
    }

    // MARK: - Scales

    func testMajorScaleSpelling() {
        let cMajor = Scale.major.pitchClasses(in: .c)
        XCTAssertEqual(cMajor, [.c, .d, .e, .f, .g, .a, .b])
        let gMajor = Scale.major.pitchClasses(in: .g)
        XCTAssertEqual(gMajor, [.g, .a, .b, .c, .d, .e, .fSharp])
    }

    func testRelativeMinorSharesPitchClasses() {
        let cMajor = Set(Scale.major.pitchClasses(in: .c))
        let aMinor = Set(Scale.naturalMinor.pitchClasses(in: .a))
        XCTAssertEqual(cMajor, aMinor)
    }

    func testModesOfCMajorShareItsPitchClasses() {
        let cMajor = Set(Scale.major.pitchClasses(in: .c))
        XCTAssertEqual(Set(Scale.dorian.pitchClasses(in: .d)), cMajor)
        XCTAssertEqual(Set(Scale.phrygian.pitchClasses(in: .e)), cMajor)
        XCTAssertEqual(Set(Scale.lydian.pitchClasses(in: .f)), cMajor)
        XCTAssertEqual(Set(Scale.mixolydian.pitchClasses(in: .g)), cMajor)
        XCTAssertEqual(Set(Scale.aeolian.pitchClasses(in: .a)), cMajor)
        XCTAssertEqual(Set(Scale.locrian.pitchClasses(in: .b)), cMajor)
    }

    func testScaleNotesAscendWithinOneOctave() {
        let root = Note(pitchClass: .a, octave: 2)
        let notes = Scale.minorPentatonic.notes(rootedAt: root)
        XCTAssertEqual(notes.first, root)
        XCTAssertEqual(notes, notes.sorted())
        XCTAssertLessThan(notes.last!.midiNumber - root.midiNumber, 12)
    }

    func testScaleDegreeLabels() {
        XCTAssertEqual(DeckGenerator.scaleDegreeLabels(for: .major),
                       ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(DeckGenerator.scaleDegreeLabels(for: .naturalMinor),
                       ["1", "2", "b3", "4", "5", "b6", "b7"])
        XCTAssertEqual(DeckGenerator.scaleDegreeLabels(for: .minorPentatonic),
                       ["1", "b3", "4", "5", "b7"])
        // No scale in the catalog should ever produce an unknown degree.
        for scale in Scale.catalog {
            XCTAssertFalse(DeckGenerator.scaleDegreeLabels(for: scale).contains("?"),
                "\(scale.name) produced a '?' degree label")
        }
    }

    // MARK: - Chords

    func testChordSpelling() {
        XCTAssertEqual(Chord(root: .a, quality: .minor).pitchClasses, [.a, .c, .e])
        XCTAssertEqual(Chord(root: .g, quality: .dominant7).pitchClasses, [.g, .b, .d, .f])
        XCTAssertEqual(Chord(root: .e, quality: .major).pitchClasses, [.e, .gSharp, .b])
        XCTAssertEqual(Chord(root: .b, quality: .diminished).pitchClasses, [.b, .d, .f])
    }

    func testChordNamesUseRootAndSymbol() {
        XCTAssertEqual(Chord(root: .a, quality: .minor).name, "Am")
        XCTAssertEqual(Chord(root: .c, quality: .major).name, "C")
        XCTAssertEqual(Chord(root: .fSharp, quality: .minor7b5).name, "F#m7♭5")
    }

    func testChordNotesVoiceUpwardFromRoot() {
        let notes = Chord(root: .a, quality: .major).notes(rootedAt: Note(pitchClass: .a, octave: 3))
        XCTAssertEqual(notes, [
            Note(pitchClass: .a, octave: 3),
            Note(pitchClass: .cSharp, octave: 4),
            Note(pitchClass: .e, octave: 4),
        ])
    }

    // MARK: - Tuning & fretboard geometry

    func testStandardTuningSpelling() {
        let expected: [Note] = [
            Note(pitchClass: .e, octave: 2),
            Note(pitchClass: .a, octave: 2),
            Note(pitchClass: .d, octave: 3),
            Note(pitchClass: .g, octave: 3),
            Note(pitchClass: .b, octave: 3),
            Note(pitchClass: .e, octave: 4),
        ]
        XCTAssertEqual(Tuning.standard.openStrings, expected)
        for tuning in Tuning.catalog {
            XCTAssertEqual(tuning.stringCount, 6, "\(tuning.name) should have 6 strings")
        }
    }

    /// The classic relative-tuning invariant: fret 5 of each string matches
    /// the next open string — except the G string, where it's fret 4.
    func testStandardTuningRelativeFretInvariant() {
        let board = Fretboard(tuning: .standard)
        for s in 0..<5 {
            let fret = (s == 3) ? 4 : 5
            XCTAssertEqual(board.note(string: s, fret: fret),
                           board.note(string: s + 1, fret: 0),
                           "string \(s) fret \(fret) should equal open string \(s + 1)")
        }
    }

    func testFretboardNoteLookup() {
        let board = Fretboard(tuning: .standard)
        XCTAssertEqual(board.note(string: 0, fret: 0), Note(pitchClass: .e, octave: 2))
        XCTAssertEqual(board.note(string: 0, fret: 12), Note(pitchClass: .e, octave: 3))
        XCTAssertEqual(board.note(string: 5, fret: 5), Note(pitchClass: .a, octave: 4))
    }

    func testFretboardPositionsFindEveryOccurrence() {
        let board = Fretboard(tuning: .standard, fretCount: 12)
        let positions = board.positions(of: .e)
        // Every string crosses E at least once in 12 frets; low/high E twice
        // (open + 12th). 6 strings × 13 positions, E appears 8 times.
        XCTAssertEqual(positions.count, 8)
        for p in positions {
            XCTAssertEqual(board.note(string: p.string, fret: p.fret).pitchClass, .e)
        }
    }
}
