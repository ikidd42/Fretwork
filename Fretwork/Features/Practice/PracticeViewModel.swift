import Foundation
import Observation

/// Drives the Practice tab: metronome with scale and chord progression modes.
///
/// Pattern matches `FretboardViewModel`: `@MainActor @Observable`, init takes
/// `(detector:chordDetector:)`, `start() async` + `stop()`.
@MainActor
@Observable
final class PracticeViewModel {

    // MARK: - Practice mode

    enum PracticeMode: String, CaseIterable, Sendable {
        case freeMetronome
        case scalePractice
        case chordProgression

        var title: String {
            switch self {
            case .freeMetronome:    "Free Metronome"
            case .scalePractice:    "Scale Practice"
            case .chordProgression: "Chord Progression"
            }
        }

        var symbolName: String {
            switch self {
            case .freeMetronome:    "metronome"
            case .scalePractice:    "music.note.list"
            case .chordProgression: "pianokeys"
            }
        }
    }

    // MARK: - Playback state

    enum PlayState: Sendable {
        case stopped
        case countingIn    // preparation bar
        case playing
    }

    // MARK: - Published state

    var mode: PracticeMode = .freeMetronome

    // Metronome
    var bpm: Double = 100 {
        didSet { metronome.bpm = bpm }
    }
    var beatsPerMeasure: Int = 4 {
        didSet { metronome.beatsPerMeasure = beatsPerMeasure }
    }
    var clickSound: AudioMetronome.ClickSound = .woodblock {
        didSet { metronome.clickSound = clickSound }
    }
    var metronomeVolume: Float = 0.7 {
        didSet { metronome.volume = metronomeVolume }
    }

    /// When true, uses a drum pattern instead of click sounds.
    var useDrumTrack: Bool = false {
        didSet {
            metronome.drumPattern = useDrumTrack ? selectedDrumPattern : nil
        }
    }
    var selectedDrumPattern: DrumPattern = .basic4_4 {
        didSet {
            if useDrumTrack { metronome.drumPattern = selectedDrumPattern }
        }
    }

    /// Current beat within the measure (1-based), for the visual indicator.
    private(set) var currentBeat: Int = 0
    /// Whether this beat is accented (beat 1).
    private(set) var isAccentBeat: Bool = false
    /// Total measures elapsed.
    private(set) var currentMeasure: Int = 0

    private(set) var playState: PlayState = .stopped
    /// Count-in beats remaining (counts down from beatsPerMeasure).
    private(set) var countInBeatsRemaining: Int = 0

    // MARK: - Key / scale / progression selection

    var selectedRoot: PitchClass = .c
    var selectedScale: Scale = .major
    var selectedProgression: ChordProgression = .oneForFiveOne

    // MARK: - Scale practice state

    /// The note the player should be playing right now (for scale mode).
    private(set) var targetNote: Note?
    /// Index into the scale sequence.
    private(set) var scaleNoteIndex: Int = 0
    /// The full ascending-descending scale sequence for one octave.
    private(set) var scaleSequence: [Note] = []
    /// Whether the player hit the right note on this beat.
    private(set) var lastNoteCorrect: Bool?

    // MARK: - Chord progression state

    /// The chord the player should be playing right now.
    private(set) var targetChord: Chord?
    /// The next chord coming up.
    private(set) var nextChord: Chord?
    /// Index into the resolved chord list.
    private(set) var chordIndex: Int = 0
    /// Beat countdown within the current chord.
    private(set) var beatsOnCurrentChord: Int = 0
    /// Resolved chords for the current key/progression.
    private(set) var resolvedChords: [Chord] = []
    /// Whether the player is playing the correct chord.
    private(set) var lastChordCorrect: Bool?

    // MARK: - Speed trainer

    /// When enabled, BPM increases after successful loops.
    var speedTrainerEnabled: Bool = false
    /// BPM increase per successful loop.
    var bpmIncrement: Double = 5
    /// Maximum BPM the speed trainer will reach.
    var maxBpm: Double = 200
    /// How many successful loops in a row.
    private(set) var successfulLoops: Int = 0

    // MARK: - Loop

    /// Whether to loop the progression / scale continuously.
    var loopEnabled: Bool = true

    // MARK: - Live detection

    private(set) var activePitchClass: PitchClass?
    private(set) var detectedChord: Chord?

    private var smoothedFrequency: Double?
    var amplitudeThreshold: Double = 0.05
    var smoothing: Double = 0.6

    // MARK: - Scoring

    private(set) var totalBeats: Int = 0
    private(set) var correctBeats: Int = 0
    var accuracy: Double {
        totalBeats > 0 ? Double(correctBeats) / Double(totalBeats) : 0
    }

    // MARK: - Audio permission

    private(set) var permission: AudioPermission.Status = .undetermined
    private(set) var isListening: Bool = false
    private(set) var lastError: String?

    // MARK: - Dependencies

    private let detector: any PitchDetector
    private let chordDetector: (any ChordDetector)?
    private let metronome = AudioMetronome()

    init(detector: any PitchDetector, chordDetector: (any ChordDetector)? = nil) {
        self.detector = detector
        self.chordDetector = chordDetector
        metronome.bpm = bpm
        metronome.beatsPerMeasure = beatsPerMeasure
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
                self?.ingestPitch(reading)
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
        stopMetronome()
        isListening = false
        smoothedFrequency = nil
        activePitchClass = nil
        detectedChord = nil
    }

    // MARK: - Metronome control

    func startMetronome() {
        guard playState == .stopped else { return }

        // Reset scoring
        totalBeats = 0
        correctBeats = 0
        successfulLoops = 0
        lastNoteCorrect = nil
        lastChordCorrect = nil

        // Prepare mode-specific state
        switch mode {
        case .scalePractice:
            buildScaleSequence()
            scaleNoteIndex = 0
            targetNote = scaleSequence.first
        case .chordProgression:
            resolvedChords = selectedProgression.chords(in: selectedRoot)
            chordIndex = 0
            beatsOnCurrentChord = 0
            targetChord = resolvedChords.first
            nextChord = resolvedChords.count > 1 ? resolvedChords[1] : resolvedChords.first
        case .freeMetronome:
            break
        }

        // Wire metronome callbacks
        metronome.onBeat = { [weak self] beat, isAccent in
            self?.handleBeat(beat, isAccent: isAccent)
        }
        metronome.onMeasure = { [weak self] measure in
            self?.currentMeasure = measure
        }

        // Start with count-in
        countInBeatsRemaining = beatsPerMeasure
        playState = .countingIn

        do {
            try metronome.start()
        } catch {
            lastError = "Metronome failed to start: \(error.localizedDescription)"
            playState = .stopped
        }
    }

    func stopMetronome() {
        metronome.stop()
        playState = .stopped
        currentBeat = 0
        currentMeasure = 0
        countInBeatsRemaining = 0
        targetNote = nil
        targetChord = nil
        nextChord = nil
    }

    func toggleMetronome() {
        if playState != .stopped {
            stopMetronome()
        } else {
            startMetronome()
        }
    }

    // MARK: - Beat handling

    private func handleBeat(_ beat: Int, isAccent: Bool) {
        currentBeat = beat
        isAccentBeat = isAccent

        // Count-in phase
        if playState == .countingIn {
            countInBeatsRemaining -= 1
            if countInBeatsRemaining <= 0 {
                playState = .playing
                currentMeasure = 0
            }
            return
        }

        guard playState == .playing else { return }

        switch mode {
        case .freeMetronome:
            break

        case .scalePractice:
            evaluateScaleBeat()
            advanceScaleNote()

        case .chordProgression:
            evaluateChordBeat()
            advanceChordBeat()
        }
    }

    // MARK: - Scale practice

    private func buildScaleSequence() {
        // Ascending then descending, one octave from the root.
        // Start at a comfortable guitar position: root at octave 3.
        let rootNote = Note(pitchClass: selectedRoot, octave: 3)
        let ascending = selectedScale.notes(rootedAt: rootNote)
        let topNote = rootNote.transposed(by: .perfectOctave)
        // Up through every degree, the octave at the top, then back down
        // mirroring every degree (the octave itself is not repeated).
        scaleSequence = ascending + [topNote] + ascending.reversed()
    }

    private func evaluateScaleBeat() {
        guard let target = targetNote else { return }
        totalBeats += 1

        if let active = activePitchClass, active == target.pitchClass {
            correctBeats += 1
            lastNoteCorrect = true
        } else {
            lastNoteCorrect = false
        }
    }

    private func advanceScaleNote() {
        scaleNoteIndex += 1
        if scaleNoteIndex >= scaleSequence.count {
            // Completed one loop
            if loopEnabled {
                handleLoopComplete()
                scaleNoteIndex = 0
            } else {
                stopMetronome()
                return
            }
        }
        targetNote = scaleSequence[scaleNoteIndex]
    }

    // MARK: - Chord progression practice

    private func evaluateChordBeat() {
        guard let target = targetChord else { return }
        totalBeats += 1

        if let detected = detectedChord, detected == target {
            correctBeats += 1
            lastChordCorrect = true
        } else {
            lastChordCorrect = false
        }
    }

    private func advanceChordBeat() {
        beatsOnCurrentChord += 1
        let beatsNeeded = selectedProgression.beatsPerChord

        if beatsOnCurrentChord >= beatsNeeded {
            // Move to next chord
            beatsOnCurrentChord = 0
            chordIndex += 1

            if chordIndex >= resolvedChords.count {
                // Completed one loop
                if loopEnabled {
                    handleLoopComplete()
                    chordIndex = 0
                } else {
                    stopMetronome()
                    return
                }
            }

            targetChord = resolvedChords[chordIndex]
            let nextIdx = (chordIndex + 1) % resolvedChords.count
            nextChord = resolvedChords[nextIdx]
        }
    }

    // MARK: - Speed trainer

    private func handleLoopComplete() {
        // Check if this loop was "successful" (>= 80% accuracy in this loop)
        let loopAccuracy = accuracy
        if loopAccuracy >= 0.8 {
            successfulLoops += 1
            if speedTrainerEnabled && bpm < maxBpm {
                bpm = min(maxBpm, bpm + bpmIncrement)
                metronome.bpm = bpm
            }
        } else {
            successfulLoops = 0
        }

        // Reset scoring for the new loop
        totalBeats = 0
        correctBeats = 0
    }

    // MARK: - Pitch ingestion

    private func ingestPitch(_ reading: DetectedPitch) {
        guard reading.amplitude > amplitudeThreshold,
              reading.frequency.isFinite,
              reading.frequency > 30,
              reading.frequency < 4000
        else {
            activePitchClass = nil
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
            activePitchClass = result.note.pitchClass
        }
    }

    // MARK: - Chord ingestion

    private func ingestChord(_ detected: DetectedChord?) {
        detectedChord = detected?.chord
    }
}
