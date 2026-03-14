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

    private var responseAudioBuffer = Data()

    // MARK: - Setup

    func setup() async {
        let granted = await audioRecorder.requestPermission()
        micPermissionGranted = granted

        configureBackendCallbacks()
    }

    private func configureBackendCallbacks() {
        backendAPI.onAudioReceived = { [weak self] data in
            guard let self else { return }
            self.responseAudioBuffer.append(data)
        }

        backendAPI.onTranscriptReceived = { [weak self] userText, assistantText in
            DispatchQueue.main.async {
                self?.userTranscript = userText
                self?.assistantTranscript = assistantText
            }
        }

        backendAPI.onResponseComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.playResponseAudio()
            }
        }

        backendAPI.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.state = .error(error.localizedDescription)
            }
        }
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
            responseAudioBuffer = Data()
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
            // Try WebSocket first
            backendAPI.connect()

            // Small delay to let WebSocket connect
            try await Task.sleep(nanoseconds: 300_000_000)

            try await backendAPI.sendSpeechRequest(scene: scene, audio: audio)
        } catch {
            // Fallback to REST
            do {
                let responseData = try await backendAPI.sendSpeechRequestREST(scene: scene, audio: audio)
                responseAudioBuffer = responseData
                await MainActor.run {
                    playResponseAudio()
                }
            } catch {
                await MainActor.run {
                    state = .error("Failed to communicate with server: \(error.localizedDescription)")
                    AccessibilityManager.shared.announce("Error communicating with assistant")
                }
            }
        }
    }

    // MARK: - Audio Playback

    private func playResponseAudio() {
        guard !responseAudioBuffer.isEmpty else {
            state = .error("No audio response received.")
            return
        }

        state = .speaking

        do {
            try audioPlayer.playAudio(data: responseAudioBuffer) { [weak self] in
                DispatchQueue.main.async {
                    self?.state = .idle
                    self?.backendAPI.disconnect()
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
        backendAPI.disconnect()
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
