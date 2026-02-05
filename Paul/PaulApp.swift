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
    @AppStorage("followup_enabled") var followUpEnabled = true

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
            Section("Verhalten") {
                Toggle("Follow-up (Rückfrage nach Antwort)", isOn: $followUpEnabled)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let overlayController = OverlayWindowController()
    private let liveTranscriber = LiveTranscriber()
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
        liveTranscriber.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor in
                await self?.processTranscription(text: text)
            }
        }
    }

    private let greetingTexts = ["Ja?", "Hey!", "Was gibt's?", "Ich bin da!", "Hm?"]
    private var greetingCache: [Data] = []

    @MainActor
    private func handleWakeWord() {
        PerfTimer.shared.reset()
        PerfTimer.shared.start("1_WakeToReady")
        PaulLogger.log("[Paul] Aktiviert!")

        wakeWordDetector.stopListening()

        stateManager.transition(to: .waking)
        overlayController.show()

        // Sofort aus Cache abspielen
        if let cached = greetingCache.randomElement() {
            PaulLogger.log("[Paul] Begrüßung aus Cache, spiele sofort ab...")
            audioPlayer.onPlaybackComplete = { [weak self] in
                Task { @MainActor in
                    PerfTimer.shared.end("1_WakeToReady")
                    PerfTimer.shared.start("2_Recording")
                    PaulLogger.log("[Paul] Begrüßung fertig, starte Aufnahme...")
                    self?.stateManager.transition(to: .listening)
                    self?.liveTranscriber.startTranscribing()
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
                        self?.liveTranscriber.startTranscribing()
                    }
                }
                audioPlayer.play(data: audioData)
            } catch {
                PaulLogger.log("[Paul] TTS Fehler: \(error) - starte direkt")
                stateManager.transition(to: .listening)
                liveTranscriber.startTranscribing()
            }
        }
    }

    @MainActor
    private func processTranscription(text: String) async {
        // Wenn wir bereits schlafen, ignorieren
        if stateManager.currentState == .sleep {
            PaulLogger.log("[Paul] Transkription ignoriert (bereits im Sleep)")
            return
        }
        PerfTimer.shared.end("2_Recording")
        PaulLogger.log("[Paul] Live-STT fertig: \"\(text)\"")
        stateManager.cancelTimers()

        // Leere Eingabe filtern
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.count < 3 {
            PaulLogger.log("[Paul] Leere/kurze Eingabe: \"\(cleaned)\" → Sleep")
            returnToSleep()
            return
        }

        do {
            // Direkt in Thinking wechseln - Text ist bereits da!
            stateManager.transition(to: .thinking)
            stateManager.transcribedText = text

            // An OpenClaw senden
            PerfTimer.shared.start("3_OpenClaw")
            var responseText: String
            if openClawClient.isConnected {
                PaulLogger.log("[Paul] Sende an OpenClaw: \(text)")
                let clawResponse = try await openClawClient.sendMessage(text: text)
                responseText = clawResponse.text
            } else {
                responseText = "OpenClaw ist nicht verbunden. Du hast gesagt: \(text)"
            }
            PerfTimer.shared.end("3_OpenClaw")

            // Leere oder Platzhalter-Antworten abfangen
            let cleanedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedResponse.isEmpty || cleanedResponse == "..." || cleanedResponse == "…" || cleanedResponse.count < 3 {
                PaulLogger.log("[Paul] Leere Antwort von OpenClaw, verwende Fallback")
                responseText = "Hmm, da kam leider keine Antwort. Versuch es nochmal."
            }

            PaulLogger.log("[Paul] Antwort: \(responseText.prefix(100))...")

            // TTS Streaming: sofort Speaking-State, Audio streamen
            PerfTimer.shared.start("4_TTS")
            PaulLogger.log("[Paul] TTS Streaming startet...")

            stateManager.transition(to: .speaking)
            stateManager.subtitleText = responseText

            audioPlayer.onPlaybackComplete = { [weak self] in
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }
            audioPlayer.startStreaming()
            startLipSyncTimer()

            var firstChunk = true
            for try await chunk in TTSService.shared.synthesizeStreaming(text: responseText) {
                if firstChunk {
                    PerfTimer.shared.end("4_TTS")
                    PaulLogger.log("[Paul] Erster TTS-Chunk angekommen, Playback startet")
                    PerfTimer.shared.summary()
                    firstChunk = false
                }
                audioPlayer.scheduleBuffer(pcmData: chunk)
            }
            audioPlayer.finishStreaming()

        } catch {
            PaulLogger.log("[Paul] Fehler: \(error)")
            let errorText = "Entschuldigung, da ist etwas schiefgelaufen."
            stateManager.subtitleText = errorText
            stateManager.transition(to: .speaking)

            audioPlayer.onPlaybackComplete = { [weak self] in
                Task { @MainActor in self?.handlePlaybackComplete() }
            }

            // Fallback auf non-streaming TTS für Fehlermeldungen
            if let audioData = try? await TTSService.shared.synthesize(text: errorText) {
                audioPlayer.play(data: audioData)
            } else {
                handlePlaybackComplete()
            }
        }
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
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        stateManager.audioLevel = 0
        stateManager.subtitleText = ""

        let followUpEnabled = UserDefaults.standard.bool(forKey: "followup_enabled")
        // Default: true (wenn noch nie gesetzt)
        let isEnabled = UserDefaults.standard.object(forKey: "followup_enabled") == nil ? true : followUpEnabled

        guard isEnabled else {
            PaulLogger.log("[Paul] Playback fertig, Follow-up deaktiviert → Sleep")
            returnToSleep()
            return
        }

        PaulLogger.log("[Paul] Playback fertig, warte auf Follow-up...")
        stateManager.transition(to: .listening)

        // Vollbild-Overlay weg, Mini-Avatar in die Ecke
        overlayController.showMini()

        // Live-Transkription starten für Follow-up (Stille-Timer erst nach Sprache)
        liveTranscriber.startTranscribing(waitForSpeech: true)

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
        if liveTranscriber.isRecording {
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
        // Callback entfernen BEVOR stopTranscribing, damit kein processTranscription mehr auslöst
        liveTranscriber.onTranscriptionComplete = nil
        liveTranscriber.stopTranscribing()
        // Callback wieder setzen für nächste Session
        liveTranscriber.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor in
                await self?.processTranscription(text: text)
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

        // Transkription stoppen
        liveTranscriber.onTranscriptionComplete = nil
        liveTranscriber.stopTranscribing()

        // Callback wieder setzen
        liveTranscriber.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor in
                await self?.processTranscription(text: text)
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
