import SwiftUI
import AVFoundation

@main
struct PaulApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("openai_api_key") var openAIKey = ""
    @AppStorage("picovoice_access_key") var picovoiceKey = ""
    @AppStorage("openclaw_gateway_token") var gatewayToken = ""

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API Key", text: $openAIKey)
            }
            Section("Picovoice") {
                SecureField("Access Key", text: $picovoiceKey)
            }
            Section("OpenClaw") {
                SecureField("Gateway Token", text: $gatewayToken)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let overlayController = OverlayWindowController()
    private let audioRecorder = AudioRecorder()
    private let audioPlayer = AudioPlayer()
    private let stateManager = StateManager.shared
    private let wakeWordDetector = WakeWordDetector.shared
    private let openClawClient = OpenClawClient.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        PaulLogger.log("[Paul] App startet...")

        // Mikrofon-Permission anfragen
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            PaulLogger.log("[Paul] Mikrofon-Berechtigung: \(granted)")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Paul")
            button.action = #selector(menuBarClicked)
            button.target = self
        }

        setupMenu()
        setupWakeWord()
        setupAudioPipeline()

        stateManager.onFollowUpTimeout = { [weak self] in
            self?.tryReturnToSleep()
        }

        // ESC-Taste zum Abbrechen
        overlayController.onEscapePressed = { [weak self] in
            Task { @MainActor in
                self?.handleEscapeKey()
            }
        }

        // OpenClaw verbinden
        openClawClient.connect()

        // Wake-Word Erkennung starten
        wakeWordDetector.startListening()

        // Begrüßungen vorladen
        Task {
            for text in greetingTexts {
                if let data = try? await TTSService.shared.synthesize(text: text) {
                    greetingCache.append(data)
                    PaulLogger.log("[Paul] Begrüßung gecacht: \(text)")
                }
            }
            PaulLogger.log("[Paul] \(greetingCache.count) Begrüßungen geladen")
        }

        PaulLogger.log("[Paul] App gestartet, bereit.")
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Paul aktivieren", action: #selector(activatePaul), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Einstellungen...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupWakeWord() {
        wakeWordDetector.onWakeWordDetected = { [weak self] in
            Task { @MainActor in
                self?.handleWakeWord()
            }
        }
    }

    private func setupAudioPipeline() {
        audioRecorder.onRecordingComplete = { [weak self] audioURL in
            Task { @MainActor in
                await self?.processRecording(audioURL: audioURL)
            }
        }
    }

    private let greetingTexts = ["Ja?", "Hey!", "Was gibt's?", "Ich bin da!", "Hm?"]
    private var greetingCache: [Data] = []

    @MainActor
    private func handleWakeWord() {
        PaulLogger.log("[Paul] Aktiviert!")

        wakeWordDetector.stopListening()

        stateManager.transition(to: .waking)
        overlayController.show()

        // Sofort aus Cache abspielen
        if let cached = greetingCache.randomElement() {
            PaulLogger.log("[Paul] Begrüßung aus Cache, spiele sofort ab...")
            audioPlayer.onPlaybackComplete = { [weak self] in
                Task { @MainActor in
                    PaulLogger.log("[Paul] Begrüßung fertig, starte Aufnahme...")
                    self?.stateManager.transition(to: .listening)
                    self?.audioRecorder.startRecording()
                }
            }
            audioPlayer.play(data: cached)
            return
        }

        // Fallback: Live TTS
        let greeting = greetingTexts.randomElement()!
        Task {
            do {
                PaulLogger.log("[Paul] TTS '\(greeting)' wird angefordert (kein Cache)...")
                let audioData = try await TTSService.shared.synthesize(text: greeting)
                PaulLogger.log("[Paul] TTS '\(greeting)' erhalten, spiele ab...")

                audioPlayer.onPlaybackComplete = { [weak self] in
                    Task { @MainActor in
                        PaulLogger.log("[Paul] Begrüßung fertig, starte Aufnahme...")
                        self?.stateManager.transition(to: .listening)
                        self?.audioRecorder.startRecording()
                    }
                }
                audioPlayer.play(data: audioData)
            } catch {
                PaulLogger.log("[Paul] TTS Fehler: \(error) - starte direkt")
                stateManager.transition(to: .listening)
                audioRecorder.startRecording()
            }
        }
    }

    @MainActor
    private func processRecording(audioURL: URL) async {
        // Wenn wir bereits schlafen, Aufnahme ignorieren
        if stateManager.currentState == .sleep {
            PaulLogger.log("[Paul] Aufnahme ignoriert (bereits im Sleep)")
            try? FileManager.default.removeItem(at: audioURL)
            return
        }
        PaulLogger.log("[Paul] Aufnahme fertig: \(audioURL.lastPathComponent)")
        stateManager.cancelTimers()

        do {
            // Speech-to-Text (bleibt im Listening-State während Whisper läuft)
            PaulLogger.log("[Paul] Whisper STT startet...")
            let transcription = try await WhisperService.shared.transcribe(audioURL: audioURL)
            PaulLogger.log("[Paul] Transkription: \"\(transcription)\"")

            // Leere oder Whisper-Halluzinationen filtern
            let cleaned = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            let hallucinations = [
                "amara.org", "untertitel", "subtitle", "transcription",
                "thank you for watching", "thanks for watching",
                "vielen dank", "danke fürs zuschauen", "bis zum nächsten mal",
                "copyright", "www.", ".com", ".org", ".de",
            ]
            let isHallucination = cleaned.isEmpty
                || cleaned.count < 3
                || hallucinations.contains(where: { cleaned.lowercased().contains($0) })

            if isHallucination {
                PaulLogger.log("[Paul] Halluzination/Stille gefiltert: \"\(cleaned)\" → Sleep")
                returnToSleep()
                return
            }

            // Erst jetzt in Thinking wechseln - echte Eingabe erkannt
            stateManager.transition(to: .thinking)

            stateManager.transcribedText = transcription

            // An OpenClaw senden
            let responseText: String
            if openClawClient.isConnected {
                PaulLogger.log("[Paul] Sende an OpenClaw: \(transcription)")
                let clawResponse = try await openClawClient.sendMessage(text: transcription)
                responseText = clawResponse.text
            } else {
                responseText = "OpenClaw ist nicht verbunden. Du hast gesagt: \(transcription)"
            }
            PaulLogger.log("[Paul] Antwort: \(responseText.prefix(100))...")

            // Text-to-Speech: erst puffern, dann Speaking-State
            PaulLogger.log("[Paul] TTS Antwort wird geladen...")
            let audioData = try await TTSService.shared.synthesize(text: responseText)
            PaulLogger.log("[Paul] TTS Antwort gepuffert (\(audioData.count) bytes), wechsle zu Speaking")

            stateManager.transition(to: .speaking)
            stateManager.subtitleText = responseText

            audioPlayer.enableMetering()
            audioPlayer.onPlaybackComplete = { [weak self] in
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }
            audioPlayer.play(data: audioData)
            startLipSyncTimer()

        } catch {
            PaulLogger.log("[Paul] Fehler: \(error)")
            stateManager.subtitleText = "Entschuldigung, da ist etwas schiefgelaufen."

            Task {
                if let audioData = try? await TTSService.shared.synthesize(text: "Entschuldigung, da ist etwas schiefgelaufen.") {
                    audioPlayer.onPlaybackComplete = { [weak self] in
                        Task { @MainActor in self?.handlePlaybackComplete() }
                    }
                    audioPlayer.play(data: audioData)
                } else {
                    handlePlaybackComplete()
                }
            }
        }

        try? FileManager.default.removeItem(at: audioURL)
    }

    private var lipSyncTimer: Timer?

    @MainActor
    private func startLipSyncTimer() {
        lipSyncTimer?.invalidate()
        lipSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let level = self.audioPlayer.currentLevel
                let normalized = max(0, (level + 50) / 50)
                self.stateManager.audioLevel = Float(normalized)
            }
        }
    }

    @MainActor
    private func handlePlaybackComplete() {
        PaulLogger.log("[Paul] Playback fertig, warte auf Follow-up...")
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        stateManager.audioLevel = 0

        stateManager.subtitleText = ""
        stateManager.transition(to: .listening)

        // Vollbild-Overlay weg, Mini-Avatar in die Ecke
        overlayController.showMini()

        // Aufnahme starten für Follow-up
        audioRecorder.startRecording()

        // Timeout: wenn nichts kommt → Sleep
        stateManager.startFollowUpTimer()
    }

    /// Vom Follow-up-Timer aufgerufen - nur Sleep wenn nichts läuft
    @MainActor
    private func tryReturnToSleep() {
        let state = stateManager.currentState
        if state == .thinking || state == .speaking {
            PaulLogger.log("[Paul] Sleep aufgeschoben, State ist \(state.rawValue)")
            stateManager.startFollowUpTimer()
            return
        }
        // Wenn noch aufgenommen wird und Silence Detector noch nicht ausgelöst hat, warten
        if audioRecorder.isRecording {
            PaulLogger.log("[Paul] Sleep aufgeschoben, Aufnahme läuft noch")
            stateManager.startFollowUpTimer()
            return
        }
        returnToSleep()
    }

    /// Sofort alles beenden und schlafen
    @MainActor
    private func returnToSleep() {
        PaulLogger.log("[Paul] Zurück in Sleep-Modus (war: \(stateManager.currentState.rawValue))")
        stateManager.cancelTimers()
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        // Callback entfernen BEVOR stopRecording, damit kein processRecording mehr auslöst
        audioRecorder.onRecordingComplete = nil
        audioRecorder.stopRecording()
        // Callback wieder setzen für nächste Session
        audioRecorder.onRecordingComplete = { [weak self] audioURL in
            Task { @MainActor in
                await self?.processRecording(audioURL: audioURL)
            }
        }
        overlayController.hide()
        stateManager.transition(to: .sleep)

        wakeWordDetector.startListening(force: true)
    }

    @MainActor
    private func handleEscapeKey() {
        let state = stateManager.currentState
        guard state != .sleep else { return }

        PaulLogger.log("[Paul] ESC gedrückt - Abbruch (war: \(state.rawValue))")

        // Audio stoppen falls es läuft
        audioPlayer.stop()
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil

        // Aufnahme stoppen
        audioRecorder.onRecordingComplete = nil
        audioRecorder.stopRecording()

        // Callback wieder setzen
        audioRecorder.onRecordingComplete = { [weak self] audioURL in
            Task { @MainActor in
                await self?.processRecording(audioURL: audioURL)
            }
        }

        // Zurück zu Sleep
        stateManager.cancelTimers()
        overlayController.hide()
        stateManager.transition(to: .sleep)
        wakeWordDetector.startListening(force: true)
    }

    @objc private func menuBarClicked() {}

    @objc private func activatePaul() {
        wakeWordDetector.triggerWakeWord()
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paul - Einstellungen"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        wakeWordDetector.stopListening()
        openClawClient.disconnect()
        NSApp.terminate(nil)
    }
}
