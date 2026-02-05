import Foundation
import AVFoundation

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    @Published var isPlaying = false
    var onPlaybackComplete: (() -> Void)?

    // Streaming mit AVAudioEngine
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var mixerNode: AVAudioMixerNode?
    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    private var streamingLevel: Float = -160
    private var scheduledBuffers = 0
    private var completedBuffers = 0
    private var streamFinished = false

    // MARK: - Legacy Playback (MP3)

    func play(data: Data) {
        do {
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.play()
            isPlaying = true
            PaulLogger.log("[AudioPlayer] Playback gestartet (\(data.count) bytes)")
        } catch {
            PaulLogger.log("[AudioPlayer] Fehler: \(error)")
            onPlaybackComplete?()
        }
    }

    func play(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            PaulLogger.log("[AudioPlayer] Fehler: \(error)")
            onPlaybackComplete?()
        }
    }

    // MARK: - Streaming Playback (PCM)

    func startStreaming() {
        stopStreaming()

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        mixerNode = AVAudioMixerNode()

        guard let engine = audioEngine, let player = playerNode, let mixer = mixerNode else { return }

        engine.attach(player)
        engine.attach(mixer)

        // Player -> Mixer -> Output
        engine.connect(player, to: mixer, format: pcmFormat)
        engine.connect(mixer, to: engine.mainMixerNode, format: pcmFormat)

        // Metering via Mixer Tap
        mixer.installTap(onBus: 0, bufferSize: 1024, format: pcmFormat) { [weak self] buffer, _ in
            self?.updateStreamingLevel(buffer: buffer)
        }

        do {
            try engine.start()
            player.play()
            isPlaying = true
            scheduledBuffers = 0
            completedBuffers = 0
            streamFinished = false
            PaulLogger.log("[AudioPlayer] Streaming Engine gestartet")
        } catch {
            PaulLogger.log("[AudioPlayer] Engine Start Fehler: \(error)")
        }
    }

    func scheduleBuffer(pcmData: Data) {
        guard let player = playerNode,
              let buffer = pcmBufferFromData(pcmData) else { return }

        scheduledBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.bufferCompleted()
            }
        }
    }

    func finishStreaming() {
        streamFinished = true
        checkPlaybackComplete()
    }

    func stopStreaming() {
        playerNode?.stop()
        mixerNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        mixerNode = nil
        isPlaying = false
        streamingLevel = -160
    }

    private func bufferCompleted() {
        completedBuffers += 1
        checkPlaybackComplete()
    }

    private func checkPlaybackComplete() {
        if streamFinished && completedBuffers >= scheduledBuffers {
            PaulLogger.log("[AudioPlayer] Streaming Playback fertig (\(completedBuffers) buffers)")
            stopStreaming()
            onPlaybackComplete?()
        }
    }

    private func pcmBufferFromData(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count / 2)  // 16-bit = 2 bytes per sample
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawPtr in
            if let src = rawPtr.baseAddress?.assumingMemoryBound(to: Int16.self),
               let dst = buffer.int16ChannelData?[0] {
                dst.update(from: src, count: Int(frameCount))
            }
        }

        return buffer
    }

    private func updateStreamingLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }
        let frames = Int(buffer.frameLength)
        let data = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            let sample = Float(data[i]) / 32768.0
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 0.0001))
        streamingLevel = db
    }

    // MARK: - Common

    func stop() {
        player?.stop()
        stopStreaming()
        isPlaying = false
    }

    var currentLevel: Float {
        if audioEngine != nil {
            return streamingLevel
        }
        player?.updateMeters()
        return player?.averagePower(forChannel: 0) ?? -160
    }

    func enableMetering() {
        player?.isMeteringEnabled = true
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        PaulLogger.log("[AudioPlayer] Playback fertig (success: \(flag))")
        isPlaying = false
        onPlaybackComplete?()
    }
}
