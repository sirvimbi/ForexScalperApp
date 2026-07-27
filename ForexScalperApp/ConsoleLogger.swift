import Foundation
import SwiftUI
import Combine

@MainActor
class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()
    
    @Published var logs: [LogEntryUI] = []
    private let maxLogs = 2000
    
    struct LogEntryUI: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevelUI
        
        enum LogLevelUI: Sendable {
            case info, warning, error, success, diagnostic
        }
    }
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.newLogEntryInternal,
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
