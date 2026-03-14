import SwiftUI
import Observation

/// Manages the voice interaction lifecycle: record → send → receive → play.
@Observable
final class VoiceAssistantViewModel {

    // MARK: - State

    enum AssistantState: Equatable {
        case idle
        case listening
        case processing
        case speaking
        case error(String)
    }

    var state: AssistantState = .idle
    var userTranscript: String = ""
    var assistantTranscript: String = ""
    var micPermissionGranted = false

    // MARK: - Services

    private let audioRecorder = AudioRecordingService()
    private let backendAPI = BackendAPIService()
    private let audioPlayer = AudioPlaybackService()

    // MARK: - Setup

    func setup() async {
        let granted = await audioRecorder.requestPermission()
        micPermissionGranted = granted
    }

    // MARK: - Voice Interaction

    /// Start recording the user's voice
    func startListening() {
        guard state == .idle || state.isError else { return }

        do {
            try audioRecorder.startRecording()
            state = .listening
            userTranscript = ""
            assistantTranscript = ""
            AccessibilityManager.shared.triggerLightFeedback()
        } catch {
            state = .error("Could not start recording: \(error.localizedDescription)")
        }
    }

    /// Stop recording and send to backend
    func stopListeningAndSend(scene: SceneDescription) {
        guard state == .listening else { return }

        let audioData = audioRecorder.stopRecording()
        state = .processing
        AccessibilityManager.shared.triggerLightFeedback()

        Task {
            await sendToBackend(audio: audioData, scene: scene)
        }
    }

    // MARK: - Backend Communication

    private func sendToBackend(audio: Data, scene: SceneDescription) async {
        do {
            let response = try await backendAPI.sendSpeechRequest(scene: scene, audio: audio)

            await MainActor.run {
                userTranscript = response.userText
                assistantTranscript = response.assistantText
                playResponseAudio(response.audioData)
            }
        } catch {
            await MainActor.run {
                state = .error("Failed to communicate with server: \(error.localizedDescription)")
                AccessibilityManager.shared.announce("Error communicating with assistant")
            }
        }
    }

    // MARK: - Audio Playback

    private func playResponseAudio(_ audioData: Data) {
        guard !audioData.isEmpty else {
            state = .error("No audio response received.")
            return
        }

        state = .speaking

        do {
            try audioPlayer.playAudio(data: audioData) { [weak self] in
                DispatchQueue.main.async {
                    self?.state = .idle
                }
            }
        } catch {
            state = .error("Failed to play response: \(error.localizedDescription)")
        }
    }

    /// Cancel any ongoing interaction
    func cancel() {
        if audioRecorder.isRecording {
            _ = audioRecorder.stopRecording()
        }
        audioPlayer.stop()
        state = .idle
    }
}

// MARK: - Helpers

private extension VoiceAssistantViewModel.AssistantState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
