import Foundation
import Speech
import AVFoundation

class WakeWordDetector: ObservableObject {
    static let shared = WakeWordDetector()

    @Published var isListening = false
    var onWakeWordDetected: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private let wakeWord = "paul"

    /// Zähler der verhindert, dass alte Error-Retries aktiv werden
    private var generation: Int = 0

    func startListening(force: Bool = false) {
        if isListening && !force {
            PaulLogger.log("[WakeWord] Bereits aktiv, überspringe")
            return
        }
        if isListening {
            stopListening()
        }

        generation += 1
        let myGeneration = generation

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            guard status == .authorized else {
                PaulLogger.log("[WakeWord] Speech-Erkennung nicht autorisiert: \(status.rawValue)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.generation == myGeneration else {
                    PaulLogger.log("[WakeWord] Veralteter Start ignoriert")
                    return
                }
                self.beginRecognition(generation: myGeneration)
            }
        }
    }

    private func beginRecognition(generation gen: Int) {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        audioEngine = AVAudioEngine()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try audioEngine.start()
            isListening = true
            PaulLogger.log("[WakeWord] Lausche auf '\(wakeWord)'...")
        } catch {
            PaulLogger.log("[WakeWord] AudioEngine Fehler: \(error)")
            scheduleRetry(generation: gen)
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                if text.contains(self.wakeWord) {
                    PaulLogger.log("[WakeWord] Erkannt! Text: '\(text)'")
                    self.stopListening()
                    DispatchQueue.main.async {
                        self.onWakeWordDetected?()
                    }
                    return
                }
            }

            if let error = error {
                PaulLogger.log("[WakeWord] Erkennungsfehler: \(error.localizedDescription)")
                self.stopListening()
                self.scheduleRetry(generation: gen)
            }
        }
    }

    private func scheduleRetry(generation gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            guard self.generation == gen else {
                PaulLogger.log("[WakeWord] Veralteter Retry ignoriert (gen \(gen) != \(self.generation))")
                return
            }
            self.startListening()
        }
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        PaulLogger.log("[WakeWord] Gestoppt")
    }

    func triggerWakeWord() {
        onWakeWordDetected?()
    }
}
