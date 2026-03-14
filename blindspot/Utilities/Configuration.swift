import Foundation

enum Configuration {
    /// Backend server base URL — change to your deployed server in production
    static let backendHost = "localhost"
    static let backendPort = 8000

    static var backendBaseURL: String {
        "http://\(backendHost):\(backendPort)"
    }

    static var webSocketURL: String {
        "ws://\(backendHost):\(backendPort)/ws/speech-agent"
    }

    static var restEndpointURL: String {
        "\(backendBaseURL)/api/speech-agent"
    }

    // MARK: - Audio Format

    /// Recording sample rate — 16kHz is standard for speech recognition
    static let recordingSampleRate: Double = 16000
    static let recordingChannels: UInt32 = 1
    static let recordingBitsPerSample: UInt32 = 16

    // MARK: - Detection Thresholds

    /// Minimum confidence to report a detected object
    static let minimumDetectionConfidence: Float = 0.4

    /// Distance threshold (in normalized bbox area) that triggers a proximity warning
    static let proximityWarningAreaThreshold: CGFloat = 0.15

    /// How often (seconds) to run Vision detection on camera frames
    static let detectionInterval: TimeInterval = 0.5
}
