import Foundation

extension MT5Service {
    /// MT5's HTTP bridge is request/response based. The persistent app-side transport
    /// is the event WebSocket, which is closed by MT5ConnectionControls. This method
    /// exists as a single semantic hook for the UI/service layer and deliberately does
    /// not pretend to terminate the broker terminal itself.
    func disconnectForApplication() {
        godLog("⛔ MT5: Application disconnect requested", level: .diagnostic)
    }
}
