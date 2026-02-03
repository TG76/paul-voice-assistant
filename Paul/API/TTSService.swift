import Foundation

class TTSService {
    static let shared = TTSService()

    func synthesize(text: String) async throws -> Data {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AppSettings.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": AppSettings.ttsModel,
            "input": text,
            "voice": AppSettings.ttsVoice,
            "response_format": "mp3",
            "speed": AppSettings.ttsSpeed,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError(errorText)
        }

        return data
    }
}

enum TTSError: Error, LocalizedError {
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "TTS API Fehler: \(msg)"
        }
    }
}
