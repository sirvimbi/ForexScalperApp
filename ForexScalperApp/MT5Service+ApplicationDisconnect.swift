import Foundation

extension MT5Service {
    private static let applicationDisconnectKey = "mt5ApplicationDisconnected"

    func disconnectForApplication() {
        UserDefaults.standard.set(true, forKey: Self.applicationDisconnectKey)
        godLog("⛔ MT5: Application transport marked disconnected", level: .diagnostic)
    }

    func clearApplicationDisconnect() {
        UserDefaults.standard.set(false, forKey: Self.applicationDisconnectKey)
    }

    func isApplicationDisconnected() -> Bool {
        UserDefaults.standard.bool(forKey: Self.applicationDisconnectKey)
    }
}
