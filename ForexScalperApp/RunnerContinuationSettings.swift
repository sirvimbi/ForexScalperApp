import Foundation

/// User-configurable runner filter settings. Values are intentionally bounded
/// when consumed by the signal engine so invalid persisted values cannot weaken
/// the safety gate unexpectedly.
struct RunnerContinuationSettings: Codable, Sendable {
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

    var validated: RunnerContinuationConfiguration {
        RunnerContinuationConfiguration(
            enabled: enabled,
            candleLookback: min(max(candleLookback, 2), 8),
            minimumAlignedCandles: min(max(minimumAlignedCandles, 2), min(max(candleLookback, 2), 8)),
            requireLatestCandleAlignment: requireLatestCandleAlignment,
            requireProgressiveCloses: requireProgressiveCloses,
            minimumBodyToRangeRatio: min(max(minimumBodyToRangeRatio, 0.20), 0.90),
            maximumOpposingWickToBodyRatio: min(max(maximumOpposingWickToBodyRatio, 0.20), 2.0),
            minimumAccelerationRatio: min(max(minimumAccelerationRatio, 1.0), 3.0),
            maximumBreakoutExtensionATR: min(max(maximumBreakoutExtensionATR, 0.20), 3.0),
            antiRunnerRangeMultiplier: min(max(antiRunnerRangeMultiplier, 1.20), 3.0),
            antiRunnerWickRatio: min(max(antiRunnerWickRatio, 0.50), 3.0),
            atrLookback: min(max(atrLookback, 5), 50)
        )
    }
}
