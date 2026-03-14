import AVFoundation

/// Records audio from the microphone as PCM 16-bit 16kHz mono data.
final class AudioRecordingService: @unchecked Sendable {

    private var audioEngine: AVAudioEngine?
    private var audioData = Data()
    private(set) var isRecording = false

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }

    // MARK: - Recording

    func startRecording() throws {
        guard !isRecording else { return }

        try configureAudioSession()

        audioData = Data()
        let engine = AVAudioEngine()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Configuration.recordingSampleRate,
            channels: AVAudioChannelCount(Configuration.recordingChannels),
            interleaved: true
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndAppend(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        isRecording = true
    }

    func stopRecording() -> Data {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        return buildWAVData(from: audioData)
    }

    // MARK: - Audio Conversion

    private func convertAndAppend(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        var inputConsumed = false

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, convertedBuffer.frameLength > 0 else { return }

        let byteCount = Int(convertedBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        if let channelData = convertedBuffer.int16ChannelData {
            let data = Data(bytes: channelData[0], count: byteCount)
            audioData.append(data)
        }
    }

    // MARK: - WAV Builder

    /// Wraps raw PCM data in a standard WAV header so the backend can decode it easily
    private func buildWAVData(from pcmData: Data) -> Data {
        let sampleRate = UInt32(Configuration.recordingSampleRate)
        let channels = UInt16(Configuration.recordingChannels)
        let bitsPerSample = UInt16(Configuration.recordingBitsPerSample)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })       // PCM
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)

        return header
    }

    // MARK: - Errors

    enum AudioError: LocalizedError {
        case converterCreationFailed
        case microphonePermissionDenied

        var errorDescription: String? {
            switch self {
            case .converterCreationFailed: return "Failed to create audio format converter."
            case .microphonePermissionDenied: return "Microphone access is required."
            }
        }
    }
}
