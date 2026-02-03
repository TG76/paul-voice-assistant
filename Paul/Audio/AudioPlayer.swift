import Foundation
import AVFoundation

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    @Published var isPlaying = false
    var onPlaybackComplete: (() -> Void)?

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

    func stop() {
        player?.stop()
        isPlaying = false
    }

    var currentLevel: Float {
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
