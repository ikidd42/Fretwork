import Foundation
import Observation

/// Drives the fretboard UI: key/scale selection, scale-degree mapping, and
/// live pitch highlighting from a `PitchDetector`.
///
/// Pattern matches `TunerViewModel`: `@MainActor @Observable`, init takes
/// `(detector:)`, `start() async` + `stop()`.
@MainActor
@Observable
final class FretboardViewModel {

    // MARK: - Scale / key selection

    var selectedRoot: PitchClass = .c {
        didSet { rebuildScaleMap() }
    }

    var selectedScale: Scale = .major {
        didSet { rebuildScaleMap() }
    }

    var selectedTuning: Tuning = .standard {
        didSet { fretboard = Fretboard(tuning: selectedTuning) }
    }

    /// Accidental preference for display labels.
    var accidental: Accidental = .sharp

    // MARK: - Fretboard model

    private(set) var fretboard = Fretboard(tuning: .standard)

    /// Number of frets to display (0 = open through this value).
    var displayFretCount: Int = 15

    // MARK: - Scale degree map

    /// Maps each `PitchClass` in the current scale to its 1-based degree string.
    /// E.g. in C major: C→"1", D→"2", E→"3", F→"4", G→"5", A→"6", B→"7".
    private(set) var scaleDegreeMap: [PitchClass: String] = [:]

    /// The set of pitch classes in the current key/scale, for quick membership tests.
    private(set) var scalePitchClasses: Set<PitchClass> = []

    // MARK: - Live pitch detection

    private(set) var permission: AudioPermission.Status = .undetermined
    private(set) var isListening: Bool = false
    private(set) var lastError: String?

    /// The pitch class currently being played (above amplitude threshold), or nil.
    private(set) var activePitchClass: PitchClass?

    /// The specific note (with octave) currently detected.
    private(set) var activeNote: Note?

    /// Smoothed frequency, same EMA approach as TunerViewModel.
    private var smoothedFrequency: Double?

    // MARK: - Chord detection

    /// The currently detected chord, or nil.
    private(set) var detectedChord: Chord?
    /// Confidence of the current chord detection [0, 1].
    private(set) var chordConfidence: Double = 0
    /// Whether to show chord detection overlay on the fretboard.
    var showChordDetection: Bool = false

    /// Stability: require the same chord for N frames before displaying.
    /// At 128 frames / 48 kHz the IOProc fires every ~2.7 ms, so 10
    /// confirmations ≈ 27 ms — enough to ride out transient fluctuations.
    private var candidateChord: Chord?
    private var candidateChordCount: Int = 0
    private let chordConfirmationsNeeded = 10

    // MARK: - Tunables

    var amplitudeThreshold: Double = DetectedPitch.defaultAmplitudeThreshold
    var smoothing: Double = 0.6
    var minFrequency: Double = 30
    var maxFrequency: Double = 4000

    // MARK: - Dependencies

    private let detector: any PitchDetector
    private let chordDetector: (any ChordDetector)?

    init(detector: any PitchDetector, chordDetector: (any ChordDetector)? = nil) {
        self.detector = detector
        self.chordDetector = chordDetector
        rebuildScaleMap()
    }

    // MARK: - Lifecycle

    func start() async {
        permission = AudioPermission.current
        if permission == .undetermined {
            permission = await AudioPermission.request()
        }
        guard permission == .granted else { return }

        detector.onPitch = { [weak self] reading in
            Task { @MainActor in
                self?.ingest(reading)
            }
        }

        chordDetector?.onChord = { [weak self] detected in
            Task { @MainActor in
                self?.ingestChord(detected)
            }
        }

        do {
            try detector.start()
            isListening = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isListening = false
        }
    }

    func stop() {
        // Don't call detector.stop() — the detector is shared and stays
        // running across tab switches. Just reset local state.
        isListening = false
        smoothedFrequency = nil
        activePitchClass = nil
        activeNote = nil
        detectedChord = nil
        chordConfidence = 0
        candidateChord = nil
        candidateChordCount = 0
    }

    // MARK: - Queries

    /// Scale degree label for a note at `(string, fret)`, or nil if not in scale.
    func degreeLabel(string: Int, fret: Int) -> String? {
        let pc = fretboard.note(string: string, fret: fret).pitchClass
        return scaleDegreeMap[pc]
    }

    /// Whether the note at `(string, fret)` is the root of the selected scale.
    func isRoot(string: Int, fret: Int) -> Bool {
        fretboard.note(string: string, fret: fret).pitchClass == selectedRoot
    }

    /// Whether the note at `(string, fret)` matches the currently played pitch class.
    func isActive(string: Int, fret: Int) -> Bool {
        guard let active = activePitchClass else { return false }
        return fretboard.note(string: string, fret: fret).pitchClass == active
    }

    /// Whether the note at `(string, fret)` is in the current scale.
    func isInScale(string: Int, fret: Int) -> Bool {
        scalePitchClasses.contains(fretboard.note(string: string, fret: fret).pitchClass)
    }

    /// Display name for the note at `(string, fret)`.
    func noteName(string: Int, fret: Int) -> String {
        fretboard.note(string: string, fret: fret).pitchClass.name(preferring: accidental)
    }

    /// Whether the note at `(string, fret)` is a tone in the currently detected chord.
    func isChordTone(string: Int, fret: Int) -> Bool {
        guard let chord = detectedChord else { return false }
        let pc = fretboard.note(string: string, fret: fret).pitchClass
        return chord.pitchClasses.contains(pc)
    }

    /// Whether the note at `(string, fret)` is the root of the detected chord.
    func isChordRoot(string: Int, fret: Int) -> Bool {
        guard let chord = detectedChord else { return false }
        return fretboard.note(string: string, fret: fret).pitchClass == chord.root
    }

    // MARK: - Chord ingestion

    private func ingestChord(_ detected: DetectedChord?) {
        guard showChordDetection else {
            detectedChord = nil
            chordConfidence = 0
            return
        }

        guard let detected else {
            // No chord detected — decay toward nil. Subtract 2 so the
            // chord clears in roughly half the time it takes to confirm.
            candidateChordCount = max(0, candidateChordCount - 2)
            if candidateChordCount == 0 {
                detectedChord = nil
                chordConfidence = 0
                candidateChord = nil
            }
            return
        }

        // Stability gate: require N consecutive readings of the same chord.
        if detected.chord == candidateChord {
            candidateChordCount += 1
        } else {
            candidateChord = detected.chord
            candidateChordCount = 1
        }

        if candidateChordCount >= chordConfirmationsNeeded {
            detectedChord = detected.chord
            chordConfidence = detected.confidence
        }
    }

    // MARK: - Private

    private func rebuildScaleMap() {
        let pcs = selectedScale.pitchClasses(in: selectedRoot)
        scalePitchClasses = Set(pcs)

        var map: [PitchClass: String] = [:]
        let degreeLabels = scaleDegreeLabels(for: selectedScale)
        for (i, pc) in pcs.enumerated() {
            map[pc] = degreeLabels[i]
        }
        scaleDegreeMap = map
    }

    /// Produces degree labels like "1", "b3", "#4", "b7" based on comparing
    /// the scale intervals against the major scale intervals.
    private func scaleDegreeLabels(for scale: Scale) -> [String] {
        let majorIntervals = Scale.major.intervals  // [0, 2, 4, 5, 7, 9, 11]

        if scale.intervals.count == majorIntervals.count {
            // Heptatonic: index maps 1:1 to degree number, so we can
            // unambiguously distinguish #4 from b5, etc.
            return scale.intervals.enumerated().map { index, semitones in
                let natural = majorIntervals[index]
                if semitones == natural     { return "\(index + 1)" }
                if semitones == natural - 1 { return "b\(index + 1)" }
                if semitones == natural + 1 { return "#\(index + 1)" }
                return "\(index + 1)"
            }
        }

        // Non-heptatonic (pentatonic, blues): match against closest major degree.
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

    private func ingest(_ reading: DetectedPitch) {
        guard reading.amplitude > amplitudeThreshold,
              reading.frequency.isFinite,
              reading.frequency > minFrequency,
              reading.frequency < maxFrequency
        else {
            // Signal dropped below threshold — clear active note after brief hold.
            activePitchClass = nil
            activeNote = nil
            return
        }

        if let current = smoothedFrequency {
            let ratio = reading.frequency / current
            if ratio > 1.04 || ratio < 0.96 {
                smoothedFrequency = reading.frequency
            } else {
                smoothedFrequency = current * smoothing + reading.frequency * (1 - smoothing)
            }
        } else {
            smoothedFrequency = reading.frequency
        }

        if let f = smoothedFrequency, let result = Note.nearest(to: f) {
            activeNote = result.note
            activePitchClass = result.note.pitchClass
        }
    }
}
