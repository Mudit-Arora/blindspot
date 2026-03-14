import Foundation

/// Communicates with the Python backend via WebSocket for low-latency speech interaction.
final class BackendAPIService: @unchecked Sendable {

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession

    /// Called when response audio data is received from the backend
    var onAudioReceived: ((Data) -> Void)?

    /// Called when the backend sends a transcript (for optional display)
    var onTranscriptReceived: ((String, String) -> Void)?

    /// Called when the full response cycle completes
    var onResponseComplete: (() -> Void)?

    /// Called on any connection error
    var onError: ((Error) -> Void)?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - WebSocket Connection

    func connect() {
        guard let url = URL(string: Configuration.webSocketURL) else { return }
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        startListening()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Send Session Start (scene context)

    func sendSceneContext(_ scene: SceneDescription) async throws {
        guard let sceneData = scene.toJSONData() else {
            throw BackendError.encodingFailed
        }

        let sceneJSON = String(data: sceneData, encoding: .utf8) ?? "{}"
        let message: [String: Any] = [
            "type": "session_start",
            "scene": sceneJSON
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let messageString = String(data: messageData, encoding: .utf8) ?? ""

        try await webSocketTask?.send(.string(messageString))
    }

    // MARK: - Send Audio Data

    func sendAudio(_ wavData: Data) async throws {
        try await webSocketTask?.send(.data(wavData))

        let endMessage = #"{"type": "audio_end"}"#
        try await webSocketTask?.send(.string(endMessage))
    }

    // MARK: - Full Request (scene + audio)

    func sendSpeechRequest(scene: SceneDescription, audio: Data) async throws {
        try await sendSceneContext(scene)
        try await sendAudio(audio)
    }

    // MARK: - REST Fallback

    /// Fallback REST endpoint if WebSocket is unavailable
    func sendSpeechRequestREST(scene: SceneDescription, audio: Data) async throws -> Data {
        guard let url = URL(string: Configuration.restEndpointURL) else {
            throw BackendError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        // Scene JSON part
        if let sceneData = scene.toJSONData() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"scene\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(sceneData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Audio file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BackendError.serverError
        }

        return data
    }

    // MARK: - Listen for Responses

    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startListening()

            case .failure(let error):
                self.onError?(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { return }

            switch type {
            case "transcript":
                let userText = json["user_text"] as? String ?? ""
                let assistantText = json["assistant_text"] as? String ?? ""
                onTranscriptReceived?(userText, assistantText)

            case "response_end":
                onResponseComplete?()

            default:
                break
            }

        case .data(let data):
            onAudioReceived?(data)

        @unknown default:
            break
        }
    }

    // MARK: - Errors

    enum BackendError: LocalizedError {
        case invalidURL
        case encodingFailed
        case serverError

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL."
            case .encodingFailed: return "Failed to encode request data."
            case .serverError: return "Server returned an error."
            }
        }
    }
}
