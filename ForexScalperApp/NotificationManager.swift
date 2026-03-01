import UserNotifications
import SwiftUI
import Combine

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestAuthorization()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    print("✅ Notification permission granted")
                } else if let error = error {
                    print("❌ Notification permission error: \(error)")
                }
            }
        }
    }
    
    func sendSignalNotification(_ signal: Signal) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🚨 \(signal.symbol) \(signal.type.displayName) SIGNAL"
        content.body = String(
            format: "Price: %.5f | Confidence: %.0f%% | Expires: %@",
            signal.price,
            signal.confidence,
            formatExpiryTime(signal.expiryTime)
        )
        content.sound = UNNotificationSound(named: UNNotificationSoundName("default"))
        content.interruptionLevel = .timeSensitive
        
        // Add action buttons
        content.categoryIdentifier = "SIGNAL_ACTION"
        
        // Create trigger immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "signal_\(signal.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error)")
            } else {
                print("✅ Signal notification sent for \(signal.symbol)")
            }
        }
    }
    
    func sendTradeClosedNotification(_ trade: TradeRecord) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        let pnlEmoji = (trade.pnl ?? 0) >= 0 ? "✅" : "❌"
        content.title = "\(pnlEmoji) \(trade.symbol) Trade Closed"
        content.body = String(
            format: "P&L: %@$%.2f (%.2f%%)",
            (trade.pnl ?? 0) >= 0 ? "+" : "",
            trade.pnl ?? 0,
            trade.pnlPercent ?? 0
        )
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "trade_\(trade.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func formatExpiryTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification response
        let identifier = response.notification.request.identifier
        
        if identifier.hasPrefix("signal_") {
            // Post notification to open the signal
            NotificationCenter.default.post(name: .showSignalDashboard, object: nil)
        }
        
        completionHandler()
    }
}
