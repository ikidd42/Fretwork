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
///     `nonisolated` + `@unchecked Sendable` — configuration and engine state
///     shared with the scheduling thread is guarded by `lock`. The loop takes
///     a snapshot each iteration and sleeps in short slices so `stop()` can
///     join it promptly. Beat/measure counters are touched only by the
///     scheduling thread (reset before it spawns).
nonisolated
final class AudioMetronome: @unchecked Sendable {

    /// Guards all mutable state shared with the scheduling thread.
    private let lock = NSLock()

    // MARK: - Configuration

    /// Beats per minute. Clamped to [20, 400].
    var bpm: Double {
        get { lock.withLock { _bpm } }
        set { lock.withLock { _bpm = max(20, min(400, newValue)) } }
    }

    /// Beats per measure (top of time signature).
    var beatsPerMeasure: Int {
        get { lock.withLock { _beatsPerMeasure } }
        set { lock.withLock { _beatsPerMeasure = max(1, min(16, newValue)) } }
    }

    /// Volume of click sounds [0, 1].
    var volume: Float {
        get { lock.withLock { _volume } }
        set {
            lock.lock()
            _volume = max(0, min(1, newValue))
            let vol = _volume
            let eng = engine
            lock.unlock()
            eng?.mainMixerNode.outputVolume = vol
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
    /// Set to `nil` to revert to click mode. Takes effect on the next start.
    var drumPattern: DrumPattern? {
        get { lock.withLock { _drumPattern } }
        set {
            lock.withLock { _drumPattern = newValue }
            if newValue != nil { regenerateDrumBuffers() }
        }
    }

    // MARK: - Callbacks

    /// Fires on each beat with (beatNumber: 1-based within measure, isAccent: true for beat 1).
    /// Dispatched to MainActor.
    var onBeat: (@MainActor (Int, Bool) -> Void)? {
        get { lock.withLock { _onBeat } }
        set { lock.withLock { _onBeat = newValue } }
    }

    /// Fires when a measure completes.
    var onMeasure: (@MainActor (Int) -> Void)? {
        get { lock.withLock { _onMeasure } }
        set { lock.withLock { _onMeasure = newValue } }
    }

    // MARK: - State

    var isRunning: Bool { lock.withLock { _isRunning } }

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
    /// Signaled by the scheduling thread when it exits.
    private var threadExited: DispatchSemaphore?

    // MARK: - Private backing

    private var _bpm: Double = 120
    private var _beatsPerMeasure: Int = 4
    private var _volume: Float = 0.7
    private var _isRunning = false
    private var _drumPattern: DrumPattern?
    private var _onBeat: (@MainActor (Int, Bool) -> Void)?
    private var _onMeasure: (@MainActor (Int) -> Void)?

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
        eng.mainMixerNode.outputVolume = lock.withLock { _volume }

        try eng.start()
        player.play()

        self.currentBeat = 0
        self.currentMeasure = 0

        let exited = DispatchSemaphore(value: 0)
        self.threadExited = exited
        lock.withLock {
            self.engine = eng
            self.playerNode = player
            self.shouldStop = false
            self._isRunning = true
        }

        // Start the scheduling thread
        let thread = Thread { [weak self] in
            self?.schedulingLoop()
            exited.signal()
        }
        thread.name = "com.fretwork.metronome"
        thread.qualityOfService = .userInteractive
        self.schedulingThread = thread
        thread.start()
    }

    func stop() {
        lock.lock()
        guard _isRunning else { lock.unlock(); return }
        shouldStop = true
        _isRunning = false
        lock.unlock()

        // Wait for the scheduling thread to actually exit before tearing the
        // engine down, so it can't schedule a buffer on a stopped engine.
        // The loop checks `shouldStop` at least every ~20 ms.
        _ = threadExited?.wait(timeout: .now() + 1)
        threadExited = nil
        schedulingThread = nil

        lock.lock()
        let player = playerNode
        let eng = engine
        playerNode = nil
        engine = nil
        lock.unlock()

        player?.stop()
        eng?.stop()
        if let player, player.engine != nil {
            eng?.detach(player)
        }
    }

    // MARK: - Scheduling loop

    /// Runs on a dedicated thread. Schedules clicks or drum hits ahead of the
    /// current playback position by sleeping between beats/subdivisions.
    private func schedulingLoop() {
        if let pattern = lock.withLock({ _drumPattern }) {
            drumSchedulingLoop(pattern: pattern)
        } else {
            clickSchedulingLoop()
        }
    }

    /// Click mode: one event per beat.
    private func clickSchedulingLoop() {
        var nextBeatTime = CACurrentMediaTime()

        while true {
            // Snapshot shared state once per iteration.
            lock.lock()
            let stopped = shouldStop
            let bpm = _bpm
            let beatsPerMeasure = _beatsPerMeasure
            let player = playerNode
            let accentBuf: AVAudioPCMBuffer? = accentClickBuffer
            let normalBuf: AVAudioPCMBuffer? = normalClickBuffer
            let beatCallback = _onBeat
            let measureCallback = _onMeasure
            lock.unlock()
            if stopped { break }

            let beatInterval = 60.0 / bpm

            // Advance beat counter
            currentBeat += 1
            if currentBeat > beatsPerMeasure {
                currentBeat = 1
                currentMeasure += 1
                let measure = currentMeasure
                Task { @MainActor in
                    measureCallback?(measure)
                }
            }

            let beat = currentBeat
            let isAccent = (beat == 1)

            // Schedule the click buffer
            if let buffer = isAccent ? accentBuf : normalBuf {
                player?.scheduleBuffer(buffer, completionHandler: nil)
            }

            // Fire the UI callback
            Task { @MainActor in
                beatCallback?(beat, isAccent)
            }

            nextBeatTime += beatInterval
            let sleepDuration = nextBeatTime - CACurrentMediaTime()
            if sleepDuration > 0 {
                if !sleepUnlessStopped(sleepDuration) { break }
            } else {
                nextBeatTime = CACurrentMediaTime()
            }
        }
    }

    /// Sleep in short slices, checking `shouldStop` between slices so `stop()`
    /// never has to wait out a full beat. Returns false if stopping.
    private func sleepUnlessStopped(_ duration: TimeInterval) -> Bool {
        var remaining = duration
        while remaining > 0 {
            if lock.withLock({ shouldStop }) { return false }
            let slice = min(0.02, remaining)
            Thread.sleep(forTimeInterval: slice)
            remaining -= slice
        }
        return !lock.withLock({ shouldStop })
    }

    /// Drum mode: iterate subdivisions of the pattern, firing beat callbacks
    /// on the appropriate subdivisions (e.g. every 2nd subdivision for 8th-note patterns in 4/4).
    private func drumSchedulingLoop(pattern: DrumPattern) {
        var nextSubTime = CACurrentMediaTime()
        var subdivIndex = 0

        while true {
            // Snapshot shared state once per iteration.
            lock.lock()
            let stopped = shouldStop
            let bpm = _bpm
            let beatsPerMeasure = _beatsPerMeasure
            let player = playerNode
            let kick = kickBuffer
            let snare = snareBuffer
            let hiHat = hiHatBuffer
            let beatCallback = _onBeat
            let measureCallback = _onMeasure
            lock.unlock()
            if stopped { break }

            // Subdivision interval: each beat has `subsPerBeat` subdivisions
            let subsPerBeat = max(1, pattern.subdivisions / beatsPerMeasure)
            let beatInterval = 60.0 / bpm
            let subInterval = beatInterval / Double(subsPerBeat)

            // Check if this subdivision falls on a beat boundary
            if subdivIndex % subsPerBeat == 0 {
                currentBeat += 1
                if currentBeat > beatsPerMeasure {
                    currentBeat = 1
                    currentMeasure += 1
                    let measure = currentMeasure
                    Task { @MainActor in
                        measureCallback?(measure)
                    }
                }

                let beat = currentBeat
                let isAccent = (beat == 1)
                Task { @MainActor in
                    beatCallback?(beat, isAccent)
                }
            }

            // Schedule drum sounds for this subdivision
            let patIdx = subdivIndex % pattern.subdivisions

            if pattern.kick[patIdx], let buf = kick {
                player?.scheduleBuffer(buf, completionHandler: nil)
            }
            if pattern.snare[patIdx], let buf = snare {
                player?.scheduleBuffer(buf, completionHandler: nil)
            }
            if pattern.hiHat[patIdx], let buf = hiHat {
                player?.scheduleBuffer(buf, completionHandler: nil)
            }

            subdivIndex += 1
            nextSubTime += subInterval
            let sleepDuration = nextSubTime - CACurrentMediaTime()
            if sleepDuration > 0 {
                if !sleepUnlessStopped(sleepDuration) { break }
            } else {
                nextSubTime = CACurrentMediaTime()
            }
        }
    }

    // MARK: - Drum synthesis

    private func regenerateDrumBuffers() {
        let kick = DrumSynthesizer.kick()
        let snare = DrumSynthesizer.snare()
        let hiHat = DrumSynthesizer.hiHat()
        lock.withLock {
            kickBuffer = kick
            snareBuffer = snare
            hiHatBuffer = hiHat
        }
    }

    // MARK: - Click synthesis

    /// Generates click buffers as short synthesized tones.
    private func regenerateClickBuffers() {
        let accent = synthesizeClick(frequency: accentFrequency, duration: clickDuration, amplitude: 0.9)
        let normal = synthesizeClick(frequency: normalFrequency, duration: clickDuration, amplitude: 0.6)
        lock.withLock {
            accentClickBuffer = accent
            normalClickBuffer = normal
        }
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
