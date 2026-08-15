import Foundation
import SwiftUI
import Combine

struct SignalAccuracyConfiguration: Sendable, Equatable {
    var minimumHistoryCandles: Int = 60
    var choppinessPeriod: Int = 14
    var choppinessWarningThreshold: Double = 61.8
    var choppinessVetoThreshold: Double = 68.0
    var hurstTrendingThreshold: Double = 0.60
    var hurstMeanReversionThreshold: Double = 0.45
    var trendingRegimeAdjustment: Double = 3.0
    var meanReversionRegimeAdjustment: Double = 1.0
    var divergenceLookback: Int = 40
    var supportingDivergenceAdjustment: Double = 5.0
    var opposingDivergenceAdjustment: Double = -15.0
    var reversalConfirmedAdjustment: Double = 7.0
    var reversalWaitingTrendPenalty: Double = -3.0
    var reversalWaitingOtherPenalty: Double = -6.0
    var favorableSessionMultiplier: Double = 1.10
    var reducedSessionMultiplier: Double = 0.94
    var favorableSession1StartHour: Int = 7
    var favorableSession1EndHour: Int = 10
    var favorableSession2StartHour: Int = 13
    var favorableSession2EndHour: Int = 16
    var reducedSessionStartHour: Int = 22
    var reducedSessionEndHour: Int = 5
    var bayesianPriorWins: Double = 1.0
    var bayesianPriorLosses: Double = 1.0
    var bayesianAdjustmentScale: Double = 8.0
    var confidenceAdjustmentFloor: Double = -20.0
    var confidenceAdjustmentCeiling: Double = 12.0
    var divergenceRSIMargin: Double = 0.0

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key) }
    private static func int(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key) }

    static func load(from defaults: UserDefaults = .standard) -> SignalAccuracyConfiguration {
        var c = SignalAccuracyConfiguration()
        c.minimumHistoryCandles = max(20, int(defaults, "signalAccuracy.minimumHistoryCandles", c.minimumHistoryCandles))
        c.choppinessPeriod = max(5, int(defaults, "signalAccuracy.choppinessPeriod", c.choppinessPeriod))
        c.choppinessWarningThreshold = double(defaults, "signalAccuracy.choppinessWarningThreshold", c.choppinessWarningThreshold)
        c.choppinessVetoThreshold = double(defaults, "signalAccuracy.choppinessVetoThreshold", c.choppinessVetoThreshold)
        c.hurstTrendingThreshold = double(defaults, "signalAccuracy.hurstTrendingThreshold", c.hurstTrendingThreshold)
        c.hurstMeanReversionThreshold = double(defaults, "signalAccuracy.hurstMeanReversionThreshold", c.hurstMeanReversionThreshold)
        c.trendingRegimeAdjustment = double(defaults, "signalAccuracy.trendingRegimeAdjustment", c.trendingRegimeAdjustment)
        c.meanReversionRegimeAdjustment = double(defaults, "signalAccuracy.meanReversionRegimeAdjustment", c.meanReversionRegimeAdjustment)
        c.divergenceLookback = max(20, int(defaults, "signalAccuracy.divergenceLookback", c.divergenceLookback))
        c.supportingDivergenceAdjustment = double(defaults, "signalAccuracy.supportingDivergenceAdjustment", c.supportingDivergenceAdjustment)
        c.opposingDivergenceAdjustment = double(defaults, "signalAccuracy.opposingDivergenceAdjustment", c.opposingDivergenceAdjustment)
        c.reversalConfirmedAdjustment = double(defaults, "signalAccuracy.reversalConfirmedAdjustment", c.reversalConfirmedAdjustment)
        c.reversalWaitingTrendPenalty = double(defaults, "signalAccuracy.reversalWaitingTrendPenalty", c.reversalWaitingTrendPenalty)
        c.reversalWaitingOtherPenalty = double(defaults, "signalAccuracy.reversalWaitingOtherPenalty", c.reversalWaitingOtherPenalty)
        c.favorableSessionMultiplier = double(defaults, "signalAccuracy.favorableSessionMultiplier", c.favorableSessionMultiplier)
        c.reducedSessionMultiplier = double(defaults, "signalAccuracy.reducedSessionMultiplier", c.reducedSessionMultiplier)
        c.favorableSession1StartHour = min(23, max(0, int(defaults, "signalAccuracy.favorableSession1StartHour", c.favorableSession1StartHour)))
        c.favorableSession1EndHour = min(23, max(0, int(defaults, "signalAccuracy.favorableSession1EndHour", c.favorableSession1EndHour)))
        c.favorableSession2StartHour = min(23, max(0, int(defaults, "signalAccuracy.favorableSession2StartHour", c.favorableSession2StartHour)))
        c.favorableSession2EndHour = min(23, max(0, int(defaults, "signalAccuracy.favorableSession2EndHour", c.favorableSession2EndHour)))
        c.reducedSessionStartHour = min(23, max(0, int(defaults, "signalAccuracy.reducedSessionStartHour", c.reducedSessionStartHour)))
        c.reducedSessionEndHour = min(23, max(0, int(defaults, "signalAccuracy.reducedSessionEndHour", c.reducedSessionEndHour)))
        c.bayesianPriorWins = max(0.01, double(defaults, "signalAccuracy.bayesianPriorWins", c.bayesianPriorWins))
        c.bayesianPriorLosses = max(0.01, double(defaults, "signalAccuracy.bayesianPriorLosses", c.bayesianPriorLosses))
        c.bayesianAdjustmentScale = double(defaults, "signalAccuracy.bayesianAdjustmentScale", c.bayesianAdjustmentScale)
        c.confidenceAdjustmentFloor = double(defaults, "signalAccuracy.confidenceAdjustmentFloor", c.confidenceAdjustmentFloor)
        c.confidenceAdjustmentCeiling = double(defaults, "signalAccuracy.confidenceAdjustmentCeiling", c.confidenceAdjustmentCeiling)
        c.divergenceRSIMargin = max(0, double(defaults, "signalAccuracy.divergenceRSIMargin", c.divergenceRSIMargin))
        return c
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(minimumHistoryCandles, forKey: "signalAccuracy.minimumHistoryCandles")
        defaults.set(choppinessPeriod, forKey: "signalAccuracy.choppinessPeriod")
        defaults.set(choppinessWarningThreshold, forKey: "signalAccuracy.choppinessWarningThreshold")
        defaults.set(choppinessVetoThreshold, forKey: "signalAccuracy.choppinessVetoThreshold")
        defaults.set(hurstTrendingThreshold, forKey: "signalAccuracy.hurstTrendingThreshold")
        defaults.set(hurstMeanReversionThreshold, forKey: "signalAccuracy.hurstMeanReversionThreshold")
        defaults.set(trendingRegimeAdjustment, forKey: "signalAccuracy.trendingRegimeAdjustment")
        defaults.set(meanReversionRegimeAdjustment, forKey: "signalAccuracy.meanReversionRegimeAdjustment")
        defaults.set(divergenceLookback, forKey: "signalAccuracy.divergenceLookback")
        defaults.set(supportingDivergenceAdjustment, forKey: "signalAccuracy.supportingDivergenceAdjustment")
        defaults.set(opposingDivergenceAdjustment, forKey: "signalAccuracy.opposingDivergenceAdjustment")
        defaults.set(reversalConfirmedAdjustment, forKey: "signalAccuracy.reversalConfirmedAdjustment")
        defaults.set(reversalWaitingTrendPenalty, forKey: "signalAccuracy.reversalWaitingTrendPenalty")
        defaults.set(reversalWaitingOtherPenalty, forKey: "signalAccuracy.reversalWaitingOtherPenalty")
        defaults.set(favorableSessionMultiplier, forKey: "signalAccuracy.favorableSessionMultiplier")
        defaults.set(reducedSessionMultiplier, forKey: "signalAccuracy.reducedSessionMultiplier")
        defaults.set(favorableSession1StartHour, forKey: "signalAccuracy.favorableSession1StartHour")
        defaults.set(favorableSession1EndHour, forKey: "signalAccuracy.favorableSession1EndHour")
        defaults.set(favorableSession2StartHour, forKey: "signalAccuracy.favorableSession2StartHour")
        defaults.set(favorableSession2EndHour, forKey: "signalAccuracy.favorableSession2EndHour")
        defaults.set(reducedSessionStartHour, forKey: "signalAccuracy.reducedSessionStartHour")
        defaults.set(reducedSessionEndHour, forKey: "signalAccuracy.reducedSessionEndHour")
        defaults.set(bayesianPriorWins, forKey: "signalAccuracy.bayesianPriorWins")
        defaults.set(bayesianPriorLosses, forKey: "signalAccuracy.bayesianPriorLosses")
        defaults.set(bayesianAdjustmentScale, forKey: "signalAccuracy.bayesianAdjustmentScale")
        defaults.set(confidenceAdjustmentFloor, forKey: "signalAccuracy.confidenceAdjustmentFloor")
        defaults.set(confidenceAdjustmentCeiling, forKey: "signalAccuracy.confidenceAdjustmentCeiling")
        defaults.set(divergenceRSIMargin, forKey: "signalAccuracy.divergenceRSIMargin")
    }
}

/// Lock-protected runtime snapshot for the synchronous signal actor. This avoids crossing the
/// MainActor or UserDefaults reference into the hot signal path while still applying saved values immediately.
final class SignalAccuracyRuntimeCache: @unchecked Sendable {
    static let shared = SignalAccuracyRuntimeCache()
    private let lock = NSLock()
    private var configuration: SignalAccuracyConfiguration

    private init() { configuration = SignalAccuracyConfiguration.load() }

    func snapshot() -> SignalAccuracyConfiguration {
        lock.lock(); defer { lock.unlock() }
        return configuration
    }

    func update(_ configuration: SignalAccuracyConfiguration) {
        lock.lock(); self.configuration = configuration; lock.unlock()
    }
}

actor SignalAccuracySettingsStore {
    static let shared = SignalAccuracySettingsStore()
    func snapshot() -> SignalAccuracyConfiguration { SignalAccuracyConfiguration.load() }
}

@MainActor
final class SignalAccuracySettingsController: ObservableObject {
    @Published var values: SignalAccuracyConfiguration
    init() { values = SignalAccuracyRuntimeCache.shared.snapshot() }
    func reload() { values = SignalAccuracyConfiguration.load(); SignalAccuracyRuntimeCache.shared.update(values) }
    func save() {
        values.minimumHistoryCandles = max(20, values.minimumHistoryCandles)
        values.choppinessPeriod = max(5, values.choppinessPeriod)
        values.choppinessVetoThreshold = max(values.choppinessWarningThreshold, values.choppinessVetoThreshold)
        values.hurstMeanReversionThreshold = min(values.hurstTrendingThreshold, values.hurstMeanReversionThreshold)
        values.confidenceAdjustmentFloor = min(values.confidenceAdjustmentFloor, values.confidenceAdjustmentCeiling)
        values.divergenceLookback = max(values.divergenceLookback, 20)
        values.save()
        SignalAccuracyRuntimeCache.shared.update(values)
        godLog("🧠 ACCURACY SETTINGS | saved | chop=\(values.choppinessWarningThreshold)/\(values.choppinessVetoThreshold) H=\(values.hurstMeanReversionThreshold)/\(values.hurstTrendingThreshold) Bayesian scale=\(values.bayesianAdjustmentScale)", level: .success)
    }
}
