import Foundation
import SwiftUI
import Combine

@MainActor
class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()
    
    @Published var logs: [LogEntryUI] = []
    private let maxLogs = 1000
    
    struct LogEntryUI: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevelUI
        
        enum LogLevelUI: Sendable {
            case info, warning, error, success, diagnostic
            
            var icon: String {
                switch self {
                case .info: return "ℹ️"
                case .warning: return "⚠️"
                case .error: return "❌"
                case .success: return "✅"
                case .diagnostic: return "🔍"
                }
            }
            
            var color: Color {
                switch self {
                case .info: return .textPrimary
                case .warning: return .accentGold
                case .error: return .accentRed
                case .success: return .accentGreen
                case .diagnostic: return .accentCyan
                }
            }
        }
    }
    
    private init() {
        setupObservers()
        startCleanupTimer()
    }
    
    private func startCleanupTimer() {
        // Run cleanup every 5 minutes
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanupOldLogs()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func cleanupOldLogs() {
        let thirtyMinutesAgo = Date().addingTimeInterval(-1800)
        let originalCount = logs.count
        logs.removeAll { $0.timestamp < thirtyMinutesAgo }
        
        let removed = originalCount - logs.count
        if removed > 0 {
            log("🧹 Log Cleanup: Removed \(removed) entries older than 30 minutes", level: .diagnostic)
        }
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .newLogEntry,
            object: nil,
            queue: .main
        ) { notification in
            if let entry = notification.object as? LogEntry {
                let uiLevel: LogEntryUI.LogLevelUI
                switch entry.level {
                case .info: uiLevel = .info
                case .trade: uiLevel = .info
                case .success: uiLevel = .success
                case .warning: uiLevel = .warning
                case .error: uiLevel = .error
                case .diagnostic: uiLevel = .diagnostic
                }
                DispatchQueue.main.async {
                    self.log(entry.message, level: uiLevel)
                }
            }
        }
    }
    
    func log(_ message: String, level: LogEntryUI.LogLevelUI = .info) {
        let entry = LogEntryUI(timestamp: Date(), message: message, level: level)
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
