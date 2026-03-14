import Foundation

struct SpeechAgentResponse {
    let userText: String
    let assistantText: String
    let audioData: Data
}

/// Communicates with the Python backend via REST POST for speech interaction.
final class BackendAPIService: @unchecked Sendable {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func sendSpeechRequest(scene: SceneDescription, audio: Data) async throws -> SpeechAgentResponse {
        guard let url = URL(string: Configuration.restEndpointURL) else {
            throw BackendError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        if let sceneData = scene.toJSONData() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"scene\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(sceneData)
            body.append("\r\n".data(using: .utf8)!)
        }

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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendError.decodingFailed
        }

        let userText = json["user_text"] as? String ?? ""
        let assistantText = json["assistant_text"] as? String ?? ""
        let audioBase64 = json["audio_base64"] as? String ?? ""

        guard let audioData = Data(base64Encoded: audioBase64), !audioData.isEmpty else {
            throw BackendError.decodingFailed
        }

        return SpeechAgentResponse(
            userText: userText,
            assistantText: assistantText,
            audioData: audioData
        )
    }

    // MARK: - Errors

    enum BackendError: LocalizedError {
        case invalidURL
        case encodingFailed
        case serverError
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL."
            case .encodingFailed: return "Failed to encode request data."
            case .serverError: return "Server returned an error."
            case .decodingFailed: return "Failed to decode server response."
            }
        }
    }
}
