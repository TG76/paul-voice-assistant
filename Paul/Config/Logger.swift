import Foundation

enum PaulLogger {
    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Paul/paul.log")

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print(line, terminator: "")

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

// Performance Timing
class PerfTimer {
    static let shared = PerfTimer()

    private var timings: [String: Date] = [:]
    private var results: [String: TimeInterval] = [:]

    func start(_ phase: String) {
        timings[phase] = Date()
        PaulLogger.log("⏱️ START: \(phase)")
    }

    func end(_ phase: String) {
        guard let startTime = timings[phase] else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        results[phase] = elapsed
        let ms = Int(elapsed * 1000)
        PaulLogger.log("⏱️ END: \(phase) → \(ms) ms")
        timings.removeValue(forKey: phase)
    }

    func reset() {
        timings.removeAll()
        results.removeAll()
        PaulLogger.log("⏱️ RESET Timing")
    }

    func summary() {
        PaulLogger.log("⏱️ ══════════════════════════════════")
        PaulLogger.log("⏱️ TIMING SUMMARY:")
        var total: TimeInterval = 0
        for (phase, duration) in results.sorted(by: { $0.key < $1.key }) {
            let ms = Int(duration * 1000)
            PaulLogger.log("⏱️   \(phase): \(ms) ms")
            total += duration
        }
        PaulLogger.log("⏱️   TOTAL: \(Int(total * 1000)) ms")
        PaulLogger.log("⏱️ ══════════════════════════════════")
    }
}
