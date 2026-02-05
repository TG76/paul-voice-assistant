import Foundation

class TTSService {
    static let shared = TTSService()

    /// Legacy: Komplette MP3 laden (für Fallback)
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

    /// Streaming: PCM-Chunks als AsyncStream (24kHz, 16-bit signed LE, mono)
    func synthesizeStreaming(text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.openai.com/v1/audio/speech")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(AppSettings.openAIAPIKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "model": AppSettings.ttsModel,
                        "input": text,
                        "voice": AppSettings.ttsVoice,
                        "response_format": "pcm",  // Raw PCM für Streaming
                        "speed": AppSettings.ttsSpeed,
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw TTSError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }

                    PaulLogger.log("[TTS] Streaming gestartet...")
                    var chunkCount = 0
                    var totalBytes = 0

                    // Chunks sammeln und in größeren Blöcken liefern (für smootheres Playback)
                    let chunkSize = 4800  // 100ms bei 24kHz 16-bit mono
                    var buffer = Data()

                    for try await byte in bytes {
                        buffer.append(byte)

                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            totalBytes += buffer.count
                            chunkCount += 1
                            buffer = Data()
                        }
                    }

                    // Rest-Buffer senden
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                        totalBytes += buffer.count
                        chunkCount += 1
                    }

                    PaulLogger.log("[TTS] Streaming fertig: \(chunkCount) chunks, \(totalBytes) bytes")
                    continuation.finish()

                } catch {
                    PaulLogger.log("[TTS] Streaming Fehler: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
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
