import SwiftUI
import Observation

/// Coordinates camera capture, Vision detection, and scene description building.
@Observable
final class CameraViewModel {

    // MARK: - Published State

    var detectedObjects: [DetectedObject] = []
    var currentScene: SceneDescription = SceneDescription(objects: [])
    var isCameraRunning = false
    var cameraPermissionGranted = false
    var errorMessage: String?

    // MARK: - Services

    let cameraService = CameraService()
    private let visionService = VisionDetectionService()

    // MARK: - Setup

    func setup() async {
        let granted = await cameraService.requestPermission()
        cameraPermissionGranted = granted

        guard granted else {
            errorMessage = "Camera access is required to detect obstacles. Please enable it in Settings."
            return
        }

        configureDetectionPipeline()
        cameraService.configure()
        cameraService.start()
        isCameraRunning = true
    }

    func stop() {
        cameraService.stop()
        isCameraRunning = false
    }

    // MARK: - Detection Pipeline

    private func configureDetectionPipeline() {
        cameraService.onFrameCaptured = { [weak self] sampleBuffer in
            self?.visionService.processFrame(sampleBuffer)
        }

        visionService.onObjectsDetected = { [weak self] objects in
            guard let self else { return }
            let scene = SceneDescription(objects: objects)

            DispatchQueue.main.async {
                self.detectedObjects = objects
                self.currentScene = scene

                AccessibilityManager.shared.evaluateHazards(in: scene)
            }
        }
    }
}
