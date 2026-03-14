import UIKit
import AVFoundation

/// Manages VoiceOver announcements and haptic feedback for accessibility.
final class AccessibilityManager: @unchecked Sendable {

    static let shared = AccessibilityManager()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let warningGenerator = UINotificationFeedbackGenerator()
    private let synthesizer = AVSpeechSynthesizer()
    private var lastWarningTime: Date = .distantPast
    private let warningCooldown: TimeInterval = 3.0

    private init() {
        impactGenerator.prepare()
        warningGenerator.prepare()
    }

    // MARK: - VoiceOver Announcements

    /// Post a VoiceOver announcement for screen reader users
    func announce(_ message: String, priority: UIAccessibility.Priority = .high) {
        UIAccessibility.post(
            notification: .announcement,
            argument: NSAttributedString(
                string: message,
                attributes: [.accessibilitySpeechQueueAnnouncement: priority == .high]
            )
        )
    }

    // MARK: - Spoken Alerts (non-VoiceOver, for all users)

    /// Speak a warning using AVSpeechSynthesizer — works even without VoiceOver enabled
    func speakWarning(_ message: String) {
        guard Date().timeIntervalSince(lastWarningTime) >= warningCooldown else { return }
        lastWarningTime = Date()

        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.2
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    // MARK: - Haptic Feedback

    func triggerProximityWarning() {
        warningGenerator.notificationOccurred(.warning)
    }

    func triggerDangerAlert() {
        // Triple-pulse pattern for danger
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            generator.impactOccurred()
        }
    }

    func triggerLightFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Proximity Check

    /// Evaluate detected objects and trigger warnings for close hazards
    func evaluateHazards(in scene: SceneDescription) {
        let hazardLabels: Set<String> = [
            "pothole", "construction", "construction cone",
            "stairs", "stairway", "vehicle", "car", "truck",
            "bicycle", "motorcycle"
        ]

        for object in scene.objects {
            let area = object.boundingBox.width * object.boundingBox.height
            let isClose = area >= Configuration.proximityWarningAreaThreshold

            if isClose {
                if hazardLabels.contains(object.label.lowercased()) {
                    triggerDangerAlert()
                    speakWarning("Warning: \(object.label) detected nearby, \(object.position.rawValue) side.")
                    return
                } else if object.label == "person" {
                    triggerProximityWarning()
                }
            }
        }
    }
}

extension UIAccessibility {
    enum Priority {
        case high, low
    }
}
