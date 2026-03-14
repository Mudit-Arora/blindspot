import Foundation

struct SceneDescription: Codable, Sendable {
    let objects: [DetectedObject]
    let timestamp: Date

    init(objects: [DetectedObject]) {
        self.objects = objects
        self.timestamp = Date()
    }

    /// Human-readable summary for sending to the AI backend
    var summary: String {
        guard !objects.isEmpty else { return "No objects detected in the scene." }

        return objects.map { obj in
            var desc = "\(obj.label) on the \(obj.position.rawValue)"
            if let dist = obj.estimatedDistance {
                desc += " approximately \(dist) away"
            }
            return desc
        }.joined(separator: ". ") + "."
    }

    /// JSON payload for the backend WebSocket
    func toJSONData() -> Data? {
        let payload: [[String: Any]] = objects.map { obj in
            var dict: [String: Any] = [
                "label": obj.label,
                "position": obj.position.rawValue,
                "confidence": obj.confidence
            ]
            if let dist = obj.estimatedDistance {
                dict["distance"] = dist
            }
            return dict
        }

        let wrapper: [String: Any] = ["objects": payload]
        return try? JSONSerialization.data(withJSONObject: wrapper)
    }
}
