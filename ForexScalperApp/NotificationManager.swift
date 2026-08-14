@preconcurrency import UserNotifications
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    @Published var isAuthorized = false

    enum SoundKind { case jackpot, urgent, passive, win, loss, partial }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestAuthorization()
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: UIApplication.willEnterForegroundNotification, object: nil)
        #else
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: NSApplication.willBecomeActiveNotification, object: nil)
        #endif
    }

    @objc func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.isAuthorized = granted
                if granted { self.sendTestNotification() }
            }
        }
    }

    private func notificationSound(for kind: SoundKind) -> UNNotificationSound {
        // Bundled custom sounds can be supplied later without changing routing.
        // The foreground macOS path below uses distinct system sounds immediately.
        return .default
    }

    private func playForegroundSound(_ kind: SoundKind) {
        #if os(macOS)
        let name: NSSound.Name
        switch kind {
        case .jackpot: name = NSSound.Name("Glass")
        case .urgent: name = NSSound.Name("Ping")
        case .passive: name = NSSound.Name("Pop")
        case .win: name = NSSound.Name("Hero")
        case .loss: name = NSSound.Name("Basso")
        case .partial: name = NSSound.Name("Tink")
        }
        NSSound(named: name)?.play()
        #endif
    }

    private func signalSoundKind(_ confidence: Double) -> SoundKind {
        if confidence >= 85 { return .jackpot }
        if confidence >= 80 { return .urgent }
        return .passive
    }

    func sendSignalNotification(_ signal: Signal) {
        guard isAuthorized else { return }
        let kind = signalSoundKind(signal.confidence)
        let content = UNMutableNotificationContent()
        content.title = "🚨 \(signal.symbol) \(signal.type.displayName) SIGNAL"
        content.body = String(format: "Price: %.5f | Confidence: %.0f%% | Expires: %@", signal.price, signal.confidence, formatExpiryTime(signal.expiryTime))
        content.sound = notificationSound(for: kind)
        content.interruptionLevel = signal.confidence >= 80 ? .timeSensitive : .active
        content.categoryIdentifier = "SIGNAL_ACTION"
        let request = UNNotificationRequest(identifier: "signal_\(signal.id.uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
        playForegroundSound(kind)
        godLog("🔔 SIGNAL NOTIFICATION | \(signal.symbol) | confidence=\(String(format: "%.0f", signal.confidence))% | sound=\(String(describing: kind))", level: .diagnostic)
    }

    func sendTradeClosedNotification(_ trade: TradeRecord) {
        guard isAuthorized, trade.status == .completed, (trade.remainingVolume ?? 0) <= 0 else { return }
        let pnl = trade.pnl ?? 0
        let kind: SoundKind = pnl >= 0 ? .win : .loss
        let content = UNMutableNotificationContent()
        content.title = "\(pnl >= 0 ? "✅" : "❌") \(trade.symbol) Trade Closed"
        content.body = String(format: "P&L: %@KES %.2f (%.2f%%)", pnl >= 0 ? "+" : "", pnl, trade.pnlPercent ?? 0)
        content.sound = notificationSound(for: kind)
        content.interruptionLevel = .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trade_\(trade.id.uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)) )
        playForegroundSound(kind)
    }

    func sendPartialCloseNotification(symbol: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "💰 \(symbol) Partial TP"
        content.body = "Partial close executed; remaining runner is protected by trailing SL."
        content.sound = notificationSound(for: .partial)
        content.interruptionLevel = .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "partial_\(symbol)_\(UUID().uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        playForegroundSound(.partial)
    }

    private func formatExpiryTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; return formatter.string(from: date)
    }

    func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent(); content.title = "Stellas System Check"; content.body = "Notification pipe is now active and synced."; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "system_test_\(UUID().uuidString)", content: content, trigger: nil))
    }
}

extension NotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound, .badge]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("signal_") { NotificationCenter.default.post(name: .showSignalDashboard, object: nil) }
        completionHandler()
    }
}
