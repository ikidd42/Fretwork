import Foundation

/// A user-selectable audio device — used for both inputs and outputs depending
/// on which list it came from.
///
/// `id` is the Core Audio device UID (a stable string like
/// `"AppleHDAEngineInput:1B,0,1,0:0"`). UIDs persist across reboots, unlike
/// numeric `AudioDeviceID`s which are reassigned at runtime.
///
/// `channelCount` is the count for the direction this instance represents:
/// input channels for an input device, output channels for an output device.
struct AudioDevice: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let channelCount: Int

    init(id: String, name: String, channelCount: Int) {
        self.id = id
        self.name = name
        self.channelCount = channelCount
    }
}
