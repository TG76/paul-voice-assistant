import SwiftUI
import Carbon.HIToolbox

// MARK: - Custom Window that accepts key events

class KeyableWindow: NSWindow {
    var onEscapePressed: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onEscapePressed?()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct OverlayView: View {
    @ObservedObject var stateManager: StateManager

    var body: some View {
        ZStack {
            // Halbtransparenter Hintergrund
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            // Chibi Avatar zentriert
            ChibiAvatarView(
                state: stateManager.currentState,
                audioLevel: stateManager.audioLevel
            )

            // Unterer Bereich
            VStack(spacing: 16) {
                Spacer()

                if stateManager.isRecording {
                    WaveformView(audioLevel: stateManager.audioLevel)
                        .padding(.horizontal, 60)
                        .transition(.opacity)
                }

                if stateManager.currentState == .speaking && !stateManager.subtitleText.isEmpty {
                    Text(stateManager.subtitleText)
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                        .transition(.opacity)
                }

                if stateManager.contentImageURL != nil || stateManager.contentWebURL != nil {
                    ContentDisplayView(
                        imageURL: stateManager.contentImageURL,
                        webURL: stateManager.contentWebURL
                    )
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 50)
        }
        .animation(.easeInOut(duration: 0.3), value: stateManager.currentState)
        .animation(.easeInOut(duration: 0.3), value: stateManager.isRecording)
    }
}

struct MiniOverlayView: View {
    @ObservedObject var stateManager: StateManager

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.85))

                ChibiAvatarView(
                    state: stateManager.currentState,
                    audioLevel: stateManager.audioLevel
                )
                .scaleEffect(0.35)
            }
            .frame(width: 150, height: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20))

            if stateManager.isRecording {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.85))
                    WaveformView(audioLevel: stateManager.audioLevel)
                        .scaleEffect(x: 1, y: 0.25)
                        .frame(height: 24)
                        .padding(.horizontal, 8)
                }
                .frame(width: 150, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
        .frame(height: 190, alignment: .top)
    }
}

class OverlayWindowController {
    private var fullWindow: KeyableWindow?
    private var miniWindow: KeyableWindow?
    private var globalEscMonitor: Any?

    var onEscapePressed: (() -> Void)?

    func showFull() {
        hideMini()
        guard fullWindow == nil else {
            fullWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let screen = NSScreen.main else { return }

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.onEscapePressed = { [weak self] in
            self?.onEscapePressed?()
        }

        let overlayView = OverlayView(stateManager: StateManager.shared)
        window.contentView = NSHostingView(rootView: overlayView)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fullWindow = window
    }

    func showMini() {
        hideFull()
        guard miniWindow == nil else {
            miniWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 150
        let height: CGFloat = 200  // Platz für Avatar + Waveform + Abstand
        let padding: CGFloat = 20
        let frame = NSRect(
            x: screen.visibleFrame.maxX - width - padding,
            y: screen.visibleFrame.minY + padding,
            width: width,
            height: height
        )

        let window = KeyableWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false  // Muss false sein für Key-Events
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.onEscapePressed = { [weak self] in
            self?.onEscapePressed?()
        }

        let miniView = MiniOverlayView(stateManager: StateManager.shared)
        window.contentView = NSHostingView(rootView: miniView)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        miniWindow = window
    }

    func hideFull() {
        fullWindow?.orderOut(nil)
        fullWindow = nil
    }

    func hideMini() {
        miniWindow?.orderOut(nil)
        miniWindow = nil
    }

    func show() {
        showFull()
        startGlobalEscMonitor()
    }

    func hide() {
        hideFull()
        hideMini()
        stopGlobalEscMonitor()
    }

    /// Globaler ESC-Monitor: fängt ESC auch ab wenn Paul nicht den Fokus hat
    private func startGlobalEscMonitor() {
        guard globalEscMonitor == nil else { return }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // kVK_Escape
                DispatchQueue.main.async {
                    self?.onEscapePressed?()
                }
            }
        }
    }

    private func stopGlobalEscMonitor() {
        if let monitor = globalEscMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscMonitor = nil
        }
    }
}
