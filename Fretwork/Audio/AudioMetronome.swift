import Foundation
import AVFoundation
import Accelerate

/// A precise, low-latency metronome that schedules click sounds ahead of time
/// on an `AVAudioEngine` timeline.
///
/// Architecture:
///     AudioMetronome owns its own AVAudioEngine for playback so it doesn't
///     compete with the LivePitchDetector's monitoring engine. Clicks are
///     synthesized in-memory as short sine-wave pips (no bundled audio files).
///
///     A background scheduling thread fills the player queue ~200 ms ahead,
///     while `onBeat` callbacks fire on `MainActor` for UI synchronization.
///
/// Thread safety:
///     `nonisolated` + `@unchecked Sendable` — internal state is only mutated
///     on the scheduling thread or while the engine is stopped.
nonisolated
final class AudioMetronome: @unchecked Sendable {

    // MARK: - Configuration

    /// Beats per minute. Clamped to [20, 400].
    var bpm: Double {
        get { _bpm }
        set { _bpm = max(20, min(400, newValue)) }
    }

    /// Beats per measure (top of time signature).
    var beatsPerMeasure: Int {
        get { _beatsPerMeasure }
        set { _beatsPerMeasure = max(1, min(16, newValue)) }
    }

    /// Volume of click sounds [0, 1].
    var volume: Float {
        get { _volume }
        set {
            _volume = max(0, min(1, newValue))
            engine?.mainMixerNode.outputVolume = _volume
        }
    }

    /// Which sound to use for the click.
    enum ClickSound: String, CaseIterable, Sendable {
        case woodblock
        case hiHat
        case rimshot
        case beep
    }
    var clickSound: ClickSound = .woodblock {
        didSet { regenerateClickBuffers() }
    }

    /// When set, the metronome plays a drum pattern instead of clicks.
    /// Set to `nil` to revert to click mode.
    var drumPattern: DrumPattern? {
        didSet {
            if drumPattern != nil { regenerateDrumBuffers() }
        }
    }

    // MARK: - Callbacks

    /// Fires on each beat with (beatNumber: 1-based within measure, isAccent: true for beat 1).
    /// Dispatched to MainActor.
    var onBeat: (@MainActor (Int, Bool) -> Void)?

    /// Fires when a measure completes.
    var onMeasure: (@MainActor (Int) -> Void)?

    // MARK: - State

    private(set) var isRunning = false

    /// Current beat within the measure (1-based). Updated on the scheduling thread.
    private var currentBeat: Int = 0
    /// Total measures elapsed since start.
    private var currentMeasure: Int = 0

    // MARK: - Audio engine

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private let sampleRate: Double = 44100
    private lazy var playbackFormat: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }()

    // MARK: - Click buffers (precomputed)

    private var accentClickBuffer: AVAudioPCMBuffer!
    private var normalClickBuffer: AVAudioPCMBuffer!

    // MARK: - Drum buffers (precomputed)

    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var hiHatBuffer: AVAudioPCMBuffer?

    // MARK: - Scheduling

    private var schedulingThread: Thread?
    private var shouldStop = false

    // MARK: - Private backing

    private var _bpm: Double = 120
    private var _beatsPerMeasure: Int = 4
    private var _volume: Float = 0.7

    // MARK: - Init

    init(bpm: Double = 120, beatsPerMeasure: Int = 4) {
        self._bpm = max(20, min(400, bpm))
        self._beatsPerMeasure = max(1, min(16, beatsPerMeasure))
        regenerateClickBuffers()
    }

    deinit {
        if isRunning { stop() }
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }

        let eng = AVAudioEngine()
        let player = AVAudioPlayerNode()
        eng.attach(player)
        eng.connect(player, to: eng.mainMixerNode, format: playbackFormat)
        eng.mainMixerNode.outputVolume = _volume

        try eng.start()
        player.play()

        self.engine = eng
        self.playerNode = player
        self.currentBeat = 0
        self.currentMeasure = 0
        self.shouldStop = false
        self.isRunning = true

        // Start the scheduling thread
        let thread = Thread { [weak self] in
            self?.schedulingLoop()
        }
        thread.name = "com.fretwork.metronome"
        thread.qualityOfService = .userInteractive
        self.schedulingThread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        shouldStop = true
        isRunning = false

        // Wait briefly for thread to exit
        Thread.sleep(forTimeInterval: 0.05)

        playerNode?.stop()
        engine?.stop()
        if let player = playerNode, player.engine != nil {
            engine?.detach(player)
        }
        engine = nil
        playerNode = nil
        schedulingThread = nil
    }

    // MARK: - Scheduling loop

    /// Runs on a dedicated thread. Schedules clicks or drum hits ahead of the
    /// current playback position by sleeping between beats/subdivisions.
    private func schedulingLoop() {
        if let pattern = drumPattern {
            drumSchedulingLoop(pattern: pattern)
        } else {
            clickSchedulingLoop()
        }
    }

    /// Click mode: one event per beat.
    private func clickSchedulingLoop() {
        var nextBeatTime = CACurrentMediaTime()

        while !shouldStop {
            let beatInterval = 60.0 / _bpm

            // Advance beat counter
            currentBeat += 1
            if currentBeat > _beatsPerMeasure {
                currentBeat = 1
                currentMeasure += 1
                let measure = currentMeasure
                Task { @MainActor [onMeasure] in
                    onMeasure?(measure)
                }
            }

            let beat = currentBeat
            let isAccent = (beat == 1)

            // Schedule the click buffer
            let buffer = isAccent ? accentClickBuffer! : normalClickBuffer!
            playerNode?.scheduleBuffer(buffer, completionHandler: nil)

            // Fire the UI callback
            Task { @MainActor [onBeat] in
                onBeat?(beat, isAccent)
            }

            nextBeatTime += beatInterval
            let sleepDuration = nextBeatTime - CACurrentMediaTime()
            if sleepDuration > 0 {
                Thread.sleep(forTimeInterval: sleepDuration)
            } else {
                nextBeatTime = CACurrentMediaTime()
            }
        }
    }

    /// Drum mode: iterate subdivisions of the pattern, firing beat callbacks
    /// on the appropriate subdivisions (e.g. every 2nd subdivision for 8th-note patterns in 4/4).
    private func drumSchedulingLoop(pattern: DrumPattern) {
        var nextSubTime = CACurrentMediaTime()
        var subdivIndex = 0

        // How many subdivisions per beat
        let subsPerBeat = pattern.subdivisions / _beatsPerMeasure

        while !shouldStop {
            // Subdivision interval: each beat has `subsPerBeat` subdivisions
            let beatInterval = 60.0 / _bpm
            let subInterval = beatInterval / Double(subsPerBeat)

            // Check if this subdivision falls on a beat boundary
            if subdivIndex % subsPerBeat == 0 {
                currentBeat += 1
                if currentBeat > _beatsPerMeasure {
                    currentBeat = 1
                    currentMeasure += 1
                    let measure = currentMeasure
                    Task { @MainActor [onMeasure] in
                        onMeasure?(measure)
                    }
                }

                let beat = currentBeat
                let isAccent = (beat == 1)
                Task { @MainActor [onBeat] in
                    onBeat?(beat, isAccent)
                }
            }

            // Schedule drum sounds for this subdivision
            let patIdx = subdivIndex % pattern.subdivisions

            if pattern.kick[patIdx], let buf = kickBuffer {
                playerNode?.scheduleBuffer(buf, completionHandler: nil)
            }
            if pattern.snare[patIdx], let buf = snareBuffer {
                playerNode?.scheduleBuffer(buf, completionHandler: nil)
            }
            if pattern.hiHat[patIdx], let buf = hiHatBuffer {
                playerNode?.scheduleBuffer(buf, completionHandler: nil)
            }

            subdivIndex += 1
            nextSubTime += subInterval
            let sleepDuration = nextSubTime - CACurrentMediaTime()
            if sleepDuration > 0 {
                Thread.sleep(forTimeInterval: sleepDuration)
            } else {
                nextSubTime = CACurrentMediaTime()
            }
        }
    }

    // MARK: - Drum synthesis

    private func regenerateDrumBuffers() {
        kickBuffer = DrumSynthesizer.kick()
        snareBuffer = DrumSynthesizer.snare()
        hiHatBuffer = DrumSynthesizer.hiHat()
    }

    // MARK: - Click synthesis

    /// Generates click buffers as short synthesized tones.
    private func regenerateClickBuffers() {
        accentClickBuffer = synthesizeClick(frequency: accentFrequency, duration: clickDuration, amplitude: 0.9)
        normalClickBuffer = synthesizeClick(frequency: normalFrequency, duration: clickDuration, amplitude: 0.6)
    }

    private var accentFrequency: Double {
        switch clickSound {
        case .woodblock: return 1200
        case .hiHat:     return 8000
        case .rimshot:   return 2500
        case .beep:      return 880
        }
    }

    private var normalFrequency: Double {
        switch clickSound {
        case .woodblock: return 800
        case .hiHat:     return 6000
        case .rimshot:   return 1800
        case .beep:      return 660
        }
    }

    private var clickDuration: Double {
        switch clickSound {
        case .woodblock: return 0.025
        case .hiHat:     return 0.040
        case .rimshot:   return 0.030
        case .beep:      return 0.060
        }
    }

    /// Synthesize a short percussive click: a sine wave with a fast exponential
    /// decay envelope. This sounds surprisingly close to a real metronome click.
    private func synthesizeClick(frequency: Double, duration: Double, amplitude: Float) -> AVAudioPCMBuffer {
        let frameCount = Int(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat,
                                       frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let data = buffer.floatChannelData?[0] else { return buffer }

        let twoPiF = 2.0 * Double.pi * frequency
        // Exponential decay: amplitude drops to ~5% over the duration.
        let decayRate = -3.0 / duration

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let envelope = Float(exp(decayRate * t))
            let sine = Float(sin(twoPiF * t))
            data[i] = amplitude * envelope * sine
        }

        return buffer
    }
}
