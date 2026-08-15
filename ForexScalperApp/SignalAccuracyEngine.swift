import Foundation

/// Non-blocking/low-frequency signal quality layer used by the scalping engine.
/// It deliberately separates market-regime confirmation from the existing pillar score.
actor SignalAccuracyEngine {
    static let shared = SignalAccuracyEngine()

    struct Assessment: Sendable {
        let approved: Bool
        let confidenceAdjustment: Double
        let regime: String
        let choppiness: Double
        let hurst: Double
        let reasons: [String]

        var insight: String {
            let reasonText = reasons.isEmpty ? "No exceptional confirmation factors." : reasons.joined(separator: "; ")
            return "Accuracy layer | regime=\(regime) | H=\(String(format: \"%.2f\", hurst)) | chop=\(String(format: \"%.1f\", choppiness)) | \(reasonText)"
        }
    }

    private struct BayesianBucket: Codable {
        var wins: Double
        var losses: Double
    }

    private var calibration: [String: BayesianBucket] = [:]
    private let storageKey = "signal.accuracy.bayesian.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: BayesianBucket].self, from: data) {
            calibration = decoded
        }
    }

    /// Phase 1-3 assessment. A signal is only hard-vetoed for severe chop or a clear
    /// opposing divergence. Everything else adjusts confidence and supplies an Insight.
    func assess(symbol: String, direction: SignalType, candles: [Kline]) -> Assessment {
        guard candles.count >= 60, direction != .none else {
            return Assessment(approved: true, confidenceAdjustment: 0, regime: "unknown", choppiness: 50, hurst: 0.5, reasons: ["insufficient accuracy-layer history"])
        }

        let prices = candles.map(\.close)
        let hurst = hurstExponent(prices)
        let chop = choppinessIndex(candles, period: 14)
        let divergence = divergenceState(candles, direction: direction)
        let reversal = microReversalConfirmation(candles, direction: direction)
        let session = sessionMultiplier(for: Date())

        var adjustment = 0.0
        var reasons: [String] = []
        var approved = true

        let regime: String
        if chop >= 61.8 {
            regime = "choppy"
            adjustment -= 10
            reasons.append("high choppiness")
            if chop >= 68.0 { approved = false }
        } else if hurst >= 0.60 {
            regime = "trending"
            adjustment += 3
            reasons.append("persistent trend")
        } else if hurst <= 0.45 {
            regime = "mean-reverting"
            adjustment += 1
            reasons.append("mean-reversion regime")
        } else {
            regime = "transitional"
        }

        switch divergence {
        case .supporting:
            adjustment += 5
            reasons.append("directional RSI divergence")
        case .opposing:
            adjustment -= 15
            reasons.append("opposing RSI/price divergence")
            approved = false
        case .none:
            break
        }

        if reversal.confirmed {
            adjustment += 7
            reasons.append(reversal.reason)
        } else {
            adjustment -= regime == "trending" ? 3 : 6
            reasons.append(reversal.reason)
        }

        adjustment += (session - 1.0) * 5.0
        if session > 1.0 { reasons.append("session momentum favorable") }
        if session < 1.0 { reasons.append("session quality reduced") }

        // Phase 4: Bayesian calibration. This is deliberately a soft multiplier;
        // it cannot turn a good signal into a hard veto by itself.
        let key = "\(symbol.uppercased()):\(direction)"
        let bucket = calibration[key] ?? BayesianBucket(wins: 1, losses: 1)
        let posteriorWinRate = (bucket.wins + 1.0) / (bucket.wins + bucket.losses + 2.0)
        adjustment += (posteriorWinRate - 0.5) * 8.0
        reasons.append("Bayesian prior=\(Int(posteriorWinRate * 100))%")

        return Assessment(
            approved: approved,
            confidenceAdjustment: max(-20, min(12, adjustment)),
            regime: regime,
            choppiness: chop,
            hurst: hurst,
            reasons: reasons
        )
    }

    /// Called by the execution/history layer when a completed signal outcome is known.
    /// Positive/negative outcomes update a Beta posterior and persist across launches.
    func recordOutcome(symbol: String, direction: SignalType, profitable: Bool) {
        guard direction != .none else { return }
        let key = "\(symbol.uppercased()):\(direction)"
        var bucket = calibration[key] ?? BayesianBucket(wins: 1, losses: 1)
        if profitable { bucket.wins += 1 } else { bucket.losses += 1 }
        calibration[key] = bucket
        if let data = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private enum Divergence { case supporting, opposing, none }

    private func divergenceState(_ candles: [Kline], direction: SignalType) -> Divergence {
        let recent = Array(candles.suffix(40))
        guard recent.count >= 20 else { return .none }
        let rsi = relativeStrengthIndex(recent, period: 14)
        guard rsi.count >= 10 else { return .none }

        let firstPrice = recent.dropLast(10).map(\.close).max() ?? 0
        let secondPrice = recent.suffix(10).map(\.close).max() ?? 0
        let firstLow = recent.dropLast(10).map(\.close).min() ?? 0
        let secondLow = recent.suffix(10).map(\.close).min() ?? 0
        let firstRSI = rsi.prefix(max(1, rsi.count - 5)).max() ?? 50
        let secondRSI = rsi.suffix(5).max() ?? 50
        let firstRSILow = rsi.prefix(max(1, rsi.count - 5)).min() ?? 50
        let secondRSILow = rsi.suffix(5).min() ?? 50

        let bearish = secondPrice > firstPrice && secondRSI < firstRSI
        let bullish = secondLow < firstLow && secondRSILow > firstRSILow

        if direction == .buy { return bullish ? .supporting : (bearish ? .opposing : .none) }
        if direction == .sell { return bearish ? .supporting : (bullish ? .opposing : .none) }
        return .none
    }

    private func microReversalConfirmation(_ candles: [Kline], direction: SignalType) -> (confirmed: Bool, reason: String) {
        let recent = Array(candles.suffix(8))
        guard recent.count >= 5 else { return (false, "reversal confirmation unavailable") }
        let previous = recent.dropLast(2)
        let turn = recent[recent.count - 2]
        let latest = recent[recent.count - 1]

        if direction == .buy {
            let dipped = (previous.map(\.close).max() ?? latest.close) > (previous.map(\.close).min() ?? latest.close)
            let bullish = latest.close > latest.open && latest.close > turn.high
            return (dipped && bullish, dipped && bullish ? "dip → bullish reclaim confirmed" : "buy waiting for bullish reclaim")
        }
        if direction == .sell {
            let rallied = (previous.map(\.close).max() ?? latest.close) > (previous.map(\.close).min() ?? latest.close)
            let bearish = latest.close < latest.open && latest.close < turn.low
            return (rallied && bearish, rallied && bearish ? "rally → bearish rejection confirmed" : "sell waiting for bearish rejection")
        }
        return (true, "no directional confirmation required")
    }

    private func relativeStrengthIndex(_ candles: [Kline], period: Int) -> [Double] {
        guard candles.count > period else { return [] }
        var gains = 0.0
        var losses = 0.0
        for i in 1...period {
            let delta = candles[i].close - candles[i - 1].close
            if delta >= 0 { gains += delta } else { losses -= delta }
        }
        var result: [Double] = []
        var avgGain = gains / Double(period)
        var avgLoss = losses / Double(period)
        result.append(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss))
        if candles.count > period + 1 {
            for i in (period + 1)..<candles.count {
                let delta = candles[i].close - candles[i - 1].close
                let gain = max(delta, 0)
                let loss = max(-delta, 0)
                avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
                avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
                result.append(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss))
            }
        }
        return result
    }

    private func choppinessIndex(_ candles: [Kline], period: Int) -> Double {
        guard candles.count > period else { return 50 }
        let recent = Array(candles.suffix(period + 1))
        var trSum = 0.0
        for i in 1..<recent.count {
            trSum += max(recent[i].high - recent[i].low, abs(recent[i].high - recent[i - 1].close), abs(recent[i].low - recent[i - 1].close))
        }
        let high = recent.map(\.high).max() ?? 0
        let low = recent.map(\.low).min() ?? 0
        let range = high - low
        guard trSum > 0, range > 0 else { return 100 }
        return 100 * log10(trSum / range) / log10(Double(period))
    }

    private func hurstExponent(_ prices: [Double]) -> Double {
        guard prices.count >= 40 else { return 0.5 }
        let sample = Array(prices.suffix(100))
        var xs: [Double] = []
        var ys: [Double] = []
        let maxLag = min(sample.count / 4, 20)
        guard maxLag >= 5 else { return 0.5 }
        for lag in 5...maxLag {
            var rsValues: [Double] = []
            var start = 0
            while start + lag <= sample.count {
                let segment = Array(sample[start..<(start + lag)])
                let mean = segment.reduce(0, +) / Double(segment.count)
                var cumulative = 0.0
                var minC = 0.0
                var maxC = 0.0
                for value in segment {
                    cumulative += value - mean
                    minC = min(minC, cumulative)
                    maxC = max(maxC, cumulative)
                }
                let variance = segment.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(segment.count)
                let sd = sqrt(variance)
                if sd > 0 { rsValues.append((maxC - minC) / sd) }
                start += lag
            }
            if let rs = rsValues.first(where: { $0 > 0 }) {
                xs.append(log(Double(lag)))
                ys.append(log(rsValues.reduce(0, +) / Double(rsValues.count)))
                _ = rs
            }
        }
        guard xs.count >= 3 else { return 0.5 }
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let denominator = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        guard denominator > 0 else { return 0.5 }
        return max(0, min(1, numerator / denominator))
    }

    private func sessionMultiplier(for date: Date) -> Double {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        switch hour {
        case 7...10, 13...16: return 1.10
        case 22...23, 0...5: return 0.94
        default: return 1.0
        }
    }
}
