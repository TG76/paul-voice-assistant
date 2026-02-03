import Foundation
import AVFoundation

class SilenceDetector {
    private let threshold: Float
    private let duration: TimeInterval
    private var silenceStart: Date?
    var onSilenceDetected: (() -> Void)?

    init(threshold: Float = AppSettings.silenceThreshold,
         duration: TimeInterval = AppSettings.silenceDuration) {
        self.threshold = threshold
        self.duration = duration
    }

    func process(buffer: AVAudioPCMBuffer) {
        let level = calculateRMS(buffer: buffer)

        Task { @MainActor in
            StateManager.shared.audioLevel = level
        }

        if level < threshold {
            if silenceStart == nil {
                silenceStart = Date()
            } else if let start = silenceStart, Date().timeIntervalSince(start) >= duration {
                silenceStart = nil
                onSilenceDetected?()
            }
        } else {
            silenceStart = nil
        }
    }

    func reset() {
        silenceStart = nil
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let data = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            sum += data[i] * data[i]
        }

        return sqrt(sum / Float(frames))
    }
}
