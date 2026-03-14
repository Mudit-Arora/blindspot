import SwiftUI

/// Root view — camera preview background with voice interaction overlay.
struct MainView: View {
    @State private var cameraViewModel = CameraViewModel()
    @State private var voiceViewModel = VoiceAssistantViewModel()
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraView(cameraViewModel: cameraViewModel)

            // Semi-transparent gradient so the UI controls are readable over the camera feed
            LinearGradient(
                colors: [.clear, .black.opacity(0.4), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VoiceInteractionView(
                voiceViewModel: voiceViewModel,
                currentScene: cameraViewModel.currentScene
            )
        }
        .task {
            guard !hasAppeared else { return }
            hasAppeared = true
            await cameraViewModel.setup()
            await voiceViewModel.setup()

            // Welcome announcement after a brief delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            AccessibilityManager.shared.announce(
                "Blindspot is ready. Hold the talk button at the bottom of the screen to ask about your surroundings."
            )
        }
        .onDisappear {
            cameraViewModel.stop()
            voiceViewModel.cancel()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}
