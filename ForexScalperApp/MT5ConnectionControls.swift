import Foundation

@MainActor
extension DashboardViewModel {
    /// Disconnects the app-side MT5 transport and prevents normal execution checks from
    /// being treated as connected by the UI until the user explicitly reconnects.
    func disconnectFromMT5() async {
        godLog("⏹️ MT5: User requested disconnect", level: .info)
        await MT5WebSocketService.shared.disconnect()
        await MT5Service.shared.disconnectForApplication()
        mt5Connected = false
        isConnecting = false
        godLog("⛔ MT5: App-side connection disconnected", level: .success)
    }
}
