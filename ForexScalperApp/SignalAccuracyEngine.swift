import Foundation

enum SignalAccuracyEngine {
    struct Assessment {
        let approved: Bool; let confidenceAdjustment: Double; let regime: String; let choppiness: Double; let hurst: Double; let reasons: [String]
        var insight: String { let text = reasons.isEmpty ? "No exceptional confirmation factors." : reasons.joined(separator: "; "); return "Accuracy layer | regime=\(regime) | H=\(String(format: "%.2f", hurst)) | chop=\(String(format: "%.1f", choppiness)) | \(text)" }
    }
    private enum Divergence { case supporting, opposing, none }

    static func assess(symbol: String, direction: SignalType, candles: [Kline]) -> Assessment {
        let settings = SignalAccuracyRuntimeCache.shared.snapshot(); guard candles.count >= settings.minimumHistoryCandles, direction != .none else { return Assessment(approved: true, confidenceAdjustment: 0, regime: "unknown", choppiness: 50, hurst: 0.5, reasons: ["insufficient accuracy-layer history"]) }
        let hurst = hurstExponent(candles.map(\.close)), chop = choppinessIndex(candles, period: settings.choppinessPeriod), divergence = divergenceState(candles, direction: direction, settings: settings), reversal = microReversalConfirmation(candles, direction: direction), session = sessionMultiplier(for: Date(), settings: settings)
        var adjustment = 0.0, reasons: [String] = [], approved = true; let regime: String
        if chop >= settings.choppinessWarningThreshold { regime = "choppy"; reasons.append("high choppiness"); if chop >= settings.choppinessVetoThreshold { approved = false } }
        else if hurst >= settings.hurstTrendingThreshold { regime = "trending"; adjustment += settings.trendingRegimeAdjustment; reasons.append("persistent trend") }
        else if hurst <= settings.hurstMeanReversionThreshold { regime = "mean-reverting"; adjustment += settings.meanReversionRegimeAdjustment; reasons.append("mean-reversion regime") }
        else { regime = "transitional" }
        switch divergence { case .supporting: adjustment += settings.supportingDivergenceAdjustment; reasons.append("directional RSI divergence"); case .opposing: adjustment += settings.opposingDivergenceAdjustment; reasons.append("opposing RSI/price divergence"); approved = false; case .none: break }
        if reversal.confirmed { adjustment += settings.reversalConfirmedAdjustment; reasons.append(reversal.reason) } else { adjustment += regime == "trending" ? settings.reversalWaitingTrendPenalty : settings.reversalWaitingOtherPenalty; reasons.append(reversal.reason) }
        if session > 1 { adjustment += (session - 1) * abs(settings.reversalConfirmedAdjustment); reasons.append("session momentum favorable") } else if session < 1 { adjustment += (session - 1) * abs(settings.reversalConfirmedAdjustment); reasons.append("session quality reduced") }
        let posterior = SignalAccuracyBayesianRuntime.shared.snapshot(key: "\(symbol.uppercased()):\(direction)", priorWins: settings.bayesianPriorWins, priorLosses: settings.bayesianPriorLosses); adjustment += (posterior - 0.5) * settings.bayesianAdjustmentScale; reasons.append("Bayesian prior=\(Int(posterior * 100))%")
        return Assessment(approved: approved, confidenceAdjustment: max(settings.confidenceAdjustmentFloor, min(settings.confidenceAdjustmentCeiling, adjustment)), regime: regime, choppiness: chop, hurst: hurst, reasons: reasons)
    }

    static func recordOutcome(outcomeID: String, symbol: String, direction: SignalType, profitable: Bool, updateRuntime: Bool = true) async {
        guard direction != .none else { return }; let settings = await SignalAccuracySettingsStore.shared.snapshot(); let key = "\(symbol.uppercased()):\(direction)"
        let didRecord = await SignalAccuracyBayesianStore.shared.record(outcomeID: outcomeID, key: key, profitable: profitable, priorWins: settings.bayesianPriorWins, priorLosses: settings.bayesianPriorLosses)
        if updateRuntime && didRecord { SignalAccuracyBayesianRuntime.shared.update(key: key, profitable: profitable, priorWins: settings.bayesianPriorWins, priorLosses: settings.bayesianPriorLosses) }
        godLog("🧠 BAYESIAN OUTCOME | \(symbol) | direction=\(direction) | result=\(profitable ? "WIN" : "LOSS") | id=\(outcomeID) | counted=\(didRecord)", level: .info)
    }

    private static func divergenceState(_ candles: [Kline], direction: SignalType, settings: SignalAccuracyConfiguration) -> Divergence {
        let recent = Array(candles.suffix(settings.divergenceLookback)); guard recent.count >= 20 else { return .none }; let rsi = relativeStrengthIndex(recent, period: settings.choppinessPeriod); guard rsi.count >= 10 else { return .none }
        let half = max(1, recent.count / 2), first = Array(recent.prefix(half)), second = Array(recent.suffix(half)); let firstHigh = first.map(\.close).max() ?? 0, secondHigh = second.map(\.close).max() ?? 0, firstLow = first.map(\.close).min() ?? 0, secondLow = second.map(\.close).min() ?? 0
        let rHalf = max(1, rsi.count / 2), firstRH = rsi.prefix(rHalf).max() ?? 50, secondRH = rsi.suffix(rHalf).max() ?? 50, firstRL = rsi.prefix(rHalf).min() ?? 50, secondRL = rsi.suffix(rHalf).min() ?? 50
        let bearish = secondHigh > firstHigh && secondRH < firstRH - settings.divergenceRSIMargin, bullish = secondLow < firstLow && secondRL > firstRL + settings.divergenceRSIMargin
        if direction == .buy { return bullish ? .supporting : (bearish ? .opposing : .none) }; if direction == .sell { return bearish ? .supporting : (bullish ? .opposing : .none) }; return .none
    }

    private static func microReversalConfirmation(_ candles: [Kline], direction: SignalType) -> (confirmed: Bool, reason: String) {
        let recent = Array(candles.suffix(8)); guard recent.count >= 5 else { return (false, "reversal confirmation unavailable") }; let previous = recent.dropLast(2), turn = recent[recent.count - 2], latest = recent[recent.count - 1]
        if direction == .buy { let dipped = (previous.map(\.close).max() ?? latest.close) > (previous.map(\.close).min() ?? latest.close), bullish = latest.close > latest.open && latest.close > turn.high; return (dipped && bullish, dipped && bullish ? "dip → bullish reclaim confirmed" : "buy waiting for bullish reclaim") }
        if direction == .sell { let rallied = (previous.map(\.close).max() ?? latest.close) > (previous.map(\.close).min() ?? latest.close), bearish = latest.close < latest.open && latest.close < turn.low; return (rallied && bearish, rallied && bearish ? "rally → bearish rejection confirmed" : "sell waiting for bearish rejection") }
        return (true, "no directional confirmation required")
    }

    private static func relativeStrengthIndex(_ candles: [Kline], period: Int) -> [Double] {
        guard candles.count > period else { return [] }; var gains = 0.0, losses = 0.0; for i in 1...period { let d = candles[i].close - candles[i - 1].close; if d >= 0 { gains += d } else { losses -= d } }; var result: [Double] = [], avgGain = gains / Double(period), avgLoss = losses / Double(period); result.append(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss)); if candles.count > period + 1 { for i in (period + 1)..<candles.count { let d = candles[i].close - candles[i - 1].close; avgGain = (avgGain * Double(period - 1) + max(d, 0)) / Double(period); avgLoss = (avgLoss * Double(period - 1) + max(-d, 0)) / Double(period); result.append(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss)) } }; return result
    }
    private static func choppinessIndex(_ candles: [Kline], period: Int) -> Double { guard candles.count > period else { return 50 }; let recent = Array(candles.suffix(period + 1)); var tr = 0.0; for i in 1..<recent.count { tr += max(recent[i].high - recent[i].low, abs(recent[i].high - recent[i - 1].close), abs(recent[i].low - recent[i - 1].close)) }; let range = (recent.map(\.high).max() ?? 0) - (recent.map(\.low).min() ?? 0); guard tr > 0, range > 0 else { return 100 }; return 100 * log10(tr / range) / log10(Double(period)) }
    private static func hurstExponent(_ prices: [Double]) -> Double { guard prices.count >= 40 else { return 0.5 }; let sample = Array(prices.suffix(100)); var xs: [Double] = [], ys: [Double] = []; let maxLag = min(sample.count / 4, 20); guard maxLag >= 5 else { return 0.5 }; for lag in 5...maxLag { var rs: [Double] = [], start = 0; while start + lag <= sample.count { let segment = Array(sample[start..<(start + lag)]), mean = segment.reduce(0, +) / Double(segment.count); var cumulative = 0.0, minC = 0.0, maxC = 0.0; for value in segment { cumulative += value - mean; minC = min(minC, cumulative); maxC = max(maxC, cumulative) }; let sd = sqrt(segment.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(segment.count)); if sd > 0 { rs.append((maxC - minC) / sd) }; start += lag }; if !rs.isEmpty { xs.append(log(Double(lag))); ys.append(log(rs.reduce(0, +) / Double(rs.count))) } }; guard xs.count >= 3 else { return 0.5 }; let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count), num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +), den = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +); guard den > 0 else { return 0.5 }; return max(0, min(1, num / den)) }
    private static func sessionMultiplier(for date: Date, settings: SignalAccuracyConfiguration) -> Double { let hour = Calendar(identifier: .gregorian).component(.hour, from: date); let favorable = (hour >= settings.favorableSession1StartHour && hour <= settings.favorableSession1EndHour) || (hour >= settings.favorableSession2StartHour && hour <= settings.favorableSession2EndHour); let reduced = settings.reducedSessionStartHour <= settings.reducedSessionEndHour ? hour >= settings.reducedSessionStartHour && hour <= settings.reducedSessionEndHour : hour >= settings.reducedSessionStartHour || hour <= settings.reducedSessionEndHour; if favorable { return settings.favorableSessionMultiplier }; if reduced { return settings.reducedSessionMultiplier }; return 1 }
}

final class SignalAccuracyBayesianRuntime: @unchecked Sendable {
    static let shared = SignalAccuracyBayesianRuntime(); private struct Bucket: Codable { var wins: Double; var losses: Double }; private struct Persisted: Codable { var buckets: [String: Bucket] }; private let lock = NSLock(); private var buckets: [String: Bucket] = [:]
    private init() { if let data = UserDefaults.standard.data(forKey: "signal.accuracy.bayesian.v2"), let persisted = try? JSONDecoder().decode(Persisted.self, from: data) { buckets = persisted.buckets } }
    func snapshot(key: String, priorWins: Double, priorLosses: Double) -> Double { lock.lock(); defer { lock.unlock() }; let b = buckets[key] ?? Bucket(wins: priorWins, losses: priorLosses); return b.wins / max(0.000001, b.wins + b.losses) }
    func update(key: String, profitable: Bool, priorWins: Double, priorLosses: Double) { lock.lock(); defer { lock.unlock() }; var b = buckets[key] ?? Bucket(wins: priorWins, losses: priorLosses); if profitable { b.wins += 1 } else { b.losses += 1 }; buckets[key] = b }
}

private actor SignalAccuracyBayesianStore {
    static let shared = SignalAccuracyBayesianStore(); private struct Bucket: Codable { var wins: Double; var losses: Double }; private struct Persisted: Codable { var buckets: [String: Bucket]; var recordedOutcomeIDs: Set<String> }; private var loaded = false; private var buckets: [String: Bucket] = [:]; private var recordedOutcomeIDs: Set<String> = []; private let storageKey = "signal.accuracy.bayesian.v2"
    func record(outcomeID: String, key: String, profitable: Bool, priorWins: Double, priorLosses: Double) -> Bool { loadIfNeeded(); guard !recordedOutcomeIDs.contains(outcomeID) else { return false }; var b = buckets[key] ?? Bucket(wins: priorWins, losses: priorLosses); if profitable { b.wins += 1 } else { b.losses += 1 }; buckets[key] = b; recordedOutcomeIDs.insert(outcomeID); persist(); return true }
    private func loadIfNeeded() { guard !loaded else { return }; loaded = true; guard let data = UserDefaults.standard.data(forKey: storageKey), let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }; buckets = persisted.buckets; recordedOutcomeIDs = persisted.recordedOutcomeIDs }
    private func persist() { let persisted = Persisted(buckets: buckets, recordedOutcomeIDs: recordedOutcomeIDs); if let data = try? JSONEncoder().encode(persisted) { UserDefaults.standard.set(data, forKey: storageKey) } }
}
