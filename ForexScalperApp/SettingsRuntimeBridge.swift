import Foundation
import Combine

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
        let trailingActivation = UserDefaults.standard.double(forKey: "v22TrailingActivationPips")
        let protection = MT5ProtectionSettings(
            tp1Pips: config.partialTP1_Pips,
            tp1Percent: config.partialTP1_Percent,
            tp2Pips: config.partialTP2_Pips,
            tp2Percent: config.partialTP2_Percent,
            tp3Pips: config.partialTP3_Pips,
            tp3Percent: config.partialTP3_Percent,
            trailingActivationPips: trailingActivation > 0 ? trailingActivation : 5.0
        )
        Task { await MT5ProtectionSettingsSync.shared.sync(settings: protection) }
    }
}

struct MT5ProtectionSettings: Sendable {
    let tp1Pips: Double
    let tp1Percent: Double
    let tp2Pips: Double
    let tp2Percent: Double
    let tp3Pips: Double
    let tp3Percent: Double
    let trailingActivationPips: Double
}

actor MT5ProtectionSettingsSync {
    static let shared = MT5ProtectionSettingsSync()

    func sync(settings: MT5ProtectionSettings) async {
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

        let body: [String: Any] = [
            "tp1_pips": settings.tp1Pips,
            "tp1_percent": settings.tp1Percent,
            "tp2_pips": settings.tp2Pips,
            "tp2_percent": settings.tp2Percent,
            "tp3_pips": settings.tp3Pips,
            "tp3_percent": settings.tp3Percent,
            "trailing_activation_pips": settings.trailingActivationPips
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                godLog("⚠️ PROTECTION SETTINGS | MT5 sync failed | HTTP=\((response as? HTTPURLResponse)?.statusCode ?? -1)", level: .warning)
                return
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            godLog("🛡️ PROTECTION SETTINGS APPLIED | TP1=\(settings.tp1Pips)p/\(Int(settings.tp1Percent * 100))% | TP2=\(settings.tp2Pips)p/\(Int(settings.tp2Percent * 100))% | TP3=\(settings.tp3Pips)p/\(Int(settings.tp3Percent * 100))% | trail=\(settings.trailingActivationPips)p | response=\(raw.prefix(180))", level: .success)
        } catch {
            godLog("⚠️ PROTECTION SETTINGS | MT5 sync error: \(error.localizedDescription)", level: .warning)
        }
    }
}
