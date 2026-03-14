import AVFoundation

/// Plays audio response data received from the backend.
final class AudioPlaybackService: @unchecked Sendable {

    private var audioPlayer: AVAudioPlayer?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var completionHandler: (() -> Void)?

    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    // MARK: - Play Complete Audio (WAV data)

    func playAudio(data: Data, completion: (() -> Void)? = nil) throws {
        try configurePlaybackSession()
        self.completionHandler = completion

        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        player.play()
        self.audioPlayer = player
    }

    // MARK: - Streaming Playback via AVAudioEngine

    /// Start the audio engine for streaming playback
    func startStreamingPlayback(format: AVAudioFormat) throws {
        try configurePlaybackSession()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        node.play()

        self.audioEngine = engine
        self.playerNode = node
    }

    /// Enqueue a chunk of audio for streaming playback
    func enqueueAudioChunk(_ data: Data, format: AVAudioFormat) {
        guard let playerNode else { return }

        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.audioBufferList.pointee.mBuffers.mData,
                       baseAddress,
                       data.count)
            }
        }

        playerNode.scheduleBuffer(buffer)
    }

    /// Stop streaming playback
    func stopStreamingPlayback() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
    }

    // MARK: - Stop

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopStreamingPlayback()
    }

    // MARK: - Audio Session

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completionHandler?()
    }
}
