// ConsoleLogger.swift - FIXED ACTOR ISOLATION
import Foundation
import SwiftUI
import Combine

@MainActor
class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()

    @Published var logs: [LogEntryUI] = []
    private let maxLogs = 5000
    private var lastMessage: String?
    private var lastMessageTime = Date.distantPast

    struct LogEntryUI: Identifiable, Equatable, Sendable {
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
        Timer.publish(every: 300, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldLogs()
            }
        }
        .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func cleanupOldLogs() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let originalCount = logs.count
        logs.removeAll { $0.timestamp < oneHourAgo }

        let removed = originalCount - logs.count
        if removed > 0 {
            appendLog("🧹 Log Cleanup: Removed \(removed) entries older than 60 minutes", level: .diagnostic, printToConsole: true)
        }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .newLogEntry,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let entry = notification.object as? LogEntry else { return }

            let uiLevel: LogEntryUI.LogLevelUI
            switch entry.level {
            case .info, .trade: uiLevel = .info
            case .success: uiLevel = .success
            case .warning: uiLevel = .warning
            case .error: uiLevel = .error
            case .diagnostic: uiLevel = .diagnostic
            }

            // godLog() already prints to stdout. Do not print again here; this was the
            // source of the duplicated lines visible in the runtime logs.
            self.appendLog(entry.message, level: uiLevel, printToConsole: false)
        }
    }

    func log(_ message: String, level: LogEntryUI.LogLevelUI = .info) {
        appendLog(message, level: level, printToConsole: true)
    }

    private func appendLog(_ message: String, level: LogEntryUI.LogLevelUI, printToConsole: Bool) {
        let now = Date()
        if message == lastMessage && now.timeIntervalSince(lastMessageTime) < 0.30 {
            return
        }
        lastMessage = message
        lastMessageTime = now

        let entry = LogEntryUI(timestamp: now, message: message, level: level)
        logs.append(entry)

        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        if printToConsole {
            print(message)
        }
    }

    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return logs.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }
        .joined(separator: "\n")
    }

    func clearLogs() {
        logs.removeAll()
        lastMessage = nil
        lastMessageTime = .distantPast
    }
}