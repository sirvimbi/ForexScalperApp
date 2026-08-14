import Foundation
import Combine

/// Keeps settings that historically lived only in the SwiftUI model synchronized with
/// UserDefaults and the live ScalpingConfig object. This is intentionally a safety net
/// around the Settings screen: changing a setting updates the shared config immediately,
/// and the value survives relaunch even if an older settings path omitted it.
@MainActor
final class SettingsRuntimeBridge {
    static let shared = SettingsRuntimeBridge()
    private var cancellable: AnyCancellable?
    private var started = false
    private let config = ScalpingConfig.shared

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        loadLegacyGaps()
        persistSnapshot()
        cancellable = config.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persistSnapshot() }
        godLog("⚙️ Settings runtime bridge active — UI changes persist and remain live", level: .diagnostic)
    }

    private func loadLegacyGaps() {
        if UserDefaults.standard.object(forKey: "useManualLot") != nil { config.useManualLot = UserDefaults.standard.bool(forKey: "useManualLot") }
        if UserDefaults.standard.object(forKey: "pauseBeforeHighImpactMinutes") != nil { config.pauseBeforeHighImpactMinutes = UserDefaults.standard.double(forKey: "pauseBeforeHighImpactMinutes") }
        if UserDefaults.standard.object(forKey: "pauseBeforeMediumImpactMinutes") != nil { config.pauseBeforeMediumImpactMinutes = UserDefaults.standard.double(forKey: "pauseBeforeMediumImpactMinutes") }
        if UserDefaults.standard.object(forKey: "maxHoldMinutes") != nil { config.maxHoldMinutes = UserDefaults.standard.double(forKey: "maxHoldMinutes") }
        if UserDefaults.standard.object(forKey: "maxDailyTrades") != nil { config.maxDailyTrades = UserDefaults.standard.integer(forKey: "maxDailyTrades") }
        if UserDefaults.standard.object(forKey: "maxConcurrentScalps") != nil { config.maxConcurrentScalps = UserDefaults.standard.integer(forKey: "maxConcurrentScalps") }
        if UserDefaults.standard.object(forKey: "maxCorrelatedTrades") != nil { config.maxCorrelatedTrades = UserDefaults.standard.integer(forKey: "maxCorrelatedTrades") }
    }

    private func persistSnapshot() {
        UserDefaults.standard.set(config.useManualLot, forKey: "useManualLot")
        UserDefaults.standard.set(config.pauseBeforeHighImpactMinutes, forKey: "pauseBeforeHighImpactMinutes")
        UserDefaults.standard.set(config.pauseBeforeMediumImpactMinutes, forKey: "pauseBeforeMediumImpactMinutes")
        UserDefaults.standard.set(config.maxHoldMinutes, forKey: "maxHoldMinutes")
        UserDefaults.standard.set(config.maxDailyTrades, forKey: "maxDailyTrades")
        UserDefaults.standard.set(config.maxConcurrentScalps, forKey: "maxConcurrentScalps")
        UserDefaults.standard.set(config.maxCorrelatedTrades, forKey: "maxCorrelatedTrades")
        config.saveConfig()
    }
}
