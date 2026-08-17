import Foundation
import SwiftUI
import Combine

@MainActor
final class PositionManagementController: ObservableObject {
    static let shared = PositionManagementController()

    @Published var breakevenEnabled: Bool
    @Published var breakevenTriggerPips: Double
    @Published var breakevenOffsetPips: Double
    @Published var trailingEnabled: Bool
    @Published var trailingActivationPips: Double
    @Published var trailingDistancePips: Double
    @Published var trailingStepPips: Double
    @Published private(set) var syncStatus: String = "Not synced"

    private let defaults = UserDefaults.standard
    private let prefix = "productionPositionManagement."

    private init() {
        breakevenEnabled = defaults.object(forKey: prefix + "breakevenEnabled") as? Bool ?? true
        breakevenTriggerPips = defaults.object(forKey: prefix + "breakevenTriggerPips") as? Double ?? 10.0
        breakevenOffsetPips = defaults.object(forKey: prefix + "breakevenOffsetPips") as? Double ?? 0.0
        trailingEnabled = defaults.object(forKey: prefix + "trailingEnabled") as? Bool ?? true
        trailingActivationPips = defaults.object(forKey: prefix + "trailingActivationPips") as? Double ?? 5.0
        trailingDistancePips = defaults.object(forKey: prefix + "trailingDistancePips") as? Double ?? 6.0
        trailingStepPips = defaults.object(forKey: prefix + "trailingStepPips") as? Double ?? 1.0
    }

    func saveAndSync() {
        persistLocalSettings()
        Task { await syncFromAppSettings() }
    }

    func syncFromAppSettings() async {
        let config = ScalpingConfig.shared
        let payload = PositionManagementPayload(
            tp1Percent: config.partialTP1_Percent,
            tp1Pips: config.partialTP1_Pips,
            tp2Percent: config.partialTP2_Percent,
            tp2Pips: config.partialTP2_Pips,
            tp3Percent: config.partialTP3_Percent,
            tp3Pips: config.partialTP3_Pips,
            breakevenEnabled: breakevenEnabled,
            breakevenTriggerPips: breakevenTriggerPips,
            breakevenOffsetPips: breakevenOffsetPips,
            trailingEnabled: trailingEnabled,
            trailingActivationPips: trailingActivationPips,
            trailingDistancePips: trailingDistancePips,
            trailingStepPips: trailingStepPips
        )

        do {
            let result = try await MT5PositionManagementSettingsService.shared.sync(payload)
            syncStatus = result.configReady ? "MT5 synced" : "MT5 connected • configuration not ready"
            godLog("🛡️ POSITION MANAGEMENT SYNC | TP=\(String(format: "%.0f/%.0f/%.0f%%", payload.tp1Percent * 100, payload.tp2Percent * 100, payload.tp3Percent * 100)) | BE=\(payload.breakevenEnabled ? "ON" : "OFF") @ \(String(format: "%.1f", payload.breakevenTriggerPips)) | TRAIL=\(payload.trailingEnabled ? "ON" : "OFF") @ \(String(format: "%.1f/%.1f/%.1f", payload.trailingActivationPips, payload.trailingDistancePips, payload.trailingStepPips))", level: .success)
        } catch {
            syncStatus = "MT5 sync pending"
            godLog("⚠️ POSITION MANAGEMENT SYNC | MT5 sync failed: \(error.localizedDescription)", level: .warning)
        }
    }

    func refreshFromMT5() {
        Task {
            do {
                let remote = try await MT5PositionManagementSettingsService.shared.get()
                breakevenEnabled = remote.breakevenEnabled
                breakevenTriggerPips = remote.breakevenTriggerPips
                breakevenOffsetPips = remote.breakevenOffsetPips
                trailingEnabled = remote.trailingEnabled
                trailingActivationPips = remote.trailingActivationPips
                trailingDistancePips = remote.trailingDistancePips
                trailingStepPips = remote.trailingStepPips
                persistLocalSettings()
                syncStatus = remote.configReady ? "MT5 synced" : "MT5 configuration not ready"
            } catch {
                syncStatus = "MT5 unavailable"
            }
        }
    }

    private func persistLocalSettings() {
        defaults.set(breakevenEnabled, forKey: prefix + "breakevenEnabled")
        defaults.set(breakevenTriggerPips, forKey: prefix + "breakevenTriggerPips")
        defaults.set(breakevenOffsetPips, forKey: prefix + "breakevenOffsetPips")
        defaults.set(trailingEnabled, forKey: prefix + "trailingEnabled")
        defaults.set(trailingActivationPips, forKey: prefix + "trailingActivationPips")
        defaults.set(trailingDistancePips, forKey: prefix + "trailingDistancePips")
        defaults.set(trailingStepPips, forKey: prefix + "trailingStepPips")
    }
}

private struct PositionManagementPayload: Codable {
    let tp1Percent: Double
    let tp1Pips: Double
    let tp2Percent: Double
    let tp2Pips: Double
    let tp3Percent: Double
    let tp3Pips: Double
    let breakevenEnabled: Bool
    let breakevenTriggerPips: Double
    let breakevenOffsetPips: Double
    let trailingEnabled: Bool
    let trailingActivationPips: Double
    let trailingDistancePips: Double
    let trailingStepPips: Double

    enum CodingKeys: String, CodingKey {
        case tp1Percent = "tp1_percent", tp1Pips = "tp1_pips"
        case tp2Percent = "tp2_percent", tp2Pips = "tp2_pips"
        case tp3Percent = "tp3_percent", tp3Pips = "tp3_pips"
        case breakevenEnabled = "breakeven_enabled"
        case breakevenTriggerPips = "breakeven_trigger_pips"
        case breakevenOffsetPips = "breakeven_offset_pips"
        case trailingEnabled = "trailing_enabled"
        case trailingActivationPips = "trailing_activation_pips"
        case trailingDistancePips = "trailing_distance_pips"
        case trailingStepPips = "trailing_step_pips"
    }
}

private struct PositionManagementRemote: Codable {
    let success: Bool
    let configReady: Bool
    let breakevenEnabled: Bool
    let breakevenTriggerPips: Double
    let breakevenOffsetPips: Double
    let trailingEnabled: Bool
    let trailingActivationPips: Double
    let trailingDistancePips: Double
    let trailingStepPips: Double

    enum CodingKeys: String, CodingKey {
        case success, configReady = "config_ready"
        case breakevenEnabled = "breakeven_enabled"
        case breakevenTriggerPips = "breakeven_trigger_pips"
        case breakevenOffsetPips = "breakeven_offset_pips"
        case trailingEnabled = "trailing_enabled"
        case trailingActivationPips = "trailing_activation_pips"
        case trailingDistancePips = "trailing_distance_pips"
        case trailingStepPips = "trailing_step_pips"
    }
}

actor MT5PositionManagementSettingsService {
    nonisolated static let shared = MT5PositionManagementSettingsService()
    private let session = URLSession(configuration: .default)

    private func baseURL() async -> String {
        await MainActor.run {
            var value = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
            if value.hasSuffix("/") { value.removeLast() }
            return value
        }
    }

    private func authToken() async -> String {
        await MainActor.run {
            let saved = SecureCredentialStore.shared.read("mt5AuthToken") ?? ""
            guard !saved.isEmpty else { return "" }
            return saved.hasPrefix("Bearer ") ? saved : "Bearer \(saved)"
        }
    }

    func sync(_ payload: PositionManagementPayload) async throws -> PositionManagementRemote {
        let base = await baseURL()
        guard let url = URL(string: base + "/v1/settings/position-management") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = await authToken()
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let result = try JSONDecoder().decode(PositionManagementRemote.self, from: data)
        guard result.success else { throw URLError(.cannotParseResponse) }
        return result
    }

    func get() async throws -> PositionManagementRemote {
        let base = await baseURL()
        guard let url = URL(string: base + "/v1/settings/position-management") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = await authToken()
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let result = try JSONDecoder().decode(PositionManagementRemote.self, from: data)
        guard result.success else { throw URLError(.cannotParseResponse) }
        return result
    }
}

struct PositionManagementSettingsCard: View {
    @ObservedObject var controller: PositionManagementController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PRODUCTION POSITION MANAGEMENT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text(controller.syncStatus)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text("TP percentages/distances use the existing Scalping settings. These controls configure broker-side breakeven and forward-only trailing protection.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Enable Breakeven", isOn: $controller.breakevenEnabled)
            HStack { Text("Breakeven trigger"); Slider(value: $controller.breakevenTriggerPips, in: 0...50, step: 0.5); Text(String(format: "%.1f", controller.breakevenTriggerPips)).monospacedDigit() }
            HStack { Text("Breakeven offset"); Slider(value: $controller.breakevenOffsetPips, in: -2...5, step: 0.1); Text(String(format: "%.1f", controller.breakevenOffsetPips)).monospacedDigit() }
            Divider()
            Toggle("Enable Trailing", isOn: $controller.trailingEnabled)
            HStack { Text("Activation"); Slider(value: $controller.trailingActivationPips, in: 0...100, step: 0.5); Text(String(format: "%.1f", controller.trailingActivationPips)).monospacedDigit() }
            HStack { Text("Distance"); Slider(value: $controller.trailingDistancePips, in: 0.5...100, step: 0.5); Text(String(format: "%.1f", controller.trailingDistancePips)).monospacedDigit() }
            HStack { Text("Step"); Slider(value: $controller.trailingStepPips, in: 0...20, step: 0.5); Text(String(format: "%.1f", controller.trailingStepPips)).monospacedDigit() }
            HStack {
                Button("SAVE & SYNC") { controller.saveAndSync() }
                    .buttonStyle(.borderedProminent)
                Button("REFRESH MT5") { controller.refreshFromMT5() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }
}
