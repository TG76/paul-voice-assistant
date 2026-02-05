import Foundation
import Speech
import AVFoundation

class LiveTranscriber {
    var onTranscriptionComplete: ((String) -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private let silenceDetector = SilenceDetector()

    private(set) var isRecording = false
    private var currentTranscription = ""
    private var waitForSpeech = false
    private var speechDetected = false

    init() {
        silenceDetector.onSilenceDetected = { [weak self] in
            DispatchQueue.main.async {
                self?.finishTranscription()
            }
        }
    }

    func startTranscribing(waitForSpeech: Bool = false) {
        guard !isRecording else {
            PaulLogger.log("[LiveSTT] Bereits aktiv, überspringe")
            return
        }

        currentTranscription = ""
        self.waitForSpeech = waitForSpeech
        self.speechDetected = false
        PaulLogger.log("[LiveSTT] waitForSpeech=\(waitForSpeech)")

        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        PaulLogger.log("[LiveSTT] Start: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if let recognizer = speechRecognizer, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            PaulLogger.log("[LiveSTT] On-Device-Erkennung aktiv")
        }
        recognitionRequest = request

        // Audio-Format: 16kHz Mono für Speech Recognition
        guard let speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: 16000,
                                                channels: 1,
                                                interleaved: false),
              let converter = AVAudioConverter(from: hardwareFormat, to: speechFormat) else {
            PaulLogger.log("[LiveSTT] Kein Converter, nutze Hardware-Format")
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                if !self.waitForSpeech || self.speechDetected {
                    self.silenceDetector.process(buffer: buffer)
                }
                self.recognitionRequest?.append(buffer)
            }
            startEngineAndRecognition()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            if !self.waitForSpeech || self.speechDetected {
                self.silenceDetector.process(buffer: buffer)
            }

            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / hardwareFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: frameCount) else {
                self.recognitionRequest?.append(buffer)
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                self.recognitionRequest?.append(convertedBuffer)
            } else {
                self.recognitionRequest?.append(buffer)
            }
        }

        startEngineAndRecognition()
    }

    private func startEngineAndRecognition() {
        do {
            try audioEngine.start()
            isRecording = true
            silenceDetector.reset()
            Task { @MainActor in StateManager.shared.isRecording = true }
            PaulLogger.log("[LiveSTT] AudioEngine gestartet")
        } catch {
            PaulLogger.log("[LiveSTT] AudioEngine Fehler: \(error)")
            return
        }

        guard let recognizer = speechRecognizer, let request = recognitionRequest else {
            PaulLogger.log("[LiveSTT] SpeechRecognizer nicht verfügbar")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.currentTranscription = text

                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.speechDetected {
                    self.speechDetected = true
                    self.silenceDetector.reset()
                    PaulLogger.log("[LiveSTT] Sprache erkannt, Stille-Timer startet jetzt")
                }

                PaulLogger.log("[LiveSTT] '\(text)'")

                Task { @MainActor in
                    StateManager.shared.transcribedText = text
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Ignoriere Cancel-Fehler (normales Beenden)
                if nsError.domain == "kLSRErrorDomain" && nsError.code == 301 { return }
                PaulLogger.log("[LiveSTT] Fehler: \(error.localizedDescription)")
            }
        }
    }

    private func finishTranscription() {
        guard isRecording else { return }
        PaulLogger.log("[LiveSTT] Stille erkannt, beende...")

        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        stopTranscribing()

        PaulLogger.log("[LiveSTT] Endergebnis: '\(text)'")
        onTranscriptionComplete?(text)
    }

    func stopTranscribing() {
        guard isRecording else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        Task { @MainActor in StateManager.shared.isRecording = false }
        PaulLogger.log("[LiveSTT] Gestoppt")
    }
}
