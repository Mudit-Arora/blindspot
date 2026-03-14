import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapper for the live camera preview layer.
struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer = cameraService.previewLayer
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.updateLayout()
    }
}

final class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let previewLayer {
                previewLayer.frame = bounds
                layer.insertSublayer(previewLayer, at: 0)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func updateLayout() {
        previewLayer?.frame = bounds
    }
}

// MARK: - Detection Overlay

/// Draws bounding boxes and labels over detected objects on the camera feed.
struct DetectionOverlayView: View {
    let objects: [DetectedObject]

    var body: some View {
        GeometryReader { geometry in
            ForEach(objects) { object in
                let rect = convertBoundingBox(object.boundingBox, in: geometry.size)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(colorForObject(object), lineWidth: 3)
                        .frame(width: rect.width, height: rect.height)

                    Text(labelText(for: object))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(colorForObject(object).opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .offset(y: -22)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Convert Vision normalized coordinates (bottom-left origin) to SwiftUI (top-left origin)
    private func convertBoundingBox(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.origin.x * size.width,
            y: (1 - box.origin.y - box.height) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }

    private func colorForObject(_ object: DetectedObject) -> Color {
        let area = object.boundingBox.width * object.boundingBox.height
        if area >= Configuration.proximityWarningAreaThreshold {
            return .red
        } else if area >= Configuration.proximityWarningAreaThreshold * 0.5 {
            return .orange
        }
        return .green
    }

    private func labelText(for object: DetectedObject) -> String {
        var text = object.label.capitalized
        if let dist = object.estimatedDistance {
            text += " · \(dist)"
        }
        return text
    }
}

// MARK: - Combined Camera View

struct CameraView: View {
    let cameraViewModel: CameraViewModel

    var body: some View {
        ZStack {
            CameraPreviewView(cameraService: cameraViewModel.cameraService)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            DetectionOverlayView(objects: cameraViewModel.detectedObjects)
                .ignoresSafeArea()

            if !cameraViewModel.cameraPermissionGranted {
                cameraPermissionDeniedView
            }
        }
    }

    private var cameraPermissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.title2.weight(.semibold))

            Text("Blindspot needs camera access to detect obstacles and help you navigate safely.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera access required. Blindspot needs your camera to detect obstacles.")
        .accessibilityHint("Double tap to open settings and grant camera permission.")
    }
}
