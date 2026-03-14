import Foundation
import CoreGraphics

struct DetectedObject: Identifiable, Codable, Sendable {
    let id: UUID
    let label: String
    let confidence: Float
    /// Normalized bounding box in Vision coordinates (origin bottom-left, 0-1 range)
    let boundingBox: CGRect
    let position: Position
    let estimatedDistance: String?

    enum Position: String, Codable, Sendable {
        case left
        case center
        case right
    }

    init(
        label: String,
        confidence: Float,
        boundingBox: CGRect,
        estimatedDistance: String? = nil
    ) {
        self.id = UUID()
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.estimatedDistance = estimatedDistance

        let centerX = boundingBox.midX
        if centerX < 0.33 {
            self.position = .left
        } else if centerX > 0.66 {
            self.position = .right
        } else {
            self.position = .center
        }
    }

    /// Heuristic distance from bounding box size — larger boxes are closer
    static func estimateDistance(from boundingBox: CGRect) -> String {
        let area = boundingBox.width * boundingBox.height
        switch area {
        case 0.25...:    return "2 feet"
        case 0.15..<0.25: return "4 feet"
        case 0.08..<0.15: return "6 feet"
        case 0.03..<0.08: return "10 feet"
        default:          return "far away"
        }
    }
}
