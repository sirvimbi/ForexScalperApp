import Foundation

/// Phase 4/5 walk-forward parameter research. It is intentionally offline and never
/// changes live settings by itself. The result can be surfaced in Insights for review.
struct SignalParameterCandidate: Sendable, Equatable {
    let choppinessCeiling: Double
    let hurstTrendFloor: Double
    let divergenceBuffer: Double
    let confirmationATRFraction: Double
    let score: Double
}

struct SignalParameterOptimizer {
    private init() {}

    static func rank(candidates: [SignalParameterCandidate], trades: [BacktestOutcome]) -> [SignalParameterCandidate] {
        guard !trades.isEmpty else { return candidates }
        return candidates.map { candidate in
            let filtered = trades.filter {
                $0.choppiness < candidate.choppinessCeiling &&
                ($0.hurst >= candidate.hurstTrendFloor || $0.regime == .meanReverting)
            }
            guard !filtered.isEmpty else { return SignalParameterCandidate(choppinessCeiling: candidate.choppinessCeiling,
                                                                              hurstTrendFloor: candidate.hurstTrendFloor,
                                                                              divergenceBuffer: candidate.divergenceBuffer,
                                                                              confirmationATRFraction: candidate.confirmationATRFraction,
                                                                              score: -.greatestFiniteMagnitude) }
            let pnl = filtered.reduce(0) { $0 + $1.pnl }
            let wins = filtered.filter { $0.pnl > 0 }.count
            let winRate = Double(wins) / Double(filtered.count)
            let avg = pnl / Double(filtered.count)
            let score = pnl + avg * 10 + (winRate - 0.5) * 100
            return SignalParameterCandidate(choppinessCeiling: candidate.choppinessCeiling,
                                            hurstTrendFloor: candidate.hurstTrendFloor,
                                            divergenceBuffer: candidate.divergenceBuffer,
                                            confirmationATRFraction: candidate.confirmationATRFraction,
                                            score: score)
        }.sorted { $0.score > $1.score }
    }
}

struct BacktestOutcome: Sendable {
    enum Regime: Sendable { case trending, meanReverting, choppy, transitional }
    let pnl: Double
    let choppiness: Double
    let hurst: Double
    let regime: Regime
}
