@preconcurrency import UserNotifications
import SwiftUI
import Combine

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestAuthorization()

        // Refresh status when app returns to foreground
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshStatus),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #else
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshStatus),
            name: NSApplication.willBecomeActiveNotification,
            object: nil
        )
        #endif
    }

    @objc func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                var authorized = settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional

                #if os(iOS)
                if settings.authorizationStatus == .ephemeral {
                    authorized = true
                }
                #endif

                if self.isAuthorized != authorized {
                    self.isAuthorized = authorized
                    print("🔔 Notification status updated: \(authorized ? "Authorized" : "Not Authorized")")
                }
            }
        }
    }

    func requestAuthorization() {
        print("🔔 NotificationManager: Requesting authorization...")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("🔔 Current settings status: \(settings.authorizationStatus.rawValue)")
            switch settings.authorizationStatus {
            case .notDetermined, .denied:
                // SIMPLIFIED: Removed .criticalAlert which requires special Apple approval
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    DispatchQueue.main.async {
                        self.isAuthorized = granted
                        if granted {
                            print("✅ Notification permission GRANTED")
                            // Trigger immediate test notification to confirm
                            self.sendTestNotification()
                        } else {
                            print("⚠️ Notification DENIED. Please check System Settings.")
                        }
                    }
                }
            case .authorized, .provisional:
                DispatchQueue.main.async {
                    self.isAuthorized = true
                    print("✅ Notifications are already authorized")
                }
            default:
                #if os(iOS)
                if settings.authorizationStatus == .ephemeral {
                    DispatchQueue.main.async {
                        self.isAuthorized = true
                        print("✅ Notifications are already authorized (ephemeral)")
                    }
                    return
                }
                #endif
                break
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

    // ✅ FIXED: Filter partial closures - only send for FULL closes
    func sendTradeClosedNotification(_ trade: TradeRecord) {
        guard isAuthorized else { return }

        // ✅ Don't send notification for partial closes or if trade is still active
        if trade.isPartialClosed && trade.status == .active {
            print("🔇 Skipping notification - partial close only (remaining volume: \(trade.remainingVolume ?? 0))")
            return
        }

        // ✅ Don't send if it's not actually completed
        if trade.status != .completed {
            print("🔇 Skipping notification - trade not completed (status: \(trade.status))")
            return
        }

        // ✅ Only send for FULL closes (no remaining volume)
        if trade.remainingVolume ?? 0 > 0 {
            print("🔇 Skipping notification - remaining volume exists: \(trade.remainingVolume ?? 0)")
            return
        }

        let content = UNMutableNotificationContent()
        let pnlEmoji = (trade.pnl ?? 0) >= 0 ? "✅" : "❌"
        content.title = "\(pnlEmoji) \(trade.symbol) Trade Closed"

        let pnlValue = trade.pnl ?? 0
        let pnlPercent = trade.pnlPercent ?? 0

        content.body = String(
            format: "P&L: %@KES %.2f (%.2f%%)",
            pnlValue >= 0 ? "+" : "",
            pnlValue,
            pnlPercent
        )

        // Add partial close info if applicable
        if let originalVol = trade.originalVolume, let remainingVol = trade.remainingVolume, originalVol > remainingVol {
            let closedPercent = ((originalVol - remainingVol) / originalVol) * 100
            content.body += " | Closed: \(String(format: "%.0f", closedPercent))%"
        }

        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "trade_\(trade.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send trade notification: \(error)")
            } else {
                print("✅ Trade notification sent for \(trade.symbol)")
            }
        }
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

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Stellas System Check"
        content.body = "Notification pipe is now active and synced."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "system_test_\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
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