import AVFoundation

/// Thin wrapper around `AVCaptureDevice` audio authorization, surfaced as a small
/// enum so the rest of the app doesn't need to import AVFoundation.
enum AudioPermission {
    enum Status: Sendable {
        case undetermined
        case granted
        case denied
    }

    /// Read the current authorization without prompting.
    static var current: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:               .granted
        case .denied, .restricted:      .denied
        case .notDetermined:            .undetermined
        @unknown default:               .undetermined
        }
    }

    /// Prompt the user if undetermined; returns the resulting status.
    @discardableResult
    static func request() async -> Status {
        if case let now = current, now != .undetermined { return now }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }
}
