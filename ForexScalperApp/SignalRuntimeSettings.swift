import Foundation

/// Runtime controls for the signal/candle synchronization path.
/// These are operational settings, not strategy constants, and are persisted in UserDefaults.
struct SignalRuntimeSettings: Sendable, Equatable {
    var heartbeatEnabled: Bool = true
    var heartbeatIntervalSeconds: Double = 15.0
    var heartbeatCandleCount: Int = 2
    var minimumHistoryCandles: Int = 60

    static func load(from defaults: UserDefaults = .standard) -> SignalRuntimeSettings {
        var settings = SignalRuntimeSettings()
        settings.heartbeatEnabled = defaults.object(forKey: "signalRuntime.heartbeatEnabled") == nil
            ? settings.heartbeatEnabled
            : defaults.bool(forKey: "signalRuntime.heartbeatEnabled")
        settings.heartbeatIntervalSeconds = max(1, defaults.object(forKey: "signalRuntime.heartbeatIntervalSeconds") == nil
            ? settings.heartbeatIntervalSeconds
            : defaults.double(forKey: "signalRuntime.heartbeatIntervalSeconds"))
        settings.heartbeatCandleCount = max(1, defaults.object(forKey: "signalRuntime.heartbeatCandleCount") == nil
            ? settings.heartbeatCandleCount
            : defaults.integer(forKey: "signalRuntime.heartbeatCandleCount"))

        // Reuse the existing user-facing signal-accuracy setting when available.
        let configuredHistory = SignalAccuracyConfiguration.load(from: defaults).minimumHistoryCandles
        settings.minimumHistoryCandles = max(1, configuredHistory)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(heartbeatEnabled, forKey: "signalRuntime.heartbeatEnabled")
        defaults.set(heartbeatIntervalSeconds, forKey: "signalRuntime.heartbeatIntervalSeconds")
        defaults.set(heartbeatCandleCount, forKey: "signalRuntime.heartbeatCandleCount")
    }
}
