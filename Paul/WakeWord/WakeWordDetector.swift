import Foundation
import Speech
import AVFoundation
import AppKit

class WakeWordDetector: ObservableObject {
    static let shared = WakeWordDetector()

    @Published var isListening = false
    var onWakeWordDetected: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private let wakeWord = "hey paul"

    /// Zähler der verhindert, dass alte Error-Retries aktiv werden
    private var generation: Int = 0

    // Debug: Audio-Buffer-Zähler
    private var bufferCount: Int = 0
    private var lastBufferLogTime: Date = Date()
    private var lastPartialResult: String = ""
    private var statusCheckTimer: Timer?

    /// Ob wir aktiv lauschen sollten (für Auto-Restart nach Display-Wake)
    private var shouldBeListening: Bool = false

    private init() {
        setupDisplayWakeNotification()
    }

    /// Lauscht auf Display-Wake um die Erkennung neu zu starten
    private func setupDisplayWakeNotification() {
        // Wenn Display aufwacht, Erkennung neu starten
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            PaulLogger.log("[WakeWord] Display aufgewacht, prüfe Status...")
            if self.shouldBeListening && !self.audioEngine.isRunning {
                PaulLogger.log("[WakeWord] AudioEngine war gestoppt, starte neu...")
                self.startListening(force: true)
            }
        }

        // Auch auf System-Wake lauschen
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            PaulLogger.log("[WakeWord] System aufgewacht, prüfe Status...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.shouldBeListening && !self.audioEngine.isRunning {
                    PaulLogger.log("[WakeWord] AudioEngine war gestoppt nach System-Wake, starte neu...")
                    self.startListening(force: true)
                }
            }
        }

        PaulLogger.log("[WakeWord] Display/System-Wake Notifications registriert")
    }

    func startListening(force: Bool = false) {
        PaulLogger.log("[WakeWord] startListening aufgerufen (force=\(force), isListening=\(isListening), gen=\(generation))")

        shouldBeListening = true

        if isListening && !force {
            PaulLogger.log("[WakeWord] Bereits aktiv, überspringe")
            logDetailedStatus()
            return
        }
        if isListening {
            PaulLogger.log("[WakeWord] War aktiv, stoppe erst...")
            stopListeningInternal()
        }

        generation += 1
        let myGeneration = generation
        bufferCount = 0
        lastPartialResult = ""

        PaulLogger.log("[WakeWord] Neue Generation: \(myGeneration)")
        PaulLogger.log("[WakeWord] SpeechRecognizer verfügbar: \(speechRecognizer?.isAvailable ?? false)")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else {
                PaulLogger.log("[WakeWord] Self ist nil nach Authorization")
                return
            }

            PaulLogger.log("[WakeWord] Authorization Status: \(self.authStatusString(status))")

            guard status == .authorized else {
                PaulLogger.log("[WakeWord] Speech-Erkennung nicht autorisiert: \(status.rawValue)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.generation == myGeneration else {
                    PaulLogger.log("[WakeWord] Veralteter Start ignoriert (gen \(myGeneration) != \(self.generation))")
                    return
                }
                self.beginRecognition(generation: myGeneration)
            }
        }
    }

    private func authStatusString(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorized: return "authorized"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private func beginRecognition(generation gen: Int) {
        PaulLogger.log("[WakeWord] beginRecognition gen=\(gen)")

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        audioEngine = AVAudioEngine()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prüfen ob On-Device-Erkennung verfügbar ist
        if let recognizer = speechRecognizer, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            PaulLogger.log("[WakeWord] Nutze On-Device-Erkennung (unterstützt)")
        } else {
            request.requiresOnDeviceRecognition = false
            PaulLogger.log("[WakeWord] Nutze Cloud-Erkennung (On-Device nicht verfügbar)")
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        PaulLogger.log("[WakeWord] Hardware-Format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount) Kanäle")

        // Optimales Format für Speech Recognition: 16kHz Mono
        guard let speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: 16000,
                                                channels: 1,
                                                interleaved: false) else {
            PaulLogger.log("[WakeWord] Konnte Speech-Format nicht erstellen")
            scheduleRetry(generation: gen)
            return
        }

        PaulLogger.log("[WakeWord] Speech-Format: 16000Hz, 1 Kanal (optimiert)")

        // Converter für Format-Konvertierung
        guard let converter = AVAudioConverter(from: hardwareFormat, to: speechFormat) else {
            PaulLogger.log("[WakeWord] Konnte Audio-Converter nicht erstellen, nutze Hardware-Format")
            // Fallback: Hardware-Format direkt nutzen
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                self.recognitionRequest?.append(buffer)
                self.bufferCount += 1
                self.logBufferStatus()
            }
            startAudioEngineAndRecognition(generation: gen)
            return
        }

        PaulLogger.log("[WakeWord] Audio-Converter erstellt (Hardware → Speech)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Konvertiere zu 16kHz Mono
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / hardwareFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: frameCount) else {
                // Fallback: Original-Buffer senden
                self.recognitionRequest?.append(buffer)
                self.bufferCount += 1
                self.logBufferStatus()
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                self.recognitionRequest?.append(convertedBuffer)
            } else {
                // Fallback bei Konvertierungsfehler
                self.recognitionRequest?.append(buffer)
            }
            self.bufferCount += 1
            self.logBufferStatus()
        }

        startAudioEngineAndRecognition(generation: gen)
    }

    private func logBufferStatus() {
        // Alle 5 Sekunden Buffer-Status loggen
        let now = Date()
        if now.timeIntervalSince(lastBufferLogTime) >= 5.0 {
            PaulLogger.log("[WakeWord] Audio-Buffer: \(bufferCount) empfangen, Engine läuft: \(audioEngine.isRunning)")
            lastBufferLogTime = now
        }
    }

    private func startAudioEngineAndRecognition(generation gen: Int) {
        do {
            try audioEngine.start()
            isListening = true
            PaulLogger.log("[WakeWord] AudioEngine gestartet, lausche auf '\(wakeWord)'...")
            PaulLogger.log("[WakeWord] AudioEngine.isRunning: \(audioEngine.isRunning)")

            // Status-Check Timer starten
            startStatusCheckTimer(generation: gen)
        } catch {
            PaulLogger.log("[WakeWord] AudioEngine Fehler: \(error)")
            PaulLogger.log("[WakeWord] Fehler Details: \((error as NSError).domain) Code: \((error as NSError).code)")
            scheduleRetry(generation: gen)
            return
        }

        guard let recognizer = speechRecognizer else {
            PaulLogger.log("[WakeWord] FEHLER: speechRecognizer ist nil!")
            scheduleRetry(generation: gen)
            return
        }

        guard let request = recognitionRequest else {
            PaulLogger.log("[WakeWord] FEHLER: recognitionRequest ist nil!")
            scheduleRetry(generation: gen)
            return
        }

        PaulLogger.log("[WakeWord] Starte recognitionTask...")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else {
                PaulLogger.log("[WakeWord] Self ist nil im recognitionTask callback")
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                let isFinal = result.isFinal

                // Nur loggen wenn sich Text geändert hat oder final
                if text != self.lastPartialResult || isFinal {
                    PaulLogger.log("[WakeWord] Gehört: '\(text)' (final=\(isFinal))")
                    self.lastPartialResult = text
                }

                if text.contains(self.wakeWord) {
                    PaulLogger.log("[WakeWord] *** WAKE WORD ERKANNT! *** Text: '\(text)'")
                    self.shouldBeListening = false  // Bewusst gestoppt
                    self.stopListeningInternal()
                    DispatchQueue.main.async {
                        PaulLogger.log("[WakeWord] Rufe onWakeWordDetected callback auf...")
                        self.onWakeWordDetected?()
                    }
                    return
                }
            }

            if let error = error {
                let nsError = error as NSError
                PaulLogger.log("[WakeWord] Erkennungsfehler: \(error.localizedDescription)")
                PaulLogger.log("[WakeWord] Error Domain: \(nsError.domain), Code: \(nsError.code)")
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    PaulLogger.log("[WakeWord] Underlying Error: \(underlying.domain) Code: \(underlying.code)")
                }
                // shouldBeListening bleibt true für Retry
                self.stopListeningInternal()
                self.scheduleRetry(generation: gen)
            }
        }

        if recognitionTask == nil {
            PaulLogger.log("[WakeWord] FEHLER: recognitionTask ist nil nach Erstellung!")
        } else {
            PaulLogger.log("[WakeWord] recognitionTask erfolgreich erstellt")
        }
    }

    private func startStatusCheckTimer(generation gen: Int) {
        statusCheckTimer?.invalidate()
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.generation == gen else {
                self.statusCheckTimer?.invalidate()
                return
            }
            self.logDetailedStatus()

            // Auto-Restart wenn AudioEngine unerwartet gestoppt
            if self.shouldBeListening && !self.audioEngine.isRunning {
                PaulLogger.log("[WakeWord] AudioEngine unerwartet gestoppt, starte neu...")
                self.startListening(force: true)
            }
        }
    }

    private func logDetailedStatus() {
        PaulLogger.log("[WakeWord] === STATUS CHECK ===")
        PaulLogger.log("[WakeWord] isListening: \(isListening)")
        PaulLogger.log("[WakeWord] generation: \(generation)")
        PaulLogger.log("[WakeWord] bufferCount: \(bufferCount)")
        PaulLogger.log("[WakeWord] audioEngine.isRunning: \(audioEngine.isRunning)")
        PaulLogger.log("[WakeWord] recognitionRequest: \(recognitionRequest != nil ? "vorhanden" : "nil")")
        PaulLogger.log("[WakeWord] recognitionTask: \(recognitionTask != nil ? "vorhanden" : "nil")")
        if let task = recognitionTask {
            PaulLogger.log("[WakeWord] task.state: \(taskStateString(task.state))")
        }
        PaulLogger.log("[WakeWord] speechRecognizer.isAvailable: \(speechRecognizer?.isAvailable ?? false)")
        PaulLogger.log("[WakeWord] lastPartialResult: '\(lastPartialResult)'")
        PaulLogger.log("[WakeWord] ===================")
    }

    private func taskStateString(_ state: SFSpeechRecognitionTaskState) -> String {
        switch state {
        case .starting: return "starting"
        case .running: return "running"
        case .finishing: return "finishing"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }

    private func scheduleRetry(generation gen: Int) {
        PaulLogger.log("[WakeWord] Plane Retry in 10s (gen=\(gen))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else {
                PaulLogger.log("[WakeWord] Retry: Self ist nil")
                return
            }
            guard self.generation == gen else {
                PaulLogger.log("[WakeWord] Veralteter Retry ignoriert (gen \(gen) != \(self.generation))")
                return
            }
            PaulLogger.log("[WakeWord] Retry wird jetzt ausgeführt (gen=\(gen))")
            self.startListening()
        }
    }

    func stopListening() {
        PaulLogger.log("[WakeWord] stopListening aufgerufen (öffentlich)")
        shouldBeListening = false
        stopListeningInternal()
    }

    /// Interne Stopp-Funktion, setzt shouldBeListening NICHT zurück
    private func stopListeningInternal() {
        PaulLogger.log("[WakeWord] stopListeningInternal aufgerufen")
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)

        audioEngine.stop()
        PaulLogger.log("[WakeWord] AudioEngine gestoppt")

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let task = recognitionTask {
            PaulLogger.log("[WakeWord] Cancelle Task (state=\(taskStateString(task.state)))")
            task.cancel()
        }
        recognitionTask = nil

        isListening = false
        PaulLogger.log("[WakeWord] Gestoppt (bufferCount war: \(bufferCount))")
    }

    func triggerWakeWord() {
        PaulLogger.log("[WakeWord] triggerWakeWord manuell aufgerufen")
        onWakeWordDetected?()
    }

    /// Öffentliche Status-Abfrage für Debugging
    func getStatus() -> String {
        return """
        isListening: \(isListening)
        generation: \(generation)
        bufferCount: \(bufferCount)
        audioEngine.isRunning: \(audioEngine.isRunning)
        recognitionTask: \(recognitionTask != nil ? taskStateString(recognitionTask!.state) : "nil")
        speechRecognizer.isAvailable: \(speechRecognizer?.isAvailable ?? false)
        """
    }
}
