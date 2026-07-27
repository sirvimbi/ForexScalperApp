import Foundation
import SwiftUI
import Combine

@MainActor
class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()
    
    @Published var logs: [LogEntry] = []
    private let maxLogs = 2000
    
    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevel
        
        enum LogLevel {
            case info, warning, error, success, diagnostic
        }
    }
    
    private init() {}
    
    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        logs.append(entry)
        
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
        
        // Also print to actual console for dev debugging
        print(message)
    }
    
    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return logs.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }
            .joined(separator: "\n")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}

// Global log function to replace standard print where needed
func godLog(_ message: String, level: ConsoleLogger.LogEntry.LogLevel = .info) {
    Task { @MainActor in
        ConsoleLogger.shared.log(message, level: level)
    }
}
