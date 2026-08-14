import Foundation

/// Structured signal-evaluation telemetry. This is intentionally observational:
/// it does not change trade authority or scoring.
struct SignalEvaluationAudit {
    let symbol: String
    let direction: String
    let rawConfidence: Double
    let historicalAdjustment: Double
    let finalConfidence: Double
    let threshold: Double
    let riskRewardPassed: Bool
    let decision: String
    let passedPillars: [(name: String, contribution: Double)]
    let failedPillars: [(name: String, reason: String)]

    func emit() {
        guard SignalAuditSettings.shared.enabled else { return }

        let detailLevel = SignalAuditSettings.shared.detailLevel
        let passed = passedPillars.map { "\($0.name)=+\(String(format: "%.1f", $0.contribution))" }.joined(separator: " | ")
        let failed = failedPillars.map { "\($0.name): \($0.reason)" }.joined(separator: " | ")

        if detailLevel >= 1 {
            godLog("🧾 SIGNAL CALC | \(symbol) | PILLARS PASS [\(passed.isEmpty ? "none" : passed)] | FAIL [\(failed.isEmpty ? "none" : failed)]", level: .info)
        }

        godLog("🧮 SIGNAL CALC | \(symbol) | Direction=\(direction) | Raw=\(String(format: "%.1f", rawConfidence))% → Historical=\(historicalAdjustment >= 0 ? "+" : "")\(String(format: "%.1f", historicalAdjustment)) → Final=\(String(format: "%.1f", finalConfidence))% | Threshold=\(String(format: "%.1f", threshold))% | R:R=\(riskRewardPassed ? "PASS" : "FAIL") | Decision=\(decision)", level: .info)
    }
}

/// Runtime-adjustable audit verbosity. Stored in UserDefaults so it survives relaunches.
/// These settings are deliberately separate from trading weights and do not authorize trades.
final class SignalAuditSettings {
    static let shared = SignalAuditSettings()
    private init() {}

    private let defaults = UserDefaults.standard
    private let enabledKey = "signalAudit.enabled"
    private let detailKey = "signalAudit.detailLevel"

    var enabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// 0 = summary only, 1 = summary + pillar PASS/FAIL, 2 = reserved for future full trace.
    var detailLevel: Int {
        get { defaults.object(forKey: detailKey) as? Int ?? 1 }
        set { defaults.set(max(0, min(2, newValue)), forKey: detailKey) }
    }

    func logSettings() {
        godLog("⚙️ SIGNAL AUDIT SETTINGS | enabled=\(enabled) | detailLevel=\(detailLevel)", level: .info)
    }
}
