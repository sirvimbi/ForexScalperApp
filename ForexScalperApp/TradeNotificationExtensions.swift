// TradeNotificationExtensions.swift - FIXED
import Foundation

extension Notification.Name {
    nonisolated static let tradePartiallyClosed = Notification.Name("tradePartiallyClosed")
}

@MainActor
final class TradeNotificationBridge {
    static let shared = TradeNotificationBridge()
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .tradePartiallyClosed,
            object: nil,
            queue: .main
        ) { notification in
            guard let symbol = notification.object as? String else { return }
            Task { @MainActor in
                NotificationManager.shared.sendPartialCloseNotification(symbol: symbol)
            }
        }
    }
}

// Force initialization when the notification manager is first used.
extension NotificationManager {
    func installTradeNotificationBridge() {
        _ = TradeNotificationBridge.shared
    }
}