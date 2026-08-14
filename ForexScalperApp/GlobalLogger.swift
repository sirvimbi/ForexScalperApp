// GlobalLogger.swift - THREAD-SAFE LOGGING WITH PROPER ACTOR ISOLATION
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

/// Small process-wide de-duplicator for log fan-out.
/// This is a standalone struct that is NOT isolated to any actor.
private struct GlobalLogDeduplicator {
    // ✅ FIX: Use nonisolated(unsafe) for mutable stored properties
    nonisolated(unsafe) private static var recent: [String: Date] = [:]
    nonisolated private static let lock = NSLock()
    nonisolated private static let duplicateWindow: TimeInterval = 0.30

    // ✅ FIX: Mark the method as nonisolated
    nonisolated static func shouldEmit(_ message: String, now: Date = Date()) -> Bool {
        // NSLock operations are thread-safe
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
    // Call shouldEmit directly (now properly nonisolated)
    guard GlobalLogDeduplicator.shouldEmit(message) else { return }

    let fileName = (file as NSString).lastPathComponent

    // Create a local formatter for thread safety
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    let timestamp = formatter.string(from: Date())

    let fullMessage = "[\(timestamp)] \(level.rawValue) \(fileName):\(line) - \(message)"

    // Single stdout emission. ConsoleLogger observes the notification but does not print it.
    print(fullMessage)

    // Route to in-app console via notification - use Task to hop to MainActor
    Task { @MainActor in
        NotificationCenter.default.post(
            name: .newLogEntry,
            object: LogEntry(message: fullMessage, level: level)
        )
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let newLogEntry = Notification.Name("newLogEntry")
}