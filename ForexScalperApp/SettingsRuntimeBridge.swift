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

        Task { @MainActor in
            await syncPositionSettings(config)
        }
    }

    func saveAll() {
        let config = ScalpingConfig.shared
        config.saveConfig()
        UserDefaults.standard.set(config.useManualLot, forKey: manualLotKey)
        godLog("⚙️ SETTINGS APPLIED | confidence=\(config.confidenceThreshold) | minScore=\(config.minScore) | RR=\(config.minRRRatio) | maxDaily=\(config.maxDailyTrades) | maxConcurrent=\(config.maxConcurrentScalps)", level: .success)
        Task { @MainActor in
            await syncPositionSettings(config)
        }
    }

    private func syncPositionSettings(_ config: ScalpingConfig) async {
        let raw = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let url = URL(string: base + "/v1/settings/position-management") else {
            godLog("⚠️ MT5 SETTINGS: invalid bridge URL", level: .warning)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = SecureCredentialStore.shared.read("mt5AuthToken"), !token.isEmpty {
            request.setValue(token.hasPrefix("Bearer ") ? token : "Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "tp1_percent": config.partialTP1_Percent,
            "tp1_pips": config.partialTP1_Pips,
            "tp2_percent": config.partialTP2_Percent,
            "tp2_pips": config.partialTP2_Pips,
            "tp3_percent": config.partialTP3_Percent,
            "tp3_pips": config.partialTP3_Pips,
            "trailing_activation_pips": 5.0,
            "broker_suffix": config.brokerSuffix
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                godLog("⚠️ MT5 SETTINGS: invalid response", level: .warning)
                return
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            guard (200..<300).contains(http.statusCode) else {
                godLog("⚠️ MT5 SETTINGS: HTTP \(http.statusCode) | \(text.prefix(300))", level: .warning)
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, !success {
                godLog("⚠️ MT5 SETTINGS: EA rejected configuration | \(text.prefix(300))", level: .warning)
                return
            }
            godLog("✅ MT5 SETTINGS APPLIED | TP1=\(config.partialTP1_Percent * 100)%/\(config.partialTP1_Pips)p | TP2=\(config.partialTP2_Percent * 100)%/\(config.partialTP2_Pips)p | TP3=\(config.partialTP3_Percent * 100)%/\(config.partialTP3_Pips)p | suffix=\(config.brokerSuffix)", level: .success)
        } catch {
            godLog("⚠️ MT5 SETTINGS: sync failed: \(error.localizedDescription)", level: .warning)
        }
    }
}