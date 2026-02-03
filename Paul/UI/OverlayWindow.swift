import SwiftUI

struct OverlayView: View {
    @ObservedObject var stateManager: StateManager

    var body: some View {
        ZStack {
            // Halbtransparenter Hintergrund
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            // Avatar zentriert
            AvatarView(
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

                AvatarView(
                    state: stateManager.currentState,
                    audioLevel: stateManager.audioLevel
                )
                .scaleEffect(0.2)
                .frame(width: 150, height: 150)
                .clipped()
            }
            .frame(width: 150, height: 150)
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
    }
}

class OverlayWindowController {
    private var fullWindow: NSWindow?
    private var miniWindow: NSWindow?

    func showFull() {
        hideMini()
        guard fullWindow == nil else {
            fullWindow?.makeKeyAndOrderFront(nil)
            return
        }
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
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

        let overlayView = OverlayView(stateManager: StateManager.shared)
        window.contentView = NSHostingView(rootView: overlayView)

        window.makeKeyAndOrderFront(nil)
        fullWindow = window
    }

    func showMini() {
        hideFull()
        guard miniWindow == nil else {
            miniWindow?.makeKeyAndOrderFront(nil)
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

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let miniView = MiniOverlayView(stateManager: StateManager.shared)
        window.contentView = NSHostingView(rootView: miniView)

        window.makeKeyAndOrderFront(nil)
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
    }

    func hide() {
        hideFull()
        hideMini()
    }
}
