import Foundation
import SwiftUI
import Combine

@MainActor
final class V22TrailingActivationController: ObservableObject {
    @Published var activationPips: Double
    @Published private(set) var syncStatus: String = "Not synced"
    private let defaultsKey = "v22TrailingActivationPips"

    init() {
        let saved = UserDefaults.standard.double(forKey: defaultsKey)
        activationPips = saved > 0 ? min(50, max(1, saved)) : 5.0
    }

    func save() {
        activationPips = min(50, max(1, activationPips))
        UserDefaults.standard.set(activationPips, forKey: defaultsKey)
        Task { @MainActor in
            do {
                let value = try await MT5V22TrailingSettingsService.shared.setActivationPips(activationPips)
                syncStatus = String(format: "MT5 V22 synced • %.1f pips", value)
                godLog(String(format: "🛡️ V22 TRAILING | activation saved=%.1f pips | hard SL/curve unchanged", value), level: .success)
            } catch {
                syncStatus = "Saved locally • MT5 sync pending"
                godLog("⚠️ V22 TRAILING | local setting saved but MT5 sync failed: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    func refreshFromMT5() {
        Task { @MainActor in
            do {
                let value = try await MT5V22TrailingSettingsService.shared.getActivationPips()
                activationPips = value
                UserDefaults.standard.set(value, forKey: defaultsKey)
                syncStatus = String(format: "MT5 V22 synced • %.1f pips", value)
            } catch {
                syncStatus = "MT5 unavailable"
            }
        }
    }
}

struct V22TrailingActivationSettingsCard: View {
    @ObservedObject var controller: V22TrailingActivationController
    @StateObject private var accuracyController = SignalAccuracySettingsController()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "arrow.up.right.circle.fill").foregroundColor(.accentCyan)
                    Text("V22 TRAILING STOP").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                    Spacer()
                    Text(controller.syncStatus).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.textMuted)
                }
                Text("Adjusts only when trailing activates. Hard/structural/ATR SL remains unchanged. The EA moves SL forward only and still enforces broker stop/freeze validation.")
                    .font(.system(size: 10)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text("Activation").font(.system(size: 12)).foregroundColor(.textSecondary)
                    Slider(value: $controller.activationPips, in: 1...50, step: 0.5)
                    Text(String(format: "%.1f pips", controller.activationPips)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 75, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text("Fixed curve").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan)
                    Text("5–10: 3 • 10–15: 4.5 • 15–25: 6 • 25–40: 8 • 40–80: 10 • 80+: 12 pips")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.textMuted).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Button("SAVE & SYNC") { controller.save() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.bgPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Color.accentCyan).cornerRadius(6).buttonStyle(.plain)
                    Button("REFRESH FROM MT5") { controller.refreshFromMT5() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Color.accentCyan.opacity(0.10)).cornerRadius(6).buttonStyle(.plain)
                }

                Divider().background(Color.borderSubtle)
                HStack {
                    Image(systemName: "brain.head.profile").foregroundColor(.accentPurple)
                    Text("SIGNAL ACCURACY / BAYESIAN").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                    Spacer()
                    Button("RESET") { accuracyController.values = SignalAccuracyConfiguration(); accuracyController.save() }
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textMuted).buttonStyle(.plain)
                }
                Text("These values control the Phase 1–4 accuracy layer. Saved values are read by the engine on the next signal assessment; ML remains informational and non-blocking.")
                    .font(.system(size: 9)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)

                accuracySlider("Min history candles", value: Binding(get: { Double(accuracyController.values.minimumHistoryCandles) }, set: { accuracyController.values.minimumHistoryCandles = Int($0.rounded()) }), range: 20...200, step: 1, suffix: "")
                accuracySlider("Chop warning", value: $accuracyController.values.choppinessWarningThreshold, range: 40...80, step: 0.5, suffix: "")
                accuracySlider("Chop veto", value: $accuracyController.values.choppinessVetoThreshold, range: 45...90, step: 0.5, suffix: "")
                accuracySlider("Hurst mean-reversion", value: $accuracyController.values.hurstMeanReversionThreshold, range: 0.20...0.55, step: 0.01, suffix: "")
                accuracySlider("Hurst trending", value: $accuracyController.values.hurstTrendingThreshold, range: 0.50...0.80, step: 0.01, suffix: "")
                accuracySlider("Trend regime adjustment", value: $accuracyController.values.trendingRegimeAdjustment, range: -10...10, step: 0.5, suffix: "")
                accuracySlider("Mean-reversion adjustment", value: $accuracyController.values.meanReversionRegimeAdjustment, range: -10...10, step: 0.5, suffix: "")
                accuracySlider("Divergence lookback", value: Binding(get: { Double(accuracyController.values.divergenceLookback) }, set: { accuracyController.values.divergenceLookback = Int($0.rounded()) }), range: 20...100, step: 1, suffix: "")
                accuracySlider("Supporting divergence", value: $accuracyController.values.supportingDivergenceAdjustment, range: -20...20, step: 0.5, suffix: "")
                accuracySlider("Opposing divergence", value: $accuracyController.values.opposingDivergenceAdjustment, range: -30...0, step: 0.5, suffix: "")
                accuracySlider("Confirmed reversal", value: $accuracyController.values.reversalConfirmedAdjustment, range: -10...20, step: 0.5, suffix: "")
                accuracySlider("Waiting penalty (trend)", value: $accuracyController.values.reversalWaitingTrendPenalty, range: -15...0, step: 0.5, suffix: "")
                accuracySlider("Waiting penalty (other)", value: $accuracyController.values.reversalWaitingOtherPenalty, range: -20...0, step: 0.5, suffix: "")
                accuracySlider("Favorable session multiplier", value: $accuracyController.values.favorableSessionMultiplier, range: 0.80...1.30, step: 0.01, suffix: "x")
                accuracySlider("Reduced session multiplier", value: $accuracyController.values.reducedSessionMultiplier, range: 0.70...1.10, step: 0.01, suffix: "x")
                accuracySlider("Bayesian adjustment scale", value: $accuracyController.values.bayesianAdjustmentScale, range: 0...20, step: 0.5, suffix: "")
                accuracySlider("Bayesian prior wins", value: $accuracyController.values.bayesianPriorWins, range: 0.1...10, step: 0.1, suffix: "")
                accuracySlider("Bayesian prior losses", value: $accuracyController.values.bayesianPriorLosses, range: 0.1...10, step: 0.1, suffix: "")

                HStack(spacing: 8) {
                    Button("SAVE ACCURACY SETTINGS") { accuracyController.save() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.bgPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Color.accentPurple).cornerRadius(6).buttonStyle(.plain)
                    Button("RELOAD") { accuracyController.reload() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentPurple)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Color.accentPurple.opacity(0.10)).cornerRadius(6).buttonStyle(.plain)
                }
            }.padding(16)
        }
    }

    @ViewBuilder private func accuracySlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 10)).foregroundColor(.textSecondary).lineLimit(1).minimumScaleFactor(0.75)
            Slider(value: value, in: range, step: step)
            Text(String(format: suffix == "x" ? "%.2fx" : "%.1f\(suffix)", value.wrappedValue))
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 62, alignment: .trailing)
        }
    }
}

actor MT5V22TrailingSettingsService {
    nonisolated static let shared = MT5V22TrailingSettingsService()
    private let session = URLSession(configuration: .default)

    private func bridgeBaseURL() async -> String {
        await MainActor.run {
            var raw = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
            if raw.hasSuffix("/") { raw.removeLast() }
            return raw
        }
    }

    private func authToken() async -> String {
        await MainActor.run {
            let saved = SecureCredentialStore.shared.read("mt5AuthToken") ?? ""
            return saved.isEmpty ? "" : (saved.hasPrefix("Bearer ") ? saved : "Bearer \(saved)")
        }
    }

    func setActivationPips(_ pips: Double) async throws -> Double {
        try await request(method: "POST", pips: min(100, max(1, pips)))
    }

    func getActivationPips() async throws -> Double {
        try await request(method: "GET", pips: nil)
    }

    private func request(method: String, pips: Double?) async throws -> Double {
        let baseURL = await bridgeBaseURL()
        guard let url = URL(string: baseURL + "/v1/settings/trailing") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = await authToken()
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Authorization") }
        if let pips {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["trailing_activation_pips": pips])
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawValue = json["trailing_activation_pips"],
              let value = (rawValue as? Double) ?? (rawValue as? NSNumber)?.doubleValue else { throw URLError(.cannotParseResponse) }
        return min(100, max(1, value))
    }
}
