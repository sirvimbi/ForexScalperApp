import Foundation

/// Final price-action gate for runner-oriented entries.
///
/// The gate is intentionally conservative: it evaluates only closed candles,
/// requires directional continuation, rewards acceleration, rejects excessive
/// extension through the broken level, rejects poor wick quality, and blocks
/// entries when the move shows signs of exhaustion (the anti-runner check).
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

    func evaluate(
        direction: String,
        candles: [RunnerCandle],
        keyLevel: Double? = nil,
        atr: Double? = nil
    ) -> RunnerContinuationResult {
        guard configuration.enabled else {
            return result(true, "disabled", 0, 1, 0, 0, 0, false)
        }

        let lookback = max(2, configuration.candleLookback)
        guard candles.count >= lookback else {
            return result(false, "insufficient closed candles (need \(lookback))", 0, 0, 0, 0, 0, false)
        }

        let recent = Array(candles.suffix(lookback))
        let bullish = direction.uppercased() == "BUY"
        let aligned = recent.filter { bullish ? $0.bullish : $0.bearish }.count
        let latest = recent[recent.count - 1]

        if aligned < min(configuration.minimumAlignedCandles, lookback) {
            return result(false, "candle alignment \(aligned)/\(lookback)", aligned, 0, 0, latest.bodyToRange, opposingWickRatio(latest, bullish: bullish), false)
        }

        if configuration.requireLatestCandleAlignment && !(bullish ? latest.bullish : latest.bearish) {
            return result(false, "latest closed candle disagrees with signal", aligned, 0, 0, latest.bodyToRange, opposingWickRatio(latest, bullish: bullish), false)
        }

        let midpoint = max(1, recent.count / 2)
        let early = recent.prefix(midpoint).map(\.body).reduce(0, +) / Double(max(1, midpoint))
        let late = recent.suffix(recent.count - midpoint).map(\.body).reduce(0, +) / Double(max(1, recent.count - midpoint))
        let acceleration = early > 0 ? late / early : (late > 0 ? 999 : 1)

        if acceleration < configuration.minimumAccelerationRatio {
            return result(false, String(format: "momentum not accelerating (%.2fx)", acceleration), aligned, acceleration, 0, latest.bodyToRange, opposingWickRatio(latest, bullish: bullish), false)
        }

        let wickRatio = opposingWickRatio(latest, bullish: bullish)
        if latest.bodyToRange < configuration.minimumBodyToRangeRatio {
            return result(false, String(format: "weak candle body (%.2f)", latest.bodyToRange), aligned, acceleration, 0, latest.bodyToRange, wickRatio, false)
        }
        if wickRatio > configuration.maximumOpposingWickToBodyRatio {
            return result(false, String(format: "poor wick quality (%.2fx)", wickRatio), aligned, acceleration, 0, latest.bodyToRange, wickRatio, false)
        }

        var extensionATR = 0.0
        if let keyLevel, let atr, atr > 0 {
            let extension = bullish ? latest.close - keyLevel : keyLevel - latest.close
            extensionATR = max(0, extension) / atr
            if extensionATR > configuration.maximumBreakoutExtensionATR {
                return result(false, String(format: "breakout overextended (%.2f ATR)", extensionATR), aligned, acceleration, extensionATR, latest.bodyToRange, wickRatio, false)
            }
        }

        let medianRange = recent.dropLast().map(\.range).sorted()
        let baselineRange: Double
        if medianRange.isEmpty { baselineRange = latest.range } else {
            baselineRange = medianRange[medianRange.count / 2]
        }
        let antiRunner = baselineRange > 0 && latest.range > baselineRange * configuration.antiRunnerRangeMultiplier && wickRatio >= configuration.antiRunnerWickRatio
        if antiRunner {
            return result(false, "anti-runner exhaustion pattern", aligned, acceleration, extensionATR, latest.bodyToRange, wickRatio, true)
        }

        return result(true, "runner continuation confirmed", aligned, acceleration, extensionATR, latest.bodyToRange, wickRatio, false)
    }

    private func opposingWickRatio(_ candle: RunnerCandle, bullish: Bool) -> Double {
        guard candle.body > 0 else { return .infinity }
        let wick = bullish ? candle.high - max(candle.open, candle.close) : min(candle.open, candle.close) - candle.low
        return max(0, wick) / candle.body
    }

    private func result(_ passed: Bool, _ reason: String, _ aligned: Int, _ acceleration: Double, _ extension: Double, _ body: Double, _ wick: Double, _ antiRunner: Bool) -> RunnerContinuationResult {
        RunnerContinuationResult(passed: passed, reason: reason, alignedCandles: aligned, accelerationRatio: acceleration, extensionATR: extension, latestBodyToRange: body, latestOpposingWickRatio: wick, antiRunnerTriggered: antiRunner)
    }
}
