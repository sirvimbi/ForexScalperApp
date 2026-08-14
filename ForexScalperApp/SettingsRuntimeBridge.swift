import Foundation
import Combine

/// Bridges settings that historically were not included in the JSON ConfigData schema
/// and provides a lightweight audit trail showing that saved values reached the runtime config.
@MainActor
final class SettingsRuntimeBridge {
    static let shared = SettingsRuntimeBridge()
    private var cancellables = Set<AnyCancellable>()
    private let manualLotKey = "stellas.useManualLot"

    private init() {
        let config = ScalpingConfig.shared
        if UserDefaults.standard.object(forKey: manualLotKey) != nil {
            config.useManualLot = UserDefaults.standard.bool(forKey: manualLotKey)
        }

        config.$useManualLot
            .removeDuplicates()
            .sink { value in
                UserDefaults.standard.set(value, forKey: "stellas.useManualLot")
                godLog("⚙️ SETTINGS APPLIED | useManualLot=\(value) | manualLot=\(String(format: "%.4f", config.manualLotSize))", level: .info)
            }
            .store(in: &cancellables)
    }

    func saveAll() {
        let config = ScalpingConfig.shared
        config.saveConfig()
        UserDefaults.standard.set(config.useManualLot, forKey: manualLotKey)
        godLog("⚙️ SETTINGS APPLIED | confidence=\(config.confidenceThreshold) | minScore=\(config.minScore) | RR=\(config.minRRRatio) | maxDaily=\(config.maxDailyTrades) | maxConcurrent=\(config.maxConcurrentScalps)", level: .success)
    }
}