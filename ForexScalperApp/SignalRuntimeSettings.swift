import Foundation

/// Runtime controls for the signal/candle synchronization path.
/// These are operational settings, not strategy constants, and are persisted in UserDefaults.
struct SignalRuntimeSettings: Sendable, Equatable {
    var heartbeatEnabled: Bool = true
    var heartbeatIntervalSeconds: Double = 15.0
    var heartbeatCandleCount: Int = 2
    var minimumHistoryCandles: Int = 60
    var maxCachedCandles: Int = 3000
    var maxPersistedCandles: Int = 5000

    /// This is a pure UserDefaults snapshot and is intentionally nonisolated so the MT5 actor
    /// can read runtime settings without crossing the MainActor.
    nonisolated static func load(from defaults: UserDefaults = .standard) -> SignalRuntimeSettings {
        var settings = SignalRuntimeSettings()
        settings.heartbeatEnabled = defaults.object(forKey: "signalRuntime.heartbeatEnabled") == nil ? settings.heartbeatEnabled : defaults.bool(forKey: "signalRuntime.heartbeatEnabled")
        settings.heartbeatIntervalSeconds = max(1, defaults.object(forKey: "signalRuntime.heartbeatIntervalSeconds") == nil ? settings.heartbeatIntervalSeconds : defaults.double(forKey: "signalRuntime.heartbeatIntervalSeconds"))
        settings.heartbeatCandleCount = max(1, defaults.object(forKey: "signalRuntime.heartbeatCandleCount") == nil ? settings.heartbeatCandleCount : defaults.integer(forKey: "signalRuntime.heartbeatCandleCount"))
        settings.maxCachedCandles = max(100, defaults.object(forKey: "signalRuntime.maxCachedCandles") == nil ? settings.maxCachedCandles : defaults.integer(forKey: "signalRuntime.maxCachedCandles"))
        settings.maxPersistedCandles = max(100, defaults.object(forKey: "signalRuntime.maxPersistedCandles") == nil ? settings.maxPersistedCandles : defaults.integer(forKey: "signalRuntime.maxPersistedCandles"))

        // Read the persisted accuracy history directly. SignalAccuracyConfiguration.load is
        // intentionally kept out of this hot actor path so Swift 6 cannot infer MainActor
        // isolation through the Settings/UI layer.
        let configuredHistory = defaults.object(forKey: "signalAccuracy.minimumHistoryCandles") == nil
            ? settings.minimumHistoryCandles
            : defaults.integer(forKey: "signalAccuracy.minimumHistoryCandles")
        settings.minimumHistoryCandles = max(1, configuredHistory)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(heartbeatEnabled, forKey: "signalRuntime.heartbeatEnabled")
        defaults.set(heartbeatIntervalSeconds, forKey: "signalRuntime.heartbeatIntervalSeconds")
        defaults.set(heartbeatCandleCount, forKey: "signalRuntime.heartbeatCandleCount")
        defaults.set(maxCachedCandles, forKey: "signalRuntime.maxCachedCandles")
        defaults.set(maxPersistedCandles, forKey: "signalRuntime.maxPersistedCandles")
    }
}