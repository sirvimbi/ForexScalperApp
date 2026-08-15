import Foundation

enum SignalAccuracyEngine {
    struct Assessment {
        let approved: Bool
        let confidenceAdjustment: Double
        let regime: String
        let choppiness: Double
        let hurst: Double
        let reasons: [String]
        var insight: String {
            let reasonText = reasons.isEmpty ? "No exceptional confirmation factors." : reasons.joined(separator: "; ")
            return "Accuracy layer | regime=\(regime) | H=\(String(format: "%.2f", hurst)) | chop=\(String(format: "%.1f", choppiness)) | \(reasonText)"
        }
    }
    private enum Divergence { case supporting, opposing, none }

    static func assess(symbol: String, direction: SignalType, candles: [Kline]) async -> Assessment {
        let settings = await SignalAccuracySettingsStore.shared.snapshot()
        guard candles.count >= settings.minimumHistoryCandles, direction != .none else {
            return Assessment(approved: true, confidenceAdjustment: 0, regime: "unknown", choppiness: 50, hurst: 0.5, reasons: ["insufficient accuracy-layer history"])
        }
        let hurst = hurstExponent(candles.map(\.close))
        let chop = choppinessIndex(candles, period: settings.choppinessPeriod)
        let divergence = divergenceState(candles, direction: direction, settings: settings)
        let reversal = microReversalConfirmation(candles, direction: direction)
        let session = sessionMultiplier(for: Date(), settings: settings)
        var adjustment = 0.0
        var reasons: [String] = []
        var approved = true
        let regime: String

        if chop >= settings.choppinessWarningThreshold {
            regime = "choppy"
            reasons.append("high choppiness")
            if chop >= settings.choppinessVetoThreshold { approved = false }
        } else if hurst >= settings.hurstTrendingThreshold {
            regime = "trending"
            adjustment += settings.trendingRegimeAdjustment
            reasons.append("persistent trend")
        } else if hurst <= settings.hurstMeanReversionThreshold {
            regime = "mean-reverting"
            adjustment += settings.meanReversionRegimeAdjustment
            reasons.append("mean-reversion regime")
        } else {
            regime = "transitional"
        }

        switch divergence {
        case .supporting:
            adjustment += settings.supportingDivergenceAdjustment
            reasons.append("directional RSI divergence")
        case .opposing:
            adjustment += settings.opposingDivergenceAdjustment
            reasons.append("opposing RSI/price divergence")
            approved = false
        case .none: break
        }
        if reversal.confirmed {
            adjustment += settings.reversalConfirmedAdjustment
            reasons.append(reversal.reason)
        } else {
            adjustment += regime == "trending" ? settings.reversalWaitingTrendPenalty : settings.reversalWaitingOtherPenalty
            reasons.append(reversal.reason)
        }
        if session > 1.0 {
            adjustment += (session - 1.0) * abs(settings.reversalConfirmedAdjustment)
            reasons.append("session momentum favorable")
        } else if session < 1.0 {
            adjustment += (session - 1.0) * abs(settings.reversalConfirmedAdjustment)
            reasons.append("session quality reduced")
        }
        let posteriorWinRate = await SignalAccuracyBayesianStore.shared.posteriorWinRate(
            key: "\(symbol.uppercased()):\(direction)", priorWins: settings.bayesianPriorWins, priorLosses: settings.bayesianPriorLosses)
        adjustment += (posteriorWinRate - 0.5) * settings.bayesianAdjustmentScale
        reasons.append("Bayesian prior=\(Int(posteriorWinRate * 100))%")

        return Assessment(approved: approved,
                          confidenceAdjustment: max(settings.confidenceAdjustmentFloor, min(settings.confidenceAdjustmentCeiling, adjustment)),
                          regime: regime, choppiness: chop, hurst: hurst, reasons: reasons)
    }

    static func recordOutcome(outcomeID: String, symbol: String, direction: SignalType, profitable: Bool) async {
        guard direction != .none else { return }
        let settings = await SignalAccuracySettingsStore.shared.snapshot()
        await SignalAccuracyBayesianStore.shared.record(outcomeID: outcomeID,
                                                         key: "\(symbol.uppercased()):\(direction)",
                                                         profitable: profitable,
                                                         priorWins: settings.bayesianPriorWins,
                                                         priorLosses: settings.bayesianPriorLosses)
        godLog("🧠 BAYESIAN OUTCOME | \(symbol) | direction=\(direction) | result=\(profitable ? "WIN" : "LOSS") | id=\(outcomeID)", level: .info)
    }

    private static func divergenceState(_ candles: [Kline], direction: SignalType, settings: SignalAccuracyConfiguration) -> Divergence {
        let recent = Array(candles.suffix(settings.divergenceLookback))
        guard recent.count >= 20 else { return .none }
        let rsi = relativeStrengthIndex(recent, period: settings.choppinessPeriod)
        guard rsi.count >= 10 else { return .none }
        let midpoint = max(1, recent.count / 2)
        let first = Array(recent.prefix(midpoint)), second = Array(recent.suffix(midpoint))
        let firstPriceHigh = first.map(\.close).max() ?? 0, secondPriceHigh = second.map(\.close).max() ?? 0
        let firstPriceLow = first.map(\.close).min() ?? 0, secondPriceLow = second.map(\.close).min() ?? 0
        let half = max(1, rsi.count / 2)
        let firstRSIHigh = rsi.prefix(half).max() ?? 50, secondRSIHigh = rsi.suffix(half).max() ?? 50
        let firstRSILow = rsi.prefix(half).min() ?? 50, secondRSILow = rsi.suffix(half).min() ?? 50
        let bearish = secondPriceHigh > firstPriceHigh && secondRSIHigh < firstRSIHigh - settings.divergenceRSIMargin
        let bullish = secondPriceLow < firstPriceLow && secondRSILow > firstRSILow + settings.divergenceRSIMargin
        if direction == .buy { return bullish ? .supporting : (bearish ? .opposing : .none) }
        if direction == .sell { return bearish ? .supporting : (bullish ? .opposing : .none) }
        return .none
    }

    private static func microReversalConfirmation(_ candles: [Kline], direction: SignalType) -> (confirmed: Bool, reason: String) {
        let recent = Array(candles.suffix(8))
        guard recent.count >= 5 else { return (false, "reversal confirmation unavailable") }
        let previous = recent.dropLast(2), turn = recent[recent.count - 2], latest = recent[recent.count - 1]
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

    private static func relativeStrengthIndex(_ candles: [Kline], period: Int) -> [Double] {
        guard candles.count > period else { return [] }
        var gains = 0.0, losses = 0.0
        for i in 1...period { let delta = candles[i].close - candles[i - 1].close; if delta >= 0 { gains += delta } else { losses -= delta } }
        var result: [Double] = [], avgGain = gains / Double(period), avgLoss = losses / Double(period)
        result.append(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss))
        if candles.count > period + 1 {
            for i in (period + 1)..<candles.count {
                let delta = candles[i].close - candles[i - 1].close, gain = max(delta, 0), loss = max(-delta, 0)
                avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
                avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
                result.append(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss))
            }
        }
        return result
    }

    private static func choppinessIndex(_ candles: [Kline], period: Int) -> Double {
        guard candles.count > period else { return 50 }
        let recent = Array(candles.suffix(period + 1))
        var trSum = 0.0
        for i in 1..<recent.count { trSum += max(recent[i].high - recent[i].low, abs(recent[i].high - recent[i - 1].close), abs(recent[i].low - recent[i - 1].close)) }
        let high = recent.map(\.high).max() ?? 0, low = recent.map(\.low).min() ?? 0, range = high - low
        guard trSum > 0, range > 0 else { return 100 }
        return 100 * log10(trSum / range) / log10(Double(period))
    }

    private static func hurstExponent(_ prices: [Double]) -> Double {
        guard prices.count >= 40 else { return 0.5 }
        let sample = Array(prices.suffix(100)); var xs: [Double] = [], ys: [Double] = []
        let maxLag = min(sample.count / 4, 20); guard maxLag >= 5 else { return 0.5 }
        for lag in 5...maxLag {
            var rsValues: [Double] = [], start = 0
            while start + lag <= sample.count {
                let segment = Array(sample[start..<(start + lag)]), mean = segment.reduce(0, +) / Double(segment.count)
                var cumulative = 0.0, minC = 0.0, maxC = 0.0
                for value in segment { cumulative += value - mean; minC = min(minC, cumulative); maxC = max(maxC, cumulative) }
                let variance = segment.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(segment.count), sd = sqrt(variance)
                if sd > 0 { rsValues.append((maxC - minC) / sd) }
                start += lag
            }
            if !rsValues.isEmpty { xs.append(log(Double(lag))); ys.append(log(rsValues.reduce(0, +) / Double(rsValues.count))) }
        }
        guard xs.count >= 3 else { return 0.5 }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +), denominator = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        guard denominator > 0 else { return 0.5 }
        return max(0, min(1, numerator / denominator))
    }

    private static func sessionMultiplier(for date: Date, settings: SignalAccuracyConfiguration) -> Double {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        let favorable1 = hour >= settings.favorableSession1StartHour && hour <= settings.favorableSession1EndHour
        let favorable2 = hour >= settings.favorableSession2StartHour && hour <= settings.favorableSession2EndHour
        let reduced = settings.reducedSessionStartHour <= settings.reducedSessionEndHour
            ? hour >= settings.reducedSessionStartHour && hour <= settings.reducedSessionEndHour
            : hour >= settings.reducedSessionStartHour || hour <= settings.reducedSessionEndHour
        if favorable1 || favorable2 { return settings.favorableSessionMultiplier }
        if reduced { return settings.reducedSessionMultiplier }
        return 1.0
    }
}

private actor SignalAccuracyBayesianStore {
    static let shared = SignalAccuracyBayesianStore()
    private struct Bucket: Codable { var wins: Double; var losses: Double }
    private struct Persisted: Codable { var buckets: [String: Bucket]; var recordedOutcomeIDs: Set<String> }
    private var loaded = false
    private var buckets: [String: Bucket] = [:]
    private var recordedOutcomeIDs: Set<String> = []
    private let storageKey = "signal.accuracy.bayesian.v2"

    func posteriorWinRate(key: String, priorWins: Double, priorLosses: Double) -> Double {
        loadIfNeeded(); let bucket = buckets[key] ?? Bucket(wins: priorWins, losses: priorLosses)
        return bucket.wins / max(0.000001, bucket.wins + bucket.losses)
    }
    func record(outcomeID: String, key: String, profitable: Bool, priorWins: Double, priorLosses: Double) {
        loadIfNeeded(); guard !recordedOutcomeIDs.contains(outcomeID) else { return }
        var bucket = buckets[key] ?? Bucket(wins: priorWins, losses: priorLosses)
        if profitable { bucket.wins += 1 } else { bucket.losses += 1 }
        buckets[key] = bucket; recordedOutcomeIDs.insert(outcomeID); persist()
    }
    private func loadIfNeeded() {
        guard !loaded else { return }; loaded = true
        guard let data = UserDefaults.standard.data(forKey: storageKey), let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        buckets = persisted.buckets; recordedOutcomeIDs = persisted.recordedOutcomeIDs
    }
    private func persist() {
        let persisted = Persisted(buckets: buckets, recordedOutcomeIDs: recordedOutcomeIDs)
        if let data = try? JSONEncoder().encode(persisted) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
}
