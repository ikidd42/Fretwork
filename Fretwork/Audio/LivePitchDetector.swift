import Foundation
import QuartzCore
import AudioKit
import os
import AVFoundation
import CoreAudio

/// Real-time pitch detection plus input monitoring.
///
/// Uses a **Core Audio HAL IOProc** for input instead of `installTap`.
/// `AVAudioEngine.installTap` batches USB audio into ~4800-frame bursts
/// (100 ms), adding unavoidable latency. The HAL IOProc fires at the
/// actual hardware IO rate (e.g. every 128 frames ≈ 2.7 ms at 48 kHz),
/// matching what GarageBand does internally.
///
///     [HAL IOProc on input device]
///       fires every HW-buffer frames
///         │
///         ├─→ PitchAnalyzer → onPitch
///         └─→ scheduleBuffer on playerNode
///
///     [playback engine — system default output]
///       playerNode → mainMixer(vol = monitorGain) → outputNode → device
///
/// `nonisolated` because the IOProc fires on the device's IO thread.
///
/// Thread safety: shared mutable state is guarded by `lock`. The IOProc takes
/// a brief snapshot under the lock at the top of each callback; control-plane
/// methods (main thread) mutate under the same lock. The lock is never held
/// across blocking Core Audio calls (`AudioDeviceStop`, engine start/stop).
nonisolated
final class LivePitchDetector: PitchDetector, ChordDetector, AudioDeviceController, @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.fretwork.app", category: "audio")

    /// Guards all mutable state shared with the IO thread.
    private let lock = NSLock()

    // MARK: - HAL IOProc (input)

    private var inputDeviceID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var captureFormat: AVAudioFormat?

    /// Max frames we'll accept per IOProc callback. Larger deliveries
    /// (startup bursts) are dropped to avoid latency buildup.
    private let maxFramesPerCallback = 1024

    private let pitchAnalyzer = PitchAnalyzer()
    private let chordAnalyzer = ChordAnalyzer()

    // MARK: - Playback engine (output)

    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // MARK: - Configuration

    private var preferredInputDeviceID: String?
    private var preferredOutputDeviceID: String?
    private var _isMonitoringEnabled: Bool = false
    private var _monitorGain: Double = 1.0

    // MARK: - PitchDetector & ChordDetector

    private var _isRunning: Bool = false
    private var _onPitch: (@Sendable (DetectedPitch) -> Void)?
    private var _onChord: (@Sendable (DetectedChord?) -> Void)?

    var isRunning: Bool { lock.withLock { _isRunning } }

    var onPitch: (@Sendable (DetectedPitch) -> Void)? {
        get { lock.withLock { _onPitch } }
        set { lock.withLock { _onPitch = newValue } }
    }

    var onChord: (@Sendable (DetectedChord?) -> Void)? {
        get { lock.withLock { _onChord } }
        set { lock.withLock { _onChord = newValue } }
    }

    func start() throws {
        guard !isRunning else { return }

        // ── 1. Resolve input device ─────────────────────────────────────
        let inputUID = preferredInputDeviceID ?? CoreAudioBridge.systemDefaultInputUID
        guard let inUID = inputUID,
              let devID = CoreAudioBridge.audioDeviceID(forUID: inUID) else {
            throw PitchDetectorError.noAudioInput
        }
        self.inputDeviceID = devID

        // ── 2. Set hardware buffer size ─────────────────────────────────
        try? CoreAudioBridge.setBufferFrameSize(128, on: devID)
        let hwBuf = CoreAudioBridge.getBufferFrameSize(for: devID) ?? 128
        Self.logger.debug("Input HW buffer: \(hwBuf) frames")

        // Also set output device buffer.
        let outputUID = preferredOutputDeviceID ?? CoreAudioBridge.systemDefaultOutputUID
        if let outUID = outputUID, let outDevID = CoreAudioBridge.audioDeviceID(forUID: outUID) {
            try? CoreAudioBridge.setBufferFrameSize(128, on: outDevID)
        }

        // ── 3. Query input format ───────────────────────────────────────
        //   Build an AVAudioFormat from the device's stream description.
        let format = try Self.inputFormat(for: devID)
        lock.withLock { self.captureFormat = format }
        Self.logger.debug("Capture format: \(format.channelCount)ch, \(format.sampleRate)Hz")

        // ── 4. Build playback engine ────────────────────────────────────
        let pbEng = AVAudioEngine()
        let player = AVAudioPlayerNode()
        pbEng.attach(player)
        pbEng.connect(player, to: pbEng.mainMixerNode, format: format)
        pbEng.mainMixerNode.outputVolume = Float(lock.withLock { _isMonitoringEnabled ? _monitorGain : 0 })

        // Route playback to the user's chosen output device. Without this the
        // engine silently stays on the system default output.
        if let outUID = outputUID, let outDevID = CoreAudioBridge.audioDeviceID(forUID: outUID) {
            do {
                try CoreAudioBridge.setOutputDevice(outDevID, on: pbEng)
            } catch {
                Self.logger.warning("Could not route playback to selected output: \(error.localizedDescription)")
            }
        }

        do {
            try pbEng.start()
            player.play()
        } catch {
            throw PitchDetectorError.engineFailed(underlying: error)
        }
        lock.withLock {
            self.playbackEngine = pbEng
            self.playerNode = player
        }

        // Pre-fill the player queue with a few silence buffers to cushion
        // against clock drift between the input and output devices.
        // 3 buffers × 128 frames ≈ 8 ms — small enough to keep latency
        // low, large enough to absorb the periodic drift underrun.
        for _ in 0..<3 {
            if let silence = AVAudioPCMBuffer(pcmFormat: format,
                                              frameCapacity: AVAudioFrameCount(hwBuf)) {
                silence.frameLength = AVAudioFrameCount(hwBuf)
                player.scheduleBuffer(silence, completionHandler: nil)
            }
        }

        // ── 5. Register HAL IOProc on input device ──────────────────────
        pitchAnalyzer.reset()
        chordAnalyzer.reset()
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        var procID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcID(devID, Self.halIOProc, clientData, &procID)
        guard status == noErr, let procID else {
            player.stop()
            pbEng.stop()
            throw PitchDetectorError.engineFailed(underlying: NSError(
                domain: NSOSStatusErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "AudioDeviceCreateIOProcID failed (\(status))."]
            ))
        }
        self.ioProcID = procID

        // ── 7. Start the IOProc ─────────────────────────────────────────
        status = AudioDeviceStart(devID, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(devID, procID)
            self.ioProcID = nil
            player.stop()
            pbEng.stop()
            throw PitchDetectorError.engineFailed(underlying: NSError(
                domain: NSOSStatusErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "AudioDeviceStart failed (\(status))."]
            ))
        }

        lock.withLock { _isRunning = true }
        Self.logger.info("IOProc started on device \(devID), HW buffer \(hwBuf) frames")
    }

    func stop() {
        lock.lock()
        guard _isRunning else { lock.unlock(); return }
        _isRunning = false
        let procID = ioProcID
        let devID = inputDeviceID
        let player = playerNode
        let engine = playbackEngine
        ioProcID = nil
        playerNode = nil
        playbackEngine = nil
        captureFormat = nil
        lock.unlock()

        // Blocking Core Audio calls happen outside the lock. Destroying the
        // IOProc synchronizes with in-flight callbacks; any callback that
        // already snapshotted state holds its own references safely.
        if let procID {
            AudioDeviceStop(devID, procID)
            AudioDeviceDestroyIOProcID(devID, procID)
        }

        player?.stop()
        engine?.stop()
        if let player, player.engine != nil {
            engine?.detach(player)
        }

        pitchAnalyzer.reset()
        chordAnalyzer.reset()
    }

    deinit {
        if isRunning { stop() }
    }

    // MARK: - HAL IOProc callback

    /// C-compatible IOProc. Fires on the device's IO thread at the hardware
    /// buffer rate. Wraps input data into a pre-allocated AVAudioPCMBuffer,
    /// runs pitch analysis, and forwards to the playback engine.
    private static let halIOProc: AudioDeviceIOProc = {
        inDevice, inNow, inInputData, inInputTime,
        outOutputData, outOutputTime, inClientData -> OSStatus in

        guard let clientData = inClientData else { return noErr }
        let detector = Unmanaged<LivePitchDetector>.fromOpaque(clientData).takeUnretainedValue()
        detector.handleHALInput(inInputData)
        return noErr
    }

    private func handleHALInput(_ inputData: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard !abl.isEmpty, let firstBuf = abl.first,
              firstBuf.mDataByteSize > 0 else { return }

        // Reject oversized deliveries (startup bursts) to avoid latency.
        let chCount = max(Int(firstBuf.mNumberChannels), 1)
        let rawFrames = Int(firstBuf.mDataByteSize) / (chCount * MemoryLayout<Float>.stride)
        guard rawFrames <= maxFramesPerCallback else { return }

        // Snapshot shared state once, briefly, under the lock. Everything
        // below uses these locals so the control plane can mutate freely.
        lock.lock()
        let format = captureFormat
        let player = playerNode
        let monitoring = _isMonitoringEnabled
        let pitchCallback = _onPitch
        let chordCallback = _onChord
        lock.unlock()

        // Allocate a fresh buffer for each callback. ARC releases it after
        // the playerNode finishes playback — no risk of overwriting a buffer
        // that's still being played. ~1 KB per allocation at 128 frames.
        guard let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(rawFrames)),
              let dstChannels = buffer.floatChannelData else { return }
        let dstChCount = Int(format.channelCount)

        if abl.count == 1 && firstBuf.mNumberChannels >= 2 {
            // ── Interleaved: single buffer with channels woven LRLRLR…
            // frameCount = bytes / (channels × sizeof(Float))
            let chCount = Int(firstBuf.mNumberChannels)
            let frameCount = Int(firstBuf.mDataByteSize) / (chCount * MemoryLayout<Float>.stride)
            guard frameCount <= buffer.frameCapacity else { return }
            buffer.frameLength = AVAudioFrameCount(frameCount)

            guard let src = firstBuf.mData?.assumingMemoryBound(to: Float.self) else { return }
            for ch in 0..<min(chCount, dstChCount) {
                let dst = dstChannels[ch]
                for f in 0..<frameCount {
                    dst[f] = src[f * chCount + ch]
                }
            }
        } else {
            // ── Non-interleaved: one buffer per channel.
            let frameCount = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.stride
            guard frameCount <= buffer.frameCapacity else { return }
            buffer.frameLength = AVAudioFrameCount(frameCount)

            for (i, audioBuf) in abl.enumerated() {
                guard let src = audioBuf.mData,
                      i < dstChCount else { continue }
                memcpy(dstChannels[i], src, Int(audioBuf.mDataByteSize))
            }
        }

        // Pitch analysis — always runs.
        if let result = pitchAnalyzer.analyze(buffer) {
            let reading = DetectedPitch(
                frequency: result.frequency,
                amplitude: result.amplitude,
                timestamp: CACurrentMediaTime()
            )
            pitchCallback?(reading)
        }

        // Chord analysis — runs on the same buffer.
        if let chordCallback {
            let sr = format.sampleRate
            if let result = chordAnalyzer.analyze(buffer, sampleRate: sr) {
                let detected = DetectedChord(
                    chord: result.chord,
                    confidence: result.confidence,
                    timestamp: CACurrentMediaTime()
                )
                chordCallback(detected)
            } else {
                chordCallback(nil)
            }
        }

        // Forward to playback for monitoring.
        guard monitoring, let player else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Input format query

    /// Build an `AVAudioFormat` from the input device's current stream format.
    private static func inputFormat(for deviceID: AudioDeviceID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Channel count from stream configuration.
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            throw PitchDetectorError.noAudioInput
        }
        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            throw PitchDetectorError.noAudioInput
        }
        let abl = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        let channels = UnsafeMutableAudioBufferListPointer(abl)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channels > 0 else { throw PitchDetectorError.noAudioInput }

        // Sample rate from nominal sample rate property.
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 48000
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &sampleRate)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            throw PitchDetectorError.noAudioInput
        }
        return format
    }

    // MARK: - AudioDeviceController

    var availableInputDevices: [AudioDevice] {
        let devices = AudioKit.AudioEngine.inputDevices ?? []
        return devices.compactMap { device -> AudioDevice? in
            guard let uid = CoreAudioBridge.deviceUID(for: device.deviceID) else { return nil }
            let channels = CoreAudioBridge.inputChannelCount(for: device.deviceID)
            guard channels > 0 else { return nil }
            return AudioDevice(id: uid, name: device.name, channelCount: channels)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var availableOutputDevices: [AudioDevice] {
        let devices = AudioKit.AudioEngine.outputDevices ?? []
        return devices.compactMap { device -> AudioDevice? in
            guard let uid = CoreAudioBridge.deviceUID(for: device.deviceID) else { return nil }
            let channels = CoreAudioBridge.outputChannelCount(for: device.deviceID)
            guard channels > 0 else { return nil }
            return AudioDevice(id: uid, name: device.name, channelCount: channels)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var currentInputDeviceID: String? {
        preferredInputDeviceID ?? CoreAudioBridge.systemDefaultInputUID
    }

    var currentOutputDeviceID: String? {
        preferredOutputDeviceID ?? CoreAudioBridge.systemDefaultOutputUID
    }

    func setInputDevice(id: String) throws {
        preferredInputDeviceID = id
        let wasRunning = isRunning
        if wasRunning { stop() }
        if wasRunning { try start() }
    }

    func setOutputDevice(id: String) throws {
        preferredOutputDeviceID = id
        let wasRunning = isRunning
        if wasRunning { stop() }
        if wasRunning { try start() }
    }

    var isMonitoringEnabled: Bool { lock.withLock { _isMonitoringEnabled } }
    var monitorGain: Double { lock.withLock { _monitorGain } }

    func setMonitoring(enabled: Bool, gain: Double) {
        lock.lock()
        _isMonitoringEnabled = enabled
        _monitorGain = max(0, min(2.0, gain))
        let volume = Float(_isMonitoringEnabled ? _monitorGain : 0)
        let engine = _isRunning ? playbackEngine : nil
        lock.unlock()
        engine?.mainMixerNode.outputVolume = volume
    }
}
