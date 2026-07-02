import XCTest
@testable import Fretwork

final class FretworkTests: XCTestCase {
    func testTargetBuilds() {
        XCTAssertTrue(true)
    }

    /// The HAL-based device enumeration (which replaced AudioKit's) must see
    /// the machine's built-in devices. Every real Mac has at least one output;
    /// headless CI VMs may have none, so the non-empty assertion is local-only.
    func testHALDeviceEnumerationFindsRealDevices() throws {
        let detector = LivePitchDetector()
        let outputs = detector.availableOutputDevices
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        try XCTSkipIf(isCI && outputs.isEmpty, "CI VM exposes no audio devices")
        XCTAssertFalse(outputs.isEmpty, "no output devices found via HAL enumeration")
        for device in outputs {
            XCTAssertFalse(device.id.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertGreaterThan(device.channelCount, 0)
        }
        // Inputs may legitimately be absent (no mic); just require no crash.
        _ = detector.availableInputDevices
    }
}
