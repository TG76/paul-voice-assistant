import Foundation

class OpenClawClient: ObservableObject {
    static let shared = OpenClawClient()

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    @Published var isConnected = false

    private var pendingRequests: [String: (Result<[String: Any], Error>) -> Void] = [:]
    private var chatContinuation: CheckedContinuation<OpenClawResponse, Error>?
    private var chatResponseText = ""
    private var currentRunId: String?
    private var chatRequestId: String?

    // MARK: - Connect

    func connect() {
        guard webSocket == nil else { return }

        // Self-signed TLS: accept all certs
        let delegate = InsecureSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        urlSession = session

        let url = AppSettings.gatewayURL
        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()
        receiveMessages()
        PaulLogger.log("[OpenClaw] WebSocket geöffnet zu \(url)")
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        PaulLogger.log("[OpenClaw] Getrennt")
    }

    // MARK: - Send Chat

    func sendMessage(text: String) async throws -> OpenClawResponse {
        guard webSocket != nil, isConnected else {
            throw OpenClawError.notConnected
        }

        chatResponseText = ""
        currentRunId = nil

        let thisRequestId = UUID().uuidString

        return try await withCheckedThrowingContinuation { continuation in
            self.chatContinuation = continuation
            self.chatRequestId = thisRequestId

            let reqId = UUID().uuidString
            let params: [String: Any] = [
                "sessionKey": "agent:main:main",
                "message": text,
                "idempotencyKey": UUID().uuidString,
            ]

            sendRequest(id: reqId, method: "chat.send", params: params) { result in
                switch result {
                case .success(let payload):
                    let runId = payload["runId"] as? String ?? ""
                    PaulLogger.log("[OpenClaw] chat.send akzeptiert, runId: \(runId)")
                    self.currentRunId = runId
                case .failure(let error):
                    PaulLogger.log("[OpenClaw] chat.send Fehler: \(error)")
                    if self.chatRequestId == thisRequestId {
                        self.chatContinuation?.resume(throwing: error)
                        self.chatContinuation = nil
                        self.chatRequestId = nil
                    }
                }
            }

            // Timeout - nur wenn dieser Request noch aktiv ist
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if self.chatRequestId == thisRequestId, let cont = self.chatContinuation {
                    self.chatContinuation = nil
                    self.chatRequestId = nil
                    cont.resume(throwing: OpenClawError.timeout)
                }
            }
        }
    }

    // MARK: - Protocol

    private func sendRequest(id: String, method: String, params: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params,
        ]

        pendingRequests[id] = completion

        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let str = String(data: data, encoding: .utf8)
        else {
            completion(.failure(OpenClawError.serializationError))
            pendingRequests.removeValue(forKey: id)
            return
        }

        webSocket?.send(.string(str)) { error in
            if let error = error {
                PaulLogger.log("[OpenClaw] Send Fehler: \(error)")
                self.pendingRequests.removeValue(forKey: id)
                completion(.failure(error))
            }
        }
    }

    private func sendConnect(nonce _: String?) {
        let reqId = UUID().uuidString
        let params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "gateway-client",
                "displayName": "Paul Voice",
                "version": "1.0.0",
                "platform": "macos",
                "mode": "backend",
            ] as [String: Any],
            "caps": [] as [Any],
            "auth": [
                "token": AppSettings.gatewayToken,
            ] as [String: Any],
            "role": "operator",
            "scopes": ["chat", "operator", "operator.read", "operator.write"],
        ]

        sendRequest(id: reqId, method: "connect", params: params) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.isConnected = true
                    PaulLogger.log("[OpenClaw] Verbunden mit Gateway")
                case .failure(let error):
                    PaulLogger.log("[OpenClaw] Connect fehlgeschlagen: \(error)")
                }
            }
        }
    }

    // MARK: - Receive

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                let text: String?
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8)
                @unknown default: text = nil
                }
                if let text = text {
                    self?.handleFrame(text)
                }
                self?.receiveMessages()

            case .failure(let error):
                PaulLogger.log("[OpenClaw] Receive Fehler: \(error)")
                Task { @MainActor in
                    self?.isConnected = false
                }
                // Reconnect nach 5s
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await MainActor.run {
                        self?.webSocket = nil
                        self?.connect()
                    }
                }
            }
        }
    }

    private func handleFrame(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "event":
            handleEvent(json)
        case "res":
            handleResponse(json)
        default:
            break
        }
    }

    private func handleEvent(_ json: [String: Any]) {
        guard let event = json["event"] as? String else { return }
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch event {
        case "connect.challenge":
            PaulLogger.log("[OpenClaw] Challenge erhalten, sende connect...")
            sendConnect(nonce: payload["nonce"] as? String)

        case "chat":
            handleChatEvent(payload)

        case "tick", "health":
            break // Ignorieren

        default:
            PaulLogger.log("[OpenClaw] Event: \(event)")
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String else { return }

        switch state {
        case "delta":
            if let message = payload["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                chatResponseText = text
            }

        case "final":
            var finalText = chatResponseText
            if let message = payload["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                finalText = text
            }

            PaulLogger.log("[OpenClaw] Antwort: \(finalText.prefix(100))...")
            let response = OpenClawResponse(text: finalText, images: [], urls: [])
            chatContinuation?.resume(returning: response)
            chatContinuation = nil
            chatResponseText = ""
            currentRunId = nil

        case "error":
            let errMsg = payload["errorMessage"] as? String ?? "Unbekannter Fehler"
            PaulLogger.log("[OpenClaw] Chat Fehler: \(errMsg)")
            chatContinuation?.resume(throwing: OpenClawError.chatError(errMsg))
            chatContinuation = nil

        case "aborted":
            PaulLogger.log("[OpenClaw] Chat abgebrochen")
            chatContinuation?.resume(throwing: OpenClawError.chatError("Abgebrochen"))
            chatContinuation = nil

        default:
            break
        }
    }

    private func handleResponse(_ json: [String: Any]) {
        guard let id = json["id"] as? String,
              let ok = json["ok"] as? Bool
        else { return }

        let handler = pendingRequests.removeValue(forKey: id)

        if ok {
            let payload = json["payload"] as? [String: Any] ?? [:]
            handler?(.success(payload))
        } else {
            let error = json["error"] as? [String: Any]
            let msg = error?["message"] as? String ?? "Unknown error"
            let code = error?["code"] as? String ?? "UNKNOWN"
            PaulLogger.log("[OpenClaw] Request Fehler: \(code) - \(msg)")
            handler?(.failure(OpenClawError.requestFailed(code, msg)))
        }
    }
}

// MARK: - TLS Delegate (self-signed certs)

private class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

// MARK: - Types

struct OpenClawResponse {
    let text: String
    let images: [String]
    let urls: [String]
}

enum OpenClawError: Error, LocalizedError {
    case notConnected
    case timeout
    case serializationError
    case requestFailed(String, String)
    case chatError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Nicht mit OpenClaw verbunden"
        case .timeout: return "Zeitüberschreitung bei OpenClaw-Anfrage"
        case .serializationError: return "Serialisierungsfehler"
        case .requestFailed(let code, let msg): return "Request Fehler: \(code) - \(msg)"
        case .chatError(let msg): return "Chat Fehler: \(msg)"
        }
    }
}
