import Foundation
import SwiftUI

enum PaulState: String, CaseIterable {
    case sleep
    case idle
    case waking
    case listening
    case thinking
    case speaking
}

@MainActor
class StateManager: ObservableObject {
    static let shared = StateManager()

    @Published var currentState: PaulState = .sleep
    @Published var subtitleText: String = ""
    @Published var transcribedText: String = ""
    @Published var contentImageURL: URL? = nil
    @Published var contentWebURL: URL? = nil
    @Published var audioLevel: Float = 0.0
    @Published var showOverlay: Bool = false
    @Published var isRecording: Bool = false

    private var followUpTimer: Timer?

    /// Wird aufgerufen wenn Follow-up-Timeout abläuft
    var onFollowUpTimeout: (() -> Void)?

    func transition(to newState: PaulState) {
        let oldState = currentState
        currentState = newState

        switch newState {
        case .sleep:
            showOverlay = false
            subtitleText = ""
            contentImageURL = nil
            contentWebURL = nil
            cancelTimers()
            DisplayController.shared.allowSleep()
            // Display-Sleep wird dem System überlassen

        case .idle:
            showOverlay = false
            subtitleText = ""

        case .waking:
            showOverlay = true
            subtitleText = ""
            transcribedText = ""
            contentImageURL = nil
            contentWebURL = nil
            DisplayController.shared.wakeDisplay()
            DisplayController.shared.preventSleep()

        case .listening:
            showOverlay = true
            subtitleText = ""
            // Timer NICHT canceln - Follow-up-Timer soll weiterlaufen

        case .thinking:
            cancelTimers()
            subtitleText = "Hmm, lass mich überlegen..."

        case .speaking:
            break
        }
    }

    func startFollowUpTimer() {
        cancelTimers()
        PaulLogger.log("[StateManager] Follow-up Timer gestartet (\(AppSettings.followUpTimeout)s)")
        followUpTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.followUpTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                PaulLogger.log("[StateManager] Follow-up Timeout - zurück in Sleep")
                self?.onFollowUpTimeout?()
            }
        }
    }

    func cancelTimers() {
        followUpTimer?.invalidate()
        followUpTimer = nil
    }
}
