import Foundation

/// Final price-action gate for runner-oriented entries.
/// Evaluates only closed candles and fails closed when confirmation is insufficient.
struct RunnerContinuationConfiguration: Sendable {
    var enabled: Bool = true
    var candleLookback: Int = 4
    var minimumAlignedCandles: Int = 3
    var requireLatestCandleAlignment: Bool = true
    var requireProgressiveCloses: Bool = false
    var minimumBodyToRangeRatio: Double = 0.45
    var maximumOpposingWickToBodyRatio: Double = 0.75
    var minimumAccelerationRatio: Double = 1.05
    var maximumBreakoutExtensionATR: Double = 0.80
    var antiRunnerRangeMultiplier: Double = 1.80
    var antiRunnerWickRatio: Double = 1.25
    var atrLookback: Int = 14
}

struct RunnerCandle: Sendable {
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    var range: Double { max(0, high - low) }
    var body: Double { abs(close - open) }
    var bodyToRange: Double { range > 0 ? body / range : 0 }
    var bullish: Bool { close > open }
    var bearish: Bool { close < open }
}

struct RunnerContinuationResult: Sendable {
    let passed: Bool
    let reason: String
    let alignedCandles: Int
    let accelerationRatio: Double
    let extensionATR: Double
    let latestBodyToRange: Double
    let latestOpposingWickRatio: Double
    let antiRunnerTriggered: Bool
}

struct RunnerContinuationGate: Sendable {
    let configuration: RunnerContinuationConfiguration

    func evaluate(direction: String, candles: [RunnerCandle], keyLevel: Double? = nil, atr: Double? = nil) -> RunnerContinuationResult {
        guard configuration.enabled else { return result(true, "disabled", 0, 1, 0, 0, 0, false) }

        let lookback = min(max(configuration.candleLookback, 2), 8)
        guard candles.count >= lookback else {
            return result(false, "insufficient closed candles (need \(lookback))", 0, 0, 0, 0, 0, false)
        }

        let recent = Array(candles.suffix(lookback))
        let isBuy = direction.uppercased() == "BUY"
        let isSell = direction.uppercased() == "SELL"
        guard isBuy || isSell else { return result(false, "invalid signal direction", 0, 0, 0, 0, 0, false) }

        let aligned = recent.filter { isBuy ? $0.bullish : $0.bearish }.count
        let minimumAligned = min(max(configuration.minimumAlignedCandles, 2), lookback)
        let latest = recent[recent.count - 1]
        let latestAligned = isBuy ? latest.bullish : latest.bearish
        let wickRatio = opposingWickRatio(latest, bullish: isBuy)

        guard aligned >= minimumAligned else {
            return result(false, "candle alignment \(aligned)/\(lookback)", aligned, 0, 0, latest.bodyToRange, wickRatio, false)
        }
        guard !configuration.requireLatestCandleAlignment || latestAligned else {
            return result(false, "latest closed candle disagrees with signal", aligned, 0, 0, latest.bodyToRange, wickRatio, false)
        }

        if configuration.requireProgressiveCloses {
            for index in 1..<recent.count {
                let previous = recent[index - 1]
                let current = recent[index]
                if isBuy && current.close <= previous.close {
                    return result(false, "bullish closes are not progressive", aligned, 0, 0, latest.bodyToRange, wickRatio, false)
                }
                if isSell && current.close >= previous.close {
                    return result(false, "bearish closes are not progressive", aligned, 0, 0, latest.bodyToRange, wickRatio, false)
                }
            }
        }

        let midpoint = max(1, recent.count / 2)
        let earlyCount = midpoint
        let lateCount = recent.count - midpoint
        let early = recent.prefix(earlyCount).map(\.body).reduce(0, +) / Double(earlyCount)
        let late = recent.suffix(lateCount).map(\.body).reduce(0, +) / Double(lateCount)
        let acceleration = early > 0 ? late / early : (late > 0 ? 999 : 1)
        guard acceleration >= configuration.minimumAccelerationRatio else {
            return result(false, String(format: "momentum not accelerating (%.2fx)", acceleration), aligned, acceleration, 0, latest.bodyToRange, wickRatio, false)
        }

        guard latest.bodyToRange >= configuration.minimumBodyToRangeRatio else {
            return result(false, String(format: "weak candle body (%.2f)", latest.bodyToRange), aligned, acceleration, 0, latest.bodyToRange, wickRatio, false)
        }
        guard wickRatio <= configuration.maximumOpposingWickToBodyRatio else {
            return result(false, String(format: "poor wick quality (%.2fx)", wickRatio), aligned, acceleration, 0, latest.bodyToRange, wickRatio, false)
        }

        var extensionATR = 0.0
        if let keyLevel, let atr, atr > 0 {
            let breakoutDistance = isBuy ? latest.close - keyLevel : keyLevel - latest.close
            extensionATR = max(0, breakoutDistance) / atr
            guard extensionATR <= configuration.maximumBreakoutExtensionATR else {
                return result(false, String(format: "breakout overextended (%.2f ATR)", extensionATR), aligned, acceleration, extensionATR, latest.bodyToRange, wickRatio, false)
            }
        }

        let priorRanges = recent.dropLast().map(\.range).sorted()
        let baselineRange = priorRanges.isEmpty ? latest.range : priorRanges[priorRanges.count / 2]
        let antiRunner = baselineRange > 0 && latest.range > baselineRange * configuration.antiRunnerRangeMultiplier && wickRatio >= configuration.antiRunnerWickRatio
        guard !antiRunner else {
            return result(false, "anti-runner exhaustion pattern", aligned, acceleration, extensionATR, latest.bodyToRange, wickRatio, true)
        }

        return result(true, "runner continuation confirmed", aligned, acceleration, extensionATR, latest.bodyToRange, wickRatio, false)
    }

    private func opposingWickRatio(_ candle: RunnerCandle, bullish: Bool) -> Double {
        guard candle.body > 0 else { return .infinity }
        let wick = bullish ? candle.high - max(candle.open, candle.close) : min(candle.open, candle.close) - candle.low
        return max(0, wick) / candle.body
    }

    private func result(_ passed: Bool, _ reason: String, _ aligned: Int, _ acceleration: Double, _ extensionATR: Double, _ body: Double, _ wick: Double, _ antiRunner: Bool) -> RunnerContinuationResult {
        RunnerContinuationResult(passed: passed, reason: reason, alignedCandles: aligned, accelerationRatio: _acceleration, extensionATR: _extensionATR, latestBodyToRange: body, latestOpposingWickRatio: wick, antiRunnerTriggered: _antiRunner)
    }
}
