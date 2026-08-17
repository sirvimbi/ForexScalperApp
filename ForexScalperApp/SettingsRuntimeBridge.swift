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
        Task {
            await MT5ProtectionSettingsSync.shared.sync(config: config)
        }
    }
}

actor MT5ProtectionSettingsSync {
    static let shared = MT5ProtectionSettingsSync()

    func sync(config: ScalpingConfig) async {
        let rawBase = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
        let baseURL = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
        guard let url = URL(string: baseURL + "/v1/settings/protection") else {
            godLog("⚠️ PROTECTION SETTINGS | invalid MT5 bridge URL", level: .warning)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let saved = SecureCredentialStore.shared.read("mt5AuthToken"), !saved.isEmpty {
            request.setValue(saved.hasPrefix("Bearer ") ? saved : "Bearer \(saved)", forHTTPHeaderField: "Authorization")
        }

        let trailingActivation = UserDefaults.standard.double(forKey: "v22TrailingActivationPips")
        let effectiveTrailingActivation = trailingActivation > 0 ? trailingActivation : 5.0
        let body: [String: Any] = [
            "tp1_pips": config.partialTP1_Pips,
            "tp1_percent": config.partialTP1_Percent,
            "tp2_pips": config.partialTP2_Pips,
            "tp2_percent": config.partialTP2_Percent,
            "tp3_pips": config.partialTP3_Pips,
            "tp3_percent": config.partialTP3_Percent,
            "trailing_activation_pips": effectiveTrailingActivation
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                godLog("⚠️ PROTECTION SETTINGS | MT5 sync failed | HTTP=\((response as? HTTPURLResponse)?.statusCode ?? -1)", level: .warning)
                return
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            godLog("🛡️ PROTECTION SETTINGS APPLIED | TP1=\(config.partialTP1_Pips)p/\(Int(config.partialTP1_Percent * 100))% | TP2=\(config.partialTP2_Pips)p/\(Int(config.partialTP2_Percent * 100))% | TP3=\(config.partialTP3_Pips)p/\(Int(config.partialTP3_Percent * 100))% | trail=\(effectiveTrailingActivation)p | response=\(raw.prefix(180))", level: .success)
        } catch {
            godLog("⚠️ PROTECTION SETTINGS | MT5 sync error: \(error.localizedDescription)", level: .warning)
        }
    }
}
