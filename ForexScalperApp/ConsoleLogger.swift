// ConsoleLogger.swift - FIXED ACTOR ISOLATION + 30-MINUTE BUFFER ROTATION
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
                switch self { case .info: return "ℹ️"; case .warning: return "⚠️"; case .error: return "❌"; case .success: return "✅"; case .diagnostic: return "🔍" }
            }
            var color: Color {
                switch self { case .info: return .textPrimary; case .warning: return .accentGold; case .error: return .accentRed; case .success: return .accentGreen; case .diagnostic: return .accentCyan }
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()
        startCleanupTimer()
    }

    private func startCleanupTimer() {
        // Rotate the in-app log buffer every 30 minutes. This prevents the SwiftUI
        // log view from retaining a large amount of diagnostic text indefinitely.
        Timer.publish(every: 1800, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.rotateLogBuffer() }
            }
            .store(in: &cancellables)
    }

    private func rotateLogBuffer() {
        let removed = logs.count
        logs.removeAll(keepingCapacity: true)
        lastMessage = nil
        lastMessageTime = .distantPast
        // Xcode's system console is owned by Xcode and cannot be cleared by the app.
        // This rotates the app's retained/in-app ConsoleLogger buffer instead.
        print("🧹 In-app log buffer rotated after 30 minutes (\(removed) entries released)")
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: .newLogEntry, object: nil, queue: .main) { [weak self] notification in
            guard let self, let entry = notification.object as? LogEntry else { return }
            let uiLevel: LogEntryUI.LogLevelUI
            switch entry.level { case .info, .trade: uiLevel = .info; case .success: uiLevel = .success; case .warning: uiLevel = .warning; case .error: uiLevel = .error; case .diagnostic: uiLevel = .diagnostic }
            self.appendLog(entry.message, level: uiLevel, printToConsole: false)
        }
    }

    func log(_ message: String, level: LogEntryUI.LogLevelUI = .info) {
        appendLog(message, level: level, printToConsole: true)
    }

    private func appendLog(_ message: String, level: LogEntryUI.LogLevelUI, printToConsole: Bool) {
        let now = Date()
        if message == lastMessage && now.timeIntervalSince(lastMessageTime) < 0.30 { return }
        lastMessage = message
        lastMessageTime = now
        logs.append(LogEntryUI(timestamp: now, message: message, level: level))
        if logs.count > maxLogs { logs.removeFirst(logs.count - maxLogs) }
        if printToConsole { print(message) }
    }

    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return logs.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }.joined(separator: "\n")
    }

    func clearLogs() {
        logs.removeAll()
        lastMessage = nil
        lastMessageTime = .distantPast
    }
}
