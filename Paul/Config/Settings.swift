import Foundation

enum AppSettings {
    static let openAIAPIKey: String = {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            return key
        }
        // Fallback: aus UserDefaults oder Keychain
        return UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    }()

    static let picovoiceAccessKey: String = {
        ProcessInfo.processInfo.environment["PICOVOICE_ACCESS_KEY"]
            ?? UserDefaults.standard.string(forKey: "picovoice_access_key")
            ?? ""
    }()

    static let gatewayURL = URL(string:
        ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_URL"]
            ?? "wss://127.0.0.1:18789"
    )!

    static let gatewayToken: String = {
        ProcessInfo.processInfo.environment["OPENCLAW_GATEWAY_TOKEN"]
            ?? UserDefaults.standard.string(forKey: "openclaw_gateway_token")
            ?? ""
    }()

    static let whisperModel = "whisper-1"
    static let whisperLanguage = "de"
    static let ttsModel = "tts-1"
    static let ttsVoice = "fable"
    static let ttsSpeed = 1.2

    static let silenceThreshold: Float = 0.01
    static let silenceDuration: TimeInterval = 4.0
    static let followUpTimeout: TimeInterval = 5.0
    static let displayOffDelay: TimeInterval = 3.0
}
