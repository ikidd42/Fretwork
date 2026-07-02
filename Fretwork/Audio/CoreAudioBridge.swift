import Foundation
import CoreAudio
import AVFoundation

/// Direct Core Audio HAL helpers: device enumeration and names, device UIDs
/// (stable across reboots, unlike numeric `AudioDeviceID`s), channel counts,
/// setting the input/output device on an `AVAudioEngine`, buffer sizes, and
/// reading the system default devices. Everything the app needs from the
/// HAL — no audio framework dependencies.
///
/// All functions are pure — no shared state. `nonisolated` because they're
/// callable from anywhere.
nonisolated
enum CoreAudioBridge {

    // MARK: - UID translation

    /// The persistent string identifier for a Core Audio device
    /// (e.g. `"AppleHDAEngineInput:1B,0,1,0:0"`).
    static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let unwrapped = uid else { return nil }
        return unwrapped.takeRetainedValue() as String
    }

    /// Resolve a stored UID back to a runtime `AudioDeviceID`.
    static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var cfUID = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // The AudioValueTranslation must point at variables that stay alive for
        // the duration of the AudioObjectGetPropertyData call, so we keep all
        // pointer use inside nested withUnsafeMutablePointer closures.
        let status: OSStatus = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            withUnsafeMutablePointer(to: &deviceID) { idPtr in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(uidPtr),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(idPtr),
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    0, nil,
                    &size,
                    &translation
                )
            }
        }

        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    // MARK: - Channel count

    /// Number of input channels on a device. `0` if the device has no inputs
    /// or the query fails.
    static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }

        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }

        let abl = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: - Device enumeration

    /// Every audio device the HAL currently knows about (inputs, outputs,
    /// and aggregates). Filter by channel count for direction.
    static var allDeviceIDs: [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs
        ) == noErr else { return [] }
        return deviceIDs
    }

    /// Human-readable device name (e.g. `"MacBook Pro Microphone"`).
    static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let unwrapped = name else { return nil }
        return unwrapped.takeRetainedValue() as String
    }

    // MARK: - System defaults

    /// UID of the system's current default input device.
    static var systemDefaultInputUID: String? {
        systemDefaultDeviceUID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    /// UID of the system's current default output device.
    static var systemDefaultOutputUID: String? {
        systemDefaultDeviceUID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private static func systemDefaultDeviceUID(selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else { return nil }
        return deviceUID(for: deviceID)
    }

    // MARK: - Setting the input/output device on an engine

    /// Point an `AVAudioEngine`'s input node at a specific Core Audio device.
    static func setInputDevice(_ deviceID: AudioDeviceID, on avEngine: AVAudioEngine) throws {
        try setDevice(deviceID, on: avEngine.inputNode.audioUnit, label: "input")
    }

    /// Point an `AVAudioEngine`'s output node at a specific Core Audio device.
    static func setOutputDevice(_ deviceID: AudioDeviceID, on avEngine: AVAudioEngine) throws {
        try setDevice(deviceID, on: avEngine.outputNode.audioUnit, label: "output")
    }

    /// On macOS the AVAudioEngine I/O nodes are AUHAL audio units. To reroute
    /// them, set the `kAudioOutputUnitProperty_CurrentDevice` property while
    /// the engine is stopped — the engine handles Initialize/Uninitialize
    /// around its own start/stop cycle.
    ///
    /// Calling `AudioUnitInitialize` directly is deliberately avoided here:
    /// the engine owns these units' lifecycle, and double-initializing leaves
    /// them in a state where `engine.start()` fails with mDeviceID = 0 and
    /// a flood of `kAudioUnitErr_InvalidParameter`.
    private static func setDevice(_ deviceID: AudioDeviceID, on unit: AudioUnit?, label: String) throws {
        guard let unit else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine \(label) node has no audio unit."]
            )
        }

        var deviceID = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Setting \(label) device failed (\(status))."]
            )
        }
    }

    // MARK: - Hardware IO buffer size

    /// Set the hardware IO buffer frame size on a Core Audio device.
    ///
    /// Smaller values reduce round-trip latency at the cost of higher CPU.
    /// 256 frames at 48 kHz ≈ 5.3 ms per buffer; 128 frames ≈ 2.7 ms.
    /// Most modern Macs handle 256 comfortably. The device may clamp the
    /// value to its supported range silently.
    static func setBufferFrameSize(_ frames: UInt32, on deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = frames
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &size
        )
        if status != noErr {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Setting buffer frame size to \(frames) failed (\(status))."]
            )
        }
    }

    /// Read the current hardware IO buffer frame size for a device.
    /// Use after `setBufferFrameSize` to find out what the device actually
    /// accepted (it may clamp to its supported range).
    static func getBufferFrameSize(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &frames)
        return status == noErr ? frames : nil
    }

    /// Whether a device exposes any output channels. Used to decide whether to
    /// also route output through it when the user picks it as input.
    static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }

        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }

        let abl = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
