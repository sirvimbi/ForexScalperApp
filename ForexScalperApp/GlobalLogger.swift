// GlobalLogger.swift - THREAD-SAFE LOGGING
import Foundation

enum LogLevel: String, Sendable {
    case info = "ℹ️"
    case success = "✅"
    case warning = "⚠️"
    case error = "❌"
    case diagnostic = "🔍"
    case trade = "📊"
}

struct LogEntry: Sendable {
    let message: String
    let level: LogLevel
}

/// Small process-wide de-duplicator for log fan-out. Multiple service callbacks can
/// legitimately report the same event in the same run-loop window; printing it twice
/// makes the runtime trace misleading without adding information.
private enum GlobalLogDeduplicator {
    static let lock = NSLock()
    static var recent: [String: Date] = [:]
    static let duplicateWindow: TimeInterval = 0.30

    static func shouldEmit(_ message: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let previous = recent[message], now.timeIntervalSince(previous) < duplicateWindow {
            return false
        }

        recent[message] = now
        if recent.count > 512 {
            let cutoff = now.addingTimeInterval(-5.0)
            recent = recent.filter { $0.value >= cutoff }
        }
        return true
    }
}

/// Thread-safe logging function that can be called from any context.
nonisolated func godLog(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
    // Suppress only identical messages emitted within the same short callback window.
    // Distinct messages, errors, requests and repeated events after the window remain visible.
    guard GlobalLogDeduplicator.shouldEmit(message) else { return }

    let fileName = (file as NSString).lastPathComponent

    // Create a local formatter for thread safety
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    let timestamp = formatter.string(from: Date())

    let fullMessage = "[\(timestamp)] \(level.rawValue) \(fileName):\(line) - \(message)"

    // Single stdout emission. ConsoleLogger observes the notification but does not print it.
    print(fullMessage)

    // Route to in-app console via notification.
    NotificationCenter.default.post(
        name: .newLogEntry,
        object: LogEntry(message: fullMessage, level: level)
    )
}

extension NSNotification.Name {
    static let newLogEntryInternal = NSNotification.Name("newLogEntryInternal")
}
