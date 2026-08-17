import Foundation
import Combine

@MainActor
final class V23PositionManagementSettingsBridge {
    static let shared = V23PositionManagementSettingsBridge()

    private var observation: AnyCancellable?
    private var syncTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard observation == nil else { return }
        observation = ScalpingConfig.shared.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSync(reason: "settings changed")
            }
        scheduleSync(reason: "startup")
    }

    func syncNow() {
        scheduleSync(reason: "manual")
    }

    private func scheduleSync(reason: String) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let values = await MainActor.run { self.currentValues() }
                let response = try await MT5V23PositionManagementService.shared.sync(values)
                godLog("🛡️ V23 POSITION SETTINGS | synced | reason=\(reason) | TP1=\(String(format: "%.1f%%/%.1f", values.tp1Percent * 100, values.tp1Pips)) | TP2=\(String(format: "%.1f%%/%.1f", values.tp2Percent * 100, values.tp2Pips)) | TP3=\(String(format: "%.1f%%/%.1f", values.tp3Percent * 100, values.tp3Pips)) | trail=\(String(format: "%.1f", values.trailingActivationPips))", level: .success)
                _ = response
            } catch {
                godLog("⚠️ V23 POSITION SETTINGS | sync pending | reason=\(reason) | \(error.localizedDescription)", level: .warning)
            }
        }
    }

    struct Values: Sendable {
        let tp1Percent: Double
        let tp1Pips: Double
        let tp2Percent: Double
        let tp2Pips: Double
        let tp3Percent: Double
        let tp3Pips: Double
        let trailingActivationPips: Double
        let breakevenLockPips: Double
        let minimumTrailStepPips: Double
        let atrPeriod: Int
        let atrBaselinePips: Double
        let atrMaxMultiplier: Double
        let trail5to10Pips: Double
        let trail10to15Pips: Double
        let trail15to25Pips: Double
        let trail25to40Pips: Double
        let trail40to80Pips: Double
        let trail80PlusPips: Double
        let deviationPoints: Int
    }

    private func currentValues() -> Values {
        let config = ScalpingConfig.shared
        let activation = UserDefaults.standard.double(forKey: "v22TrailingActivationPips")
        return Values(
            tp1Percent: min(1, max(0, config.partialTP1_Percent)),
            tp1Pips: max(0, config.partialTP1_Pips),
            tp2Percent: min(1, max(0, config.partialTP2_Percent)),
            tp2Pips: max(0, config.partialTP2_Pips),
            tp3Percent: min(1, max(0, config.partialTP3_Percent)),
            tp3Pips: max(0, config.partialTP3_Pips),
            trailingActivationPips: activation > 0 ? min(1000, max(0, activation)) : 5.0,
            breakevenLockPips: max(0, UserDefaults.standard.object(forKey: "v23BreakevenLockPips") as? Double ?? 0.5),
            minimumTrailStepPips: max(0, UserDefaults.standard.object(forKey: "v23MinimumTrailStepPips") as? Double ?? 1.0),
            atrPeriod: max(2, UserDefaults.standard.object(forKey: "v23ATRPeriod") as? Int ?? 14),
            atrBaselinePips: max(0.1, UserDefaults.standard.object(forKey: "v23ATRBaselinePips") as? Double ?? 5.0),
            atrMaxMultiplier: max(1, UserDefaults.standard.object(forKey: "v23ATRMaxMultiplier") as? Double ?? 1.5),
            trail5to10Pips: max(0.1, UserDefaults.standard.object(forKey: "v23Trail5to10Pips") as? Double ?? 3.0),
            trail10to15Pips: max(0.1, UserDefaults.standard.object(forKey: "v23Trail10to15Pips") as? Double ?? 4.5),
            trail15to25Pips: max(0.1, UserDefaults.standard.object(forKey: "v23Trail15to25Pips") as? Double ?? 6.0),
            trail25to40Pips: max(0.1, UserDefaults.standard.object(forKey: "v23Trail25to40Pips") as? Double ?? 8.0),
            trail40to80Pips: max(0.1, UserDefaults.standard.object(forKey: "v23Trail40to80Pips") as? Double ?? 10.0),
            trail80PlusPips: max(0.1, UserDefaults.standard.object(forKey: "v23Trail80PlusPips") as? Double ?? 12.0),
            deviationPoints: max(0, UserDefaults.standard.object(forKey: "v23DeviationPoints") as? Int ?? 15)
        )
    }
}

actor MT5V23PositionManagementService {
    nonisolated static let shared = MT5V23PositionManagementService()
    private let session = URLSession(configuration: .default)

    func sync(_ values: V23PositionManagementSettingsBridge.Values) async throws -> [String: Any] {
        let base = await MainActor.run {
            var value = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
            if value.hasSuffix("/") { value.removeLast() }
            return value
        }
        guard let url = URL(string: base + "/v1/settings/position-management") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = await MainActor.run { SecureCredentialStore.shared.read("mt5AuthToken") ?? "" }
        if !token.isEmpty { request.setValue(token.hasPrefix("Bearer ") ? token : "Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "tp1_pips": values.tp1Pips,
            "tp1_percent": values.tp1Percent,
            "tp2_pips": values.tp2Pips,
            "tp2_percent": values.tp2Percent,
            "tp3_pips": values.tp3Pips,
            "tp3_percent": values.tp3Percent,
            "trailing_activation_pips": values.trailingActivationPips,
            "breakeven_lock_pips": values.breakevenLockPips,
            "minimum_trail_step_pips": values.minimumTrailStepPips,
            "atr_period": values.atrPeriod,
            "atr_baseline_pips": values.atrBaselinePips,
            "atr_max_multiplier": values.atrMaxMultiplier,
            "trail_5_10_pips": values.trail5to10Pips,
            "trail_10_15_pips": values.trail10to15Pips,
            "trail_15_25_pips": values.trail15to25Pips,
            "trail_25_40_pips": values.trail25to40Pips,
            "trail_40_80_pips": values.trail40to80Pips,
            "trail_80_plus_pips": values.trail80PlusPips,
            "deviation_points": values.deviationPoints
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], (json["success"] as? Bool) == true else { throw URLError(.cannotParseResponse) }
        return json
    }
}
