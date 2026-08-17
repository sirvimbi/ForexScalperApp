import Foundation

/// Persisted runner-continuation controls. Values are bounded before reaching the
/// execution gate so a malformed or stale preference cannot weaken safety limits.
struct RunnerContinuationSettings: Codable, Sendable {
    var enabled: Bool
    var candleLookback: Int
    var minimumAlignedCandles: Int
    var requireLatestCandleAlignment: Bool
    var requireProgressiveCloses: Bool
    var minimumBodyToRangeRatio: Double
    var maximumOpposingWickToBodyRatio: Double
    var minimumAccelerationRatio: Double
    var maximumBreakoutExtensionATR: Double
    var antiRunnerRangeMultiplier: Double
    var antiRunnerWickRatio: Double
    var atrLookback: Int

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "runner.enabled") as? Bool ?? true
        candleLookback = defaults.object(forKey: "runner.candleLookback") as? Int ?? 4
        minimumAlignedCandles = defaults.object(forKey: "runner.minimumAlignedCandles") as? Int ?? 3
        requireLatestCandleAlignment = defaults.object(forKey: "runner.requireLatestCandleAlignment") as? Bool ?? true
        requireProgressiveCloses = defaults.object(forKey: "runner.requireProgressiveCloses") as? Bool ?? false
        minimumBodyToRangeRatio = defaults.object(forKey: "runner.minimumBodyToRangeRatio") as? Double ?? 0.45
        maximumOpposingWickToBodyRatio = defaults.object(forKey: "runner.maximumOpposingWickToBodyRatio") as? Double ?? 0.75
        minimumAccelerationRatio = defaults.object(forKey: "runner.minimumAccelerationRatio") as? Double ?? 1.05
        maximumBreakoutExtensionATR = defaults.object(forKey: "runner.maximumBreakoutExtensionATR") as? Double ?? 0.80
        antiRunnerRangeMultiplier = defaults.object(forKey: "runner.antiRunnerRangeMultiplier") as? Double ?? 1.80
        antiRunnerWickRatio = defaults.object(forKey: "runner.antiRunnerWickRatio") as? Double ?? 1.25
        atrLookback = defaults.object(forKey: "runner.atrLookback") as? Int ?? 14
    }

    init(configuration: RunnerContinuationConfiguration) {
        enabled = configuration.enabled
        candleLookback = configuration.candleLookback
        minimumAlignedCandles = configuration.minimumAlignedCandles
        requireLatestCandleAlignment = configuration.requireLatestCandleAlignment
        requireProgressiveCloses = configuration.requireProgressiveCloses
        minimumBodyToRangeRatio = configuration.minimumBodyToRangeRatio
        maximumOpposingWickToBodyRatio = configuration.maximumOpposingWickToBodyRatio
        minimumAccelerationRatio = configuration.minimumAccelerationRatio
        maximumBreakoutExtensionATR = configuration.maximumBreakoutExtensionATR
        antiRunnerRangeMultiplier = configuration.antiRunnerRangeMultiplier
        antiRunnerWickRatio = configuration.antiRunnerWickRatio
        atrLookback = configuration.atrLookback
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "runner.enabled")
        defaults.set(candleLookback, forKey: "runner.candleLookback")
        defaults.set(minimumAlignedCandles, forKey: "runner.minimumAlignedCandles")
        defaults.set(requireLatestCandleAlignment, forKey: "runner.requireLatestCandleAlignment")
        defaults.set(requireProgressiveCloses, forKey: "runner.requireProgressiveCloses")
        defaults.set(minimumBodyToRangeRatio, forKey: "runner.minimumBodyToRangeRatio")
        defaults.set(maximumOpposingWickToBodyRatio, forKey: "runner.maximumOpposingWickToBodyRatio")
        defaults.set(minimumAccelerationRatio, forKey: "runner.minimumAccelerationRatio")
        defaults.set(maximumBreakoutExtensionATR, forKey: "runner.maximumBreakoutExtensionATR")
        defaults.set(antiRunnerRangeMultiplier, forKey: "runner.antiRunnerRangeMultiplier")
        defaults.set(antiRunnerWickRatio, forKey: "runner.antiRunnerWickRatio")
        defaults.set(atrLookback, forKey: "runner.atrLookback")
    }

    var validated: RunnerContinuationConfiguration {
        let lookback = min(max(candleLookback, 2), 8)
        return RunnerContinuationConfiguration(
            enabled: enabled,
            candleLookback: lookback,
            minimumAlignedCandles: min(max(minimumAlignedCandles, 2), lookback),
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
