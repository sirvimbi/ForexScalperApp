import Foundation

/// Non-ML signal-quality intelligence used to diagnose and improve signal generation.
/// The service is deliberately deterministic and non-blocking: it can veto poor market
/// conditions only when explicitly requested by the caller and otherwise returns context.
struct SignalAccuracySnapshot: Sendable {
    enum Regime: String, Sendable { case trending, meanReverting, choppy, transitional, unknown }
    let hurst: Double
    let choppiness: Double
    let regime: Regime
    let bullishDivergence: Bool
    let bearishDivergence: Bool
    let spreadShock: Bool
    let sessionMultiplier: Double
    let confirmationScore: Double
    let notes: [String]

    var isChoppy: Bool { choppiness >= 61.8 }
    var isTrending: Bool { hurst >= 0.60 && choppiness < 55.0 }
}

struct SignalAccuracyIntelligence {
    private init() {}

    static func analyze(candles: [Kline], signal: SignalType? = nil, spreadHistoryPips: [Double] = []) -> SignalAccuracySnapshot {
        let closes = candles.map(\.close)
        let hurst = hurstExponent(closes)
        let chop = choppinessIndex(candles)
        let regime: SignalAccuracySnapshot.Regime
        if chop >= 61.8 { regime = .choppy }
        else if hurst >= 0.60 && chop < 55 { regime = .trending }
        else if hurst <= 0.45 { regime = .meanReverting }
        else { regime = .transitional }

        let div = divergence(candles: candles)
        let spreadShock = spreadHistoryPips.count >= 4 && {
            guard let latest = spreadHistoryPips.last else { return false }
            let baseline = Array(spreadHistoryPips.dropLast()).reduce(0, +) / Double(spreadHistoryPips.count - 1)
            return baseline > 0 && latest > baseline * 1.30
        }()

        let hour = Calendar.current.component(.hour, from: Date())
        let sessionMultiplier: Double
        switch hour {
        case 7...10, 13...16: sessionMultiplier = 1.10
        case 0...5: sessionMultiplier = 0.90
        case 20...23: sessionMultiplier = 0.92
        default: sessionMultiplier = 1.0
        }

        var score = 0.0
        var notes: [String] = []
        if regime == .trending { score += 0.25; notes.append("trend regime") }
        if regime == .meanReverting { score += 0.10; notes.append("mean-reversion regime") }
        if regime == .choppy { score -= 0.45; notes.append("high choppiness") }
        if div.bullish { score += 0.20; notes.append("bullish RSI/price divergence") }
        if div.bearish { score -= 0.20; notes.append("bearish RSI/price divergence") }
        if spreadShock { score -= 0.30; notes.append("spread expansion") }
        score *= sessionMultiplier
        if let signal {
            if signal == .buy && div.bearish { score -= 0.35; notes.append("BUY conflicts with bearish divergence") }
            if signal == .sell && div.bullish { score -= 0.35; notes.append("SELL conflicts with bullish divergence") }
        }
        return SignalAccuracySnapshot(hurst: hurst, choppiness: chop, regime: regime,
                                      bullishDivergence: div.bullish, bearishDivergence: div.bearish,
                                      spreadShock: spreadShock, sessionMultiplier: sessionMultiplier,
                                      confirmationScore: max(-1, min(1, score)), notes: notes)
    }

    /// Rescaled-range Hurst estimate. Values above .60 favour trend continuation;
    /// values below .45 favour mean reversion; the middle is treated as transitional.
    static func hurstExponent(_ prices: [Double]) -> Double {
        guard prices.count >= 32 else { return 0.5 }
        let maxLag = min(prices.count / 4, 64)
        var xs: [Double] = [], ys: [Double] = []
        for lag in 8...maxLag {
            var rs: [Double] = []
            var start = 0
            while start + lag <= prices.count {
                let segment = Array(prices[start..<(start + lag)])
                let mean = segment.reduce(0, +) / Double(lag)
                var running = 0.0, minRun = 0.0, maxRun = 0.0, variance = 0.0
                for value in segment {
                    let d = value - mean
                    variance += d * d
                    running += d
                    minRun = min(minRun, running)
                    maxRun = max(maxRun, running)
                }
                let std = sqrt(variance / Double(lag))
                if std > 0 && maxRun > minRun { rs.append((maxRun - minRun) / std) }
                start += lag
            }
            if !rs.isEmpty {
                xs.append(log(Double(lag)))
                ys.append(log(rs.reduce(0, +) / Double(rs.count)))
            }
        }
        guard xs.count >= 3 else { return 0.5 }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let denom = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard denom > 0 else { return 0.5 }
        return max(0, min(1, xs.indices.reduce(0) { $0 + (xs[$1] - mx) * (ys[$1] - my) } / denom))
    }

    static func choppinessIndex(_ candles: [Kline], period: Int = 14) -> Double {
        guard candles.count >= period + 1 else { return 50 }
        let slice = Array(candles.suffix(period + 1))
        var atrSum = 0.0
        for i in 1..<slice.count {
            let c = slice[i], p = slice[i - 1]
            atrSum += max(c.high - c.low, max(abs(c.high - p.close), abs(c.low - p.close)))
        }
        let highest = slice.map(\.high).max() ?? 0
        let lowest = slice.map(\.low).min() ?? 0
        let range = highest - lowest
        guard range > 0, atrSum > 0 else { return 100 }
        return max(0, min(100, 100 * log10(atrSum / range) / log10(Double(period))))
    }

    static func divergence(candles: [Kline], lookback: Int = 24) -> (bullish: Bool, bearish: Bool) {
        guard candles.count >= lookback + 5 else { return (false, false) }
        let slice = Array(candles.suffix(lookback))
        let closes = slice.map(\.close)
        let rsi = rsiSeries(closes, period: 14)
        guard rsi.count == closes.count else { return (false, false) }
        let mid = closes.count / 2
        let first = 0..<mid, second = mid..<closes.count
        let firstLow = first.min { closes[$0] < closes[$1] } ?? 0
        let secondLow = second.min { closes[$0] < closes[$1] } ?? mid
        let firstHigh = first.max { closes[$0] < closes[$1] } ?? 0
        let secondHigh = second.max { closes[$0] < closes[$1] } ?? mid
        let bullish = closes[secondLow] < closes[firstLow] && rsi[secondLow] > rsi[firstLow] + 2
        let bearish = closes[secondHigh] > closes[firstHigh] && rsi[secondHigh] < rsi[firstHigh] - 2
        return (bullish, bearish)
    }

    private static func rsiSeries(_ values: [Double], period: Int) -> [Double] {
        guard values.count > period else { return [] }
        var gains = 0.0, losses = 0.0
        for i in 1...period { let d = values[i] - values[i - 1]; gains += max(0, d); losses += max(0, -d) }
        var result = Array(repeating: 50.0, count: values.count)
        func rsi(_ g: Double, _ l: Double) -> Double { l == 0 ? 100 : 100 - 100 / (1 + g / l) }
        gains /= Double(period); losses /= Double(period); result[period] = rsi(gains, losses)
        if period + 1 < values.count {
            for i in (period + 1)..<values.count {
                let d = values[i] - values[i - 1]
                gains = (gains * Double(period - 1) + max(0, d)) / Double(period)
                losses = (losses * Double(period - 1) + max(0, -d)) / Double(period)
                result[i] = rsi(gains, losses)
            }
        }
        return result
    }
}

/// Bayesian-style online pillar calibration. This never replaces the strategy's
/// configured weights; it produces bounded multipliers for diagnostics/adaptation.
actor AdaptivePillarLearner {
    struct Posterior: Sendable { var wins: Double; var losses: Double }
    private var posteriors: [String: Posterior] = [:]

    func record(pillar: String, won: Bool) {
        var p = posteriors[pillar] ?? Posterior(wins: 1, losses: 1)
        if won { p.wins += 1 } else { p.losses += 1 }
        posteriors[pillar] = p
    }

    func multiplier(for pillar: String) -> Double {
        let p = posteriors[pillar] ?? Posterior(wins: 1, losses: 1)
        let winRate = p.wins / (p.wins + p.losses)
        return max(0.50, min(1.75, 0.75 + winRate))
    }

    func snapshot() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: posteriors.keys.map { ($0, multiplier(for: $0)) })
    }
}

/// Phase 3 entry-turn detector. It waits for a directional reversal instead of
/// entering blindly while the market is still moving against the signal.
struct MicroReversalConfirmation {
    static func confirmed(signal: SignalType, candles: [Kline], atr: Double) -> Bool {
        guard candles.count >= 6, atr > 0 else { return false }
        let recent = Array(candles.suffix(6))
        let prev = recent[recent.count - 2], last = recent[recent.count - 1]
        let body = last.close - last.open
        let threshold = max(atr * 0.08, atr / 20)
        switch signal {
        case .buy:
            let higherLow = last.low >= prev.low - atr * 0.05
            let reclaim = last.close > prev.high || body > threshold
            return higherLow && reclaim
        case .sell:
            let lowerHigh = last.high <= prev.high + atr * 0.05
            let rejection = last.close < prev.low || body < -threshold
            return lowerHigh && rejection
        default: return false
        }
    }
}
