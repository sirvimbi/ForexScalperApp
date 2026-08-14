import Foundation
import SwiftUI

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
        Task {
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
        Task {
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

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .foregroundColor(.accentCyan)
                    Text("V22 TRAILING STOP")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(controller.syncStatus)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.textMuted)
                }

                Text("Adjusts only when trailing activates. Hard/structural/ATR SL remains unchanged. The EA moves SL forward only and still enforces broker stop/freeze validation.")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Text("Activation")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Slider(value: $controller.activationPips, in: 1...50, step: 0.5)
                    Text(String(format: "%.1f pips", controller.activationPips))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentGold)
                        .frame(width: 75, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("Fixed curve")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentCyan)
                    Text("5–10: 3 • 10–15: 4.5 • 15–25: 6 • 25–40: 8 • 40–80: 10 • 80+: 12 pips")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.textMuted)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button("SAVE & SYNC") { controller.save() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.bgPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.accentCyan)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    Button("REFRESH FROM MT5") { controller.refreshFromMT5() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentCyan)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.accentCyan.opacity(0.10))
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

actor MT5V22TrailingSettingsService {
    static let shared = MT5V22TrailingSettingsService()
    private let session = URLSession(configuration: .default)

    private var baseURL: String {
        var raw = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
        if raw.hasSuffix("/") { raw.removeLast() }
        return raw
    }

    private var authToken: String {
        let saved = SecureCredentialStore.shared.read("mt5AuthToken") ?? ""
        return saved.isEmpty ? "" : (saved.hasPrefix("Bearer ") ? saved : "Bearer \(saved)")
    }

    func setActivationPips(_ pips: Double) async throws -> Double {
        try await request(method: "POST", pips: min(100, max(1, pips)))
    }

    func getActivationPips() async throws -> Double {
        try await request(method: "GET", pips: nil)
    }

    private func request(method: String, pips: Double?) async throws -> Double {
        guard let url = URL(string: baseURL + "/v1/settings/trailing") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty { request.setValue(authToken, forHTTPHeaderField: "Authorization") }
        if let pips {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["trailing_activation_pips": pips])
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["trailing_activation_pips"] as? Double else { throw URLError(.cannotParseResponse) }
        return min(100, max(1, value))
    }
}
