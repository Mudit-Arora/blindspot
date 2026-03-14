import Vision
import CoreImage
import CoreMedia
import UIKit

/// Runs Apple Vision requests on camera frames to detect objects and classify scenes.
final class VisionDetectionService: @unchecked Sendable {

    private let detectionQueue = DispatchQueue(label: "com.blindspot.vision.detection")
    private var lastDetectionTime: Date = .distantPast
    private var isProcessing = false

    /// Called on detectionQueue with fresh detection results
    var onObjectsDetected: (([DetectedObject]) -> Void)?

    // MARK: - Process Frame

    /// Throttled detection — skips frames if called faster than Configuration.detectionInterval
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= Configuration.detectionInterval,
              !isProcessing
        else { return }

        lastDetectionTime = now
        isProcessing = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }

        detectionQueue.async { [weak self] in
            self?.runDetection(on: pixelBuffer)
        }
    }

    // MARK: - Vision Requests

    private func runDetection(on pixelBuffer: CVPixelBuffer) {
        var detectedObjects: [DetectedObject] = []
        let group = DispatchGroup()

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        // 1. Detect people
        group.enter()
        let humanRequest = VNDetectHumanRectanglesRequest { [weak self] request, error in
            defer { group.leave() }
            guard let self, error == nil,
                  let results = request.results as? [VNHumanObservation]
            else { return }

            let people = results
                .filter { $0.confidence >= Configuration.minimumDetectionConfidence }
                .map { observation in
                    DetectedObject(
                        label: "person",
                        confidence: observation.confidence,
                        boundingBox: observation.boundingBox,
                        estimatedDistance: DetectedObject.estimateDistance(from: observation.boundingBox)
                    )
                }
            detectedObjects.append(contentsOf: people)
        }

        // 2. Detect animals (bikes, dogs etc. that could be in path)
        group.enter()
        let animalRequest = VNRecognizeAnimalsRequest { [weak self] request, error in
            defer { group.leave() }
            guard let self, error == nil,
                  let results = request.results as? [VNRecognizedObjectObservation]
            else { return }

            let animals = results
                .filter { $0.confidence >= Configuration.minimumDetectionConfidence }
                .compactMap { observation -> DetectedObject? in
                    guard let label = observation.labels.first?.identifier else { return nil }
                    return DetectedObject(
                        label: label,
                        confidence: observation.confidence,
                        boundingBox: observation.boundingBox,
                        estimatedDistance: DetectedObject.estimateDistance(from: observation.boundingBox)
                    )
                }
            detectedObjects.append(contentsOf: animals)
        }

        // 3. General image classification for scene context
        group.enter()
        let classifyRequest = VNClassifyImageRequest { request, error in
            defer { group.leave() }
            guard error == nil,
                  let results = request.results as? [VNClassificationObservation]
            else { return }

            // Take top classifications relevant to navigation hazards
            let hazardKeywords: Set<String> = [
                "car", "truck", "bus", "bicycle", "motorcycle",
                "stairs", "stairway", "construction",
                "traffic_light", "stop_sign", "fire_hydrant",
                "bench", "chair", "pole"
            ]

            let relevant = results
                .filter { $0.confidence >= 0.3 }
                .prefix(10)
                .filter { classification in
                    hazardKeywords.contains(where: {
                        classification.identifier.lowercased().contains($0)
                    })
                }
                .map { classification in
                    DetectedObject(
                        label: classification.identifier.replacingOccurrences(of: "_", with: " "),
                        confidence: classification.confidence,
                        boundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                        estimatedDistance: nil
                    )
                }
            detectedObjects.append(contentsOf: relevant)
        }

        do {
            try requestHandler.perform([humanRequest, animalRequest, classifyRequest])
        } catch {
            print("[VisionDetection] Error: \(error.localizedDescription)")
        }

        group.wait()
        isProcessing = false
        onObjectsDetected?(detectedObjects)
    }
}
