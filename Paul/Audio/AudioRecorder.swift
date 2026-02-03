import Foundation
import AVFoundation

class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let silenceDetector = SilenceDetector()
    private var recordingURL: URL?

    @Published var isRecording = false

    var onRecordingComplete: ((URL) -> Void)?

    init() {
        silenceDetector.onSilenceDetected = { [weak self] in
            DispatchQueue.main.async {
                self?.stopRecording()
            }
        }
    }

    func startRecording() {
        guard !isRecording else {
            PaulLogger.log("[AudioRecorder] Bereits aktiv, überspringe")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        PaulLogger.log("[AudioRecorder] Format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paul_recording_\(UUID().uuidString).wav")
        recordingURL = url

        // WAV-Datei in nativem Format erstellen (Float32, gleiche Samplerate/Channels)
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: recordingFormat.settings
            )
        } catch {
            PaulLogger.log("[AudioRecorder] Fehler beim Erstellen der Datei: \(error)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.silenceDetector.process(buffer: buffer)
            try? self.audioFile?.write(from: buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            isRecording = true
            silenceDetector.reset()
            Task { @MainActor in StateManager.shared.isRecording = true }
            PaulLogger.log("[AudioRecorder] Aufnahme gestartet")
        } catch {
            PaulLogger.log("[AudioRecorder] Fehler beim Starten: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false

        Task { @MainActor in StateManager.shared.isRecording = false }
        PaulLogger.log("[AudioRecorder] Aufnahme beendet")

        if let url = recordingURL {
            onRecordingComplete?(url)
        }
    }
}
