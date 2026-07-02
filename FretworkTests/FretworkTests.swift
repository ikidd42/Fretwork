import XCTest
@testable import Fretwork

final class FretworkTests: XCTestCase {
    func testTargetBuilds() {
        XCTAssertTrue(true)
    }

    /// The HAL-based device enumeration (which replaced AudioKit's) must see
    /// the machine's built-in devices. Every Mac has at least one output.
    func testHALDeviceEnumerationFindsRealDevices() {
        let detector = LivePitchDetector()
        let outputs = detector.availableOutputDevices
        XCTAssertFalse(outputs.isEmpty, "no output devices found via HAL enumeration")
        for device in outputs {
            XCTAssertFalse(device.id.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertGreaterThan(device.channelCount, 0)
        }
        // CI runners may lack inputs; just require the call not to crash.
        _ = detector.availableInputDevices
    }
}
