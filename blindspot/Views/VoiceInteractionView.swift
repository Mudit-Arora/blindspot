import SwiftUI

/// The voice interaction panel with talk button and status display.
struct VoiceInteractionView: View {
    let voiceViewModel: VoiceAssistantViewModel
    let currentScene: SceneDescription

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            statusBar

            sceneInfoBar

            talkButton
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 8) {
            if !voiceViewModel.userTranscript.isEmpty {
                TranscriptBubble(text: voiceViewModel.userTranscript, isUser: true)
            }

            if !voiceViewModel.assistantTranscript.isEmpty {
                TranscriptBubble(text: voiceViewModel.assistantTranscript, isUser: false)
            }

            Text(statusText)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .accessibilityLabel(statusAccessibilityLabel)
        }
    }

    // MARK: - Scene Info

    private var sceneInfoBar: some View {
        Group {
            if !currentScene.objects.isEmpty {
                Text("\(currentScene.objects.count) object\(currentScene.objects.count == 1 ? "" : "s") detected")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    .accessibilityLabel("\(currentScene.objects.count) objects detected around you. \(currentScene.summary)")
            }
        }
    }

    // MARK: - Talk Button (Tap Toggle: tap to start recording, tap again to stop and send)

    private var talkButton: some View {
        Button(action: handleTalkButtonTap) {
            ZStack {
                Circle()
                    .fill(talkButtonColor)
                    .frame(width: 120, height: 120)
                    .shadow(color: talkButtonColor.opacity(0.5), radius: voiceViewModel.state == .listening ? 20 : 10)
                    .scaleEffect(voiceViewModel.state == .listening ? 1.1 : 1.0)

                VStack(spacing: 4) {
                    Image(systemName: talkButtonIcon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(talkButtonLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .accessibilityLabel(talkButtonAccessibilityLabel)
        .accessibilityHint(talkButtonAccessibilityHint)
        .disabled(voiceViewModel.state == .processing || voiceViewModel.state == .speaking)
        .animation(.easeInOut(duration: 0.3), value: voiceViewModel.state)
    }

    // MARK: - Computed Properties

    private var statusText: String {
        switch voiceViewModel.state {
        case .idle: return "Tap to Talk"
        case .listening: return "Listening... Tap to Send"
        case .processing: return "Thinking..."
        case .speaking: return "Speaking..."
        case .error(let msg): return msg
        }
    }

    private var statusAccessibilityLabel: String {
        switch voiceViewModel.state {
        case .idle: return "Assistant is ready. Tap the talk button to ask a question."
        case .listening: return "Listening to your question. Tap the button again to send."
        case .processing: return "Processing your question. Please wait."
        case .speaking: return "Assistant is responding."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var talkButtonColor: Color {
        switch voiceViewModel.state {
        case .idle: return .blue
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .green
        case .error: return .gray
        }
    }

    private var talkButtonIcon: String {
        switch voiceViewModel.state {
        case .idle: return "mic.fill"
        case .listening: return "stop.circle.fill"
        case .processing: return "brain"
        case .speaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var talkButtonLabel: String {
        switch voiceViewModel.state {
        case .idle: return "TALK"
        case .listening: return "SEND"
        case .processing: return "WAIT"
        case .speaking: return "PLAYING"
        case .error: return "RETRY"
        }
    }

    private var talkButtonAccessibilityLabel: String {
        switch voiceViewModel.state {
        case .idle: return "Talk to assistant"
        case .listening: return "Send your question"
        case .processing: return "Processing"
        case .speaking: return "Assistant is speaking"
        case .error: return "Try again"
        }
    }

    private var talkButtonAccessibilityHint: String {
        switch voiceViewModel.state {
        case .idle: return "Double tap to start recording your question."
        case .listening: return "Double tap to send your question to the assistant."
        case .processing: return "Please wait while the assistant processes your question."
        case .speaking: return "The assistant is speaking the response."
        case .error: return "Double tap to reset and try again."
        }
    }

    // MARK: - Actions

    private func handleTalkButtonTap() {
        switch voiceViewModel.state {
        case .idle:
            voiceViewModel.startListening()
        case .listening:
            voiceViewModel.stopListeningAndSend(scene: currentScene)
        case .error:
            voiceViewModel.cancel()
        default:
            break
        }
    }
}

// MARK: - Transcript Bubble

private struct TranscriptBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer() }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isUser ? Color.blue.opacity(0.7) : Color.green.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer() }
        }
        .accessibilityLabel("\(isUser ? "You said" : "Assistant said"): \(text)")
    }
}
