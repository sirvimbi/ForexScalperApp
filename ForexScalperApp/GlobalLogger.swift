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

/// Thread-safe logging function that can be called from any context.
nonisolated func godLog(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
    let fileName = (file as NSString).lastPathComponent
    
    // Create a local formatter for thread safety
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    let timestamp = formatter.string(from: Date())
    
    let fullMessage = "[\(timestamp)] \(level.rawValue) \(fileName):\(line) - \(message)"
    
    // Original print for console (stdout is thread-safe)
    print(fullMessage)
    
    // Route to in-app console via notification
    // We use NotificationCenter.default.post which is thread-safe.
    // However, the Name we use must be nonisolated
    NotificationCenter.default.post(name: .newLogEntry, object: LogEntry(message: fullMessage, level: level))
}

extension NSNotification.Name {
    static let newLogEntryInternal = NSNotification.Name("newLogEntryInternal")
}
