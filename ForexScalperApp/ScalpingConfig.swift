// ScalpingConfig.swift - GOD MODE V7.0 ELITE
import Foundation
import Combine

@MainActor
class ScalpingConfig: ObservableObject {
    static let shared = ScalpingConfig()

    // MARK: - CORE SETTINGS (Optimized for 85%+ Win Rate)
    @Published var confidenceThreshold: Double = 78.0
    @Published var spreadTolerance: Double = 1.5
    @Published var minScore: Double = 70.0
    @Published var cooldownSeconds: Double = 60.0

    // MARK: - ENTRY FILTERS (ELITE)
    @Published var minVolatilityATR: Double = 0.006
    @Published var minVolumeRatio: Double = 1.5
    @Published var mandatoryConfluenceLevel: Int = 2
    @Published var minConfluencePillars: Double = 3.0

    // MARK: - EXIT OPTIMIZATION
    @Published var fixedSLPips: Double = 30.0
    @Published var maxHoldMinutes: Double = 20.0
    @Published var enableIndicatorExit: Bool = true

    // MARK: - RISK SETTINGS
    @Published var maxDailyTrades: Int = 8
    @Published var maxConcurrentScalps: Int = 2
    @Published var maxCorrelatedTrades: Int = 1
    @Published var enableHourlyLimit: Bool = true
    @Published var maxHourlyTrades: Int = 3
    @Published var enableRRCheck: Bool = true
    @Published var minRRRatio: Double = 1.5

    // MARK: - STOP LOSS
    @Published var useFixedSL: Bool = true
    @Published var baseSLPips: Double = 30.0

    // MARK: - TAKE PROFIT
    @Published var baseTPPips: Double = 12.0
    @Published var maxTPPips: Double = 25.0
    @Published var minTPPips: Double = 8.0
    @Published var partialTPPercent: Double = 0.50

    // MARK: - SESSION SETTINGS
    var sessionMultipliers: [String: SessionMultiplier] = [
        "Asian": SessionMultiplier(confidence: 1.15, sl: 0.8, tp: 0.8, spread: 1.2),
        "London": SessionMultiplier(confidence: 1.0, sl: 1.0, tp: 1.0, spread: 1.5),
        "US": SessionMultiplier(confidence: 0.9, sl: 1.2, tp: 1.2, spread: 2.0)
    ]

    struct SymbolConfig {
        let minConfidence: Double
        let baseSL: Double
        let baseTP: Double
        let maxSpread: Double
    }

    struct SessionMultiplier {
        let confidence: Double
        let sl: Double
        let tp: Double
        let spread: Double
    }

    // MARK: - BROKER
    @Published var brokerSuffix: String = "m"
    @Published var useManualLot: Bool = false
    @Published var manualLotSize: Double = 0.01

    // MARK: - NEWS FILTER
    @Published var enableNewsFilter: Bool = true
    @Published var pauseBeforeHighImpactMinutes: Double = 60.0
    @Published var pauseBeforeMediumImpactMinutes: Double = 30.0
    @Published var autoRaiseSpreadDuringNews: Bool = true
    @Published var newsSpreadMultiplier: Double = 2.0

    // MARK: - ELITE PRECISION (V10.0)
    @Published var enableOrderFlowFilter: Bool = true
    @Published var orderFlowThreshold: Double = 50.0
    @Published var enablePullbackEntry: Bool = true
    @Published var pullbackEMAPeriod: Int = 21
    @Published var pullbackFVGWeight: Double = 10.0
    @Published var rocPeriod: Int = 1
    @Published var enableMLTrendFilter: Bool = true
    @Published var mlConfidenceThreshold: Double = 0.7
    @Published var enableSwingSL: Bool = true
    @Published var swingLookback: Int = 20
    @Published var volatilityMultiplierMin: Double = 0.5
    @Published var volatilityMultiplierMax: Double = 1.5

    // MARK: - STRATEGY WEIGHTS (V10.0 Zero Hardcoding)
    @Published var weightHTFAlignment: Double = 25.0
    @Published var weightMomentumExhaustion: Double = 15.0
    @Published var weightVolumeSurge: Double = 12.0
    @Published var weightEMAStack: Double = 18.0
    @Published var weightBollingerRejection: Double = 10.0
    @Published var weightCCICycle: Double = 10.0
    @Published var weightSARTrend: Double = 10.0
    @Published var weightMomentumSurge: Double = 12.0
    @Published var weightOrderFlow: Double = 15.0
    @Published var weightMLConfirmed: Double = 10.0

    // MARK: - PARTIAL TAKE PROFIT (50/30/20)
    @Published var partialTP1_Percent: Double = 0.50
    @Published var partialTP1_Pips: Double = 10.0
    @Published var partialTP2_Percent: Double = 0.30
    @Published var partialTP2_Pips: Double = 15.0
    @Published var partialTP3_Percent: Double = 0.20
    @Published var partialTP3_Pips: Double = 20.0

    // MARK: - RUNNER CONTINUATION / ANTI-EXHAUSTION
    @Published var enableRunnerContinuation: Bool = true
    @Published var runnerCandleLookback: Int = 4
    @Published var runnerMinimumAlignedCandles: Int = 3
    @Published var runnerRequireLatestCandleAlignment: Bool = true
    @Published var runnerRequireProgressiveCloses: Bool = false
    @Published var runnerMinimumBodyToRangeRatio: Double = 0.45
    @Published var runnerMaximumOpposingWickToBodyRatio: Double = 0.75
    @Published var runnerMinimumAccelerationRatio: Double = 1.05
    @Published var runnerMaximumBreakoutExtensionATR: Double = 0.80
    @Published var runnerAntiRunnerRangeMultiplier: Double = 1.80
    @Published var runnerAntiRunnerWickRatio: Double = 1.25
    @Published var runnerATRLookback: Int = 14

    var runnerContinuationConfiguration: RunnerContinuationConfiguration {
        RunnerContinuationConfiguration(
            enabled: enableRunnerContinuation,
            candleLookback: runnerCandleLookback,
            minimumAlignedCandles: runnerMinimumAlignedCandles,
            requireLatestCandleAlignment: runnerRequireLatestCandleAlignment,
            requireProgressiveCloses: runnerRequireProgressiveCloses,
            minimumBodyToRangeRatio: runnerMinimumBodyToRangeRatio,
            maximumOpposingWickToBodyRatio: runnerMaximumOpposingWickToBodyRatio,
            minimumAccelerationRatio: runnerMinimumAccelerationRatio,
            maximumBreakoutExtensionATR: runnerMaximumBreakoutExtensionATR,
            antiRunnerRangeMultiplier: runnerAntiRunnerRangeMultiplier,
            antiRunnerWickRatio: runnerAntiRunnerWickRatio,
            atrLookback: runnerATRLookback
        )
    }

    private let savePath: URL

    init() {
        savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scalping_config.json")
        loadConfig()
    }

    func getConfidenceThreshold(for symbol: String) -> Double { confidenceThreshold }

    func getSymbolConfig(_ symbol: String) -> SymbolConfig {
        SymbolConfig(minConfidence: confidenceThreshold, baseSL: baseSLPips, baseTP: baseTPPips, maxSpread: spreadTolerance)
    }

    func getSessionMultiplier() -> SessionMultiplier {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 0 && hour < 8 { return sessionMultipliers["Asian"] ?? SessionMultiplier(confidence: 1.0, sl: 1.0, tp: 1.0, spread: 1.0) }
        if hour >= 8 && hour < 16 { return sessionMultipliers["London"] ?? SessionMultiplier(confidence: 1.0, sl: 1.0, tp: 1.0, spread: 1.0) }
        return sessionMultipliers["US"] ?? SessionMultiplier(confidence: 1.0, sl: 1.0, tp: 1.0, spread: 1.0)
    }

    private func normalizeSymbol(_ symbol: String) -> String {
        var normalized = symbol.replacingOccurrences(of: "m", with: "")
        if let dotIndex = normalized.firstIndex(of: ".") { normalized = String(normalized[..<dotIndex]) }
        return normalized
    }

    private func loadConfig() {
        do {
            let data = try Data(contentsOf: savePath)
            let config = try JSONDecoder().decode(ConfigData.self, from: data)
            confidenceThreshold = config.confidenceThreshold
            spreadTolerance = config.spreadTolerance
            minScore = config.minScore
            cooldownSeconds = config.cooldownSeconds
            minVolatilityATR = config.minVolatilityATR
            minVolumeRatio = config.minVolumeRatio
            mandatoryConfluenceLevel = config.mandatoryConfluenceLevel
            minConfluencePillars = config.minConfluencePillars
            maxHoldMinutes = config.maxHoldMinutes
            enableIndicatorExit = config.enableIndicatorExit
            maxDailyTrades = config.maxDailyTrades
            maxConcurrentScalps = config.maxConcurrentScalps
            enableHourlyLimit = config.enableHourlyLimit ?? true
            maxHourlyTrades = config.maxHourlyTrades ?? 3
            enableRRCheck = config.enableRRCheck ?? true
            minRRRatio = config.minRRRatio ?? 1.5
            fixedSLPips = config.fixedSLPips ?? 30.0
            useFixedSL = config.useFixedSL ?? true
            baseSLPips = config.baseSLPips
            baseTPPips = config.baseTPPips
            maxTPPips = config.maxTPPips
            minTPPips = config.minTPPips
            partialTPPercent = config.partialTPPercent
            brokerSuffix = config.brokerSuffix ?? "m"
            manualLotSize = config.manualLotSize ?? 0.01
            enableNewsFilter = config.enableNewsFilter ?? true
            autoRaiseSpreadDuringNews = config.autoRaiseSpreadDuringNews ?? true
            newsSpreadMultiplier = config.newsSpreadMultiplier ?? 2.0
            enableOrderFlowFilter = config.enableOrderFlowFilter ?? true
            orderFlowThreshold = config.orderFlowThreshold ?? 50.0
            enablePullbackEntry = config.enablePullbackEntry ?? true
            pullbackEMAPeriod = config.pullbackEMAPeriod ?? 21
            pullbackFVGWeight = config.pullbackFVGWeight ?? 10.0
            rocPeriod = config.rocPeriod ?? 1
            enableMLTrendFilter = config.enableMLTrendFilter ?? true
            mlConfidenceThreshold = config.mlConfidenceThreshold ?? 0.7
            enableSwingSL = config.enableSwingSL ?? true
            swingLookback = config.swingLookback ?? 20
            volatilityMultiplierMin = config.volatilityMultiplierMin ?? 0.5
            volatilityMultiplierMax = config.volatilityMultiplierMax ?? 1.5
            weightHTFAlignment = config.weightHTFAlignment ?? 25.0
            weightMomentumExhaustion = config.weightMomentumExhaustion ?? 15.0
            weightVolumeSurge = config.weightVolumeSurge ?? 12.0
            weightEMAStack = config.weightEMAStack ?? 18.0
            weightBollingerRejection = config.weightBollingerRejection ?? 10.0
            weightCCICycle = config.weightCCICycle ?? 10.0
            weightSARTrend = config.weightSARTrend ?? 10.0
            weightMomentumSurge = config.weightMomentumSurge ?? 12.0
            weightOrderFlow = config.weightOrderFlow ?? 15.0
            weightMLConfirmed = config.weightMLConfirmed ?? 10.0
            partialTP1_Percent = config.partialTP1_Percent ?? 0.50
            partialTP1_Pips = config.partialTP1_Pips ?? 10.0
            partialTP2_Percent = config.partialTP2_Percent ?? 0.30
            partialTP2_Pips = config.partialTP2_Pips ?? 15.0
            partialTP3_Percent = config.partialTP3_Percent ?? 0.20
            partialTP3_Pips = config.partialTP3_Pips ?? 20.0
            enableRunnerContinuation = config.enableRunnerContinuation ?? true
            runnerCandleLookback = min(max(config.runnerCandleLookback ?? 4, 2), 8)
            runnerMinimumAlignedCandles = min(max(config.runnerMinimumAlignedCandles ?? 3, 2), runnerCandleLookback)
            runnerRequireLatestCandleAlignment = config.runnerRequireLatestCandleAlignment ?? true
            runnerRequireProgressiveCloses = config.runnerRequireProgressiveCloses ?? false
            runnerMinimumBodyToRangeRatio = min(max(config.runnerMinimumBodyToRangeRatio ?? 0.45, 0.05), 0.95)
            runnerMaximumOpposingWickToBodyRatio = max(config.runnerMaximumOpposingWickToBodyRatio ?? 0.75, 0.0)
            runnerMinimumAccelerationRatio = max(config.runnerMinimumAccelerationRatio ?? 1.05, 0.0)
            runnerMaximumBreakoutExtensionATR = max(config.runnerMaximumBreakoutExtensionATR ?? 0.80, 0.0)
            runnerAntiRunnerRangeMultiplier = max(config.runnerAntiRunnerRangeMultiplier ?? 1.80, 1.0)
            runnerAntiRunnerWickRatio = max(config.runnerAntiRunnerWickRatio ?? 1.25, 0.0)
            runnerATRLookback = min(max(config.runnerATRLookback ?? 14, 5), 100)
        } catch { saveConfig() }
    }

    func saveConfig() {
        let config = ConfigData(
            confidenceThreshold: confidenceThreshold, spreadTolerance: spreadTolerance, minScore: minScore, cooldownSeconds: cooldownSeconds,
            minVolatilityATR: minVolatilityATR, minVolumeRatio: minVolumeRatio, mandatoryConfluenceLevel: mandatoryConfluenceLevel,
            minConfluencePillars: minConfluencePillars, maxHoldMinutes: maxHoldMinutes, enableIndicatorExit: enableIndicatorExit,
            maxDailyTrades: maxDailyTrades, maxConcurrentScalps: maxConcurrentScalps, enableHourlyLimit: enableHourlyLimit,
            maxHourlyTrades: maxHourlyTrades, enableRRCheck: enableRRCheck, minRRRatio: minRRRatio, fixedSLPips: fixedSLPips,
            useFixedSL: useFixedSL, baseSLPips: baseSLPips, baseTPPips: baseTPPips, maxTPPips: maxTPPips, minTPPips: minTPPips,
            partialTPPercent: partialTPPercent, brokerSuffix: brokerSuffix, manualLotSize: manualLotSize, enableNewsFilter: enableNewsFilter,
            autoRaiseSpreadDuringNews: autoRaiseSpreadDuringNews, newsSpreadMultiplier: newsSpreadMultiplier,
            enableOrderFlowFilter: enableOrderFlowFilter, orderFlowThreshold: orderFlowThreshold, enablePullbackEntry: enablePullbackEntry,
            pullbackEMAPeriod: pullbackEMAPeriod, pullbackFVGWeight: pullbackFVGWeight, rocPeriod: rocPeriod,
            enableMLTrendFilter: enableMLTrendFilter, mlConfidenceThreshold: mlConfidenceThreshold, enableSwingSL: enableSwingSL,
            swingLookback: swingLookback, volatilityMultiplierMin: volatilityMultiplierMin, volatilityMultiplierMax: volatilityMultiplierMax,
            weightHTFAlignment: weightHTFAlignment, weightMomentumExhaustion: weightMomentumExhaustion, weightVolumeSurge: weightVolumeSurge,
            weightEMAStack: weightEMAStack, weightBollingerRejection: weightBollingerRejection, weightCCICycle: weightCCICycle,
            weightSARTrend: weightSARTrend, weightMomentumSurge: weightMomentumSurge, weightOrderFlow: weightOrderFlow, weightMLConfirmed: weightMLConfirmed,
            partialTP1_Percent: partialTP1_Percent, partialTP1_Pips: partialTP1_Pips, partialTP2_Percent: partialTP2_Percent,
            partialTP2_Pips: partialTP2_Pips, partialTP3_Percent: partialTP3_Percent, partialTP3_Pips: partialTP3_Pips,
            enableRunnerContinuation: enableRunnerContinuation, runnerCandleLookback: runnerCandleLookback,
            runnerMinimumAlignedCandles: runnerMinimumAlignedCandles, runnerRequireLatestCandleAlignment: runnerRequireLatestCandleAlignment,
            runnerRequireProgressiveCloses: runnerRequireProgressiveCloses, runnerMinimumBodyToRangeRatio: runnerMinimumBodyToRangeRatio,
            runnerMaximumOpposingWickToBodyRatio: runnerMaximumOpposingWickToBodyRatio, runnerMinimumAccelerationRatio: runnerMinimumAccelerationRatio,
            runnerMaximumBreakoutExtensionATR: runnerMaximumBreakoutExtensionATR, runnerAntiRunnerRangeMultiplier: runnerAntiRunnerRangeMultiplier,
            runnerAntiRunnerWickRatio: runnerAntiRunnerWickRatio, runnerATRLookback: runnerATRLookback
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(config).write(to: savePath)
        } catch { godLog("❌ Failed to save config: \(error)", level: .error) }
    }

    private struct ConfigData: Codable {
        let confidenceThreshold: Double
        let spreadTolerance: Double
        let minScore: Double
        let cooldownSeconds: Double
        let minVolatilityATR: Double
        let minVolumeRatio: Double
        let mandatoryConfluenceLevel: Int
        let minConfluencePillars: Double
        let maxHoldMinutes: Double
        let enableIndicatorExit: Bool
        let maxDailyTrades: Int
        let maxConcurrentScalps: Int
        let enableHourlyLimit: Bool?
        let maxHourlyTrades: Int?
        let enableRRCheck: Bool?
        let minRRRatio: Double?
        let fixedSLPips: Double?
        let useFixedSL: Bool?
        let baseSLPips: Double
        let baseTPPips: Double
        let maxTPPips: Double
        let minTPPips: Double
        let partialTPPercent: Double
        let brokerSuffix: String?
        let manualLotSize: Double?
        let enableNewsFilter: Bool?
        let autoRaiseSpreadDuringNews: Bool?
        let newsSpreadMultiplier: Double?
        let enableOrderFlowFilter: Bool?
        let orderFlowThreshold: Double?
        let enablePullbackEntry: Bool?
        let pullbackEMAPeriod: Int?
        let pullbackFVGWeight: Double?
        let rocPeriod: Int?
        let enableMLTrendFilter: Bool?
        let mlConfidenceThreshold: Double?
        let enableSwingSL: Bool?
        let swingLookback: Int?
        let volatilityMultiplierMin: Double?
        let volatilityMultiplierMax: Double?
        let weightHTFAlignment: Double?
        let weightMomentumExhaustion: Double?
        let weightVolumeSurge: Double?
        let weightEMAStack: Double?
        let weightBollingerRejection: Double?
        let weightCCICycle: Double?
        let weightSARTrend: Double?
        let weightMomentumSurge: Double?
        let weightOrderFlow: Double?
        let weightMLConfirmed: Double?
        let partialTP1_Percent: Double?
        let partialTP1_Pips: Double?
        let partialTP2_Percent: Double?
        let partialTP2_Pips: Double?
        let partialTP3_Percent: Double?
        let partialTP3_Pips: Double?
        let enableRunnerContinuation: Bool?
        let runnerCandleLookback: Int?
        let runnerMinimumAlignedCandles: Int?
        let runnerRequireLatestCandleAlignment: Bool?
        let runnerRequireProgressiveCloses: Bool?
        let runnerMinimumBodyToRangeRatio: Double?
        let runnerMaximumOpposingWickToBodyRatio: Double?
        let runnerMinimumAccelerationRatio: Double?
        let runnerMaximumBreakoutExtensionATR: Double?
        let runnerAntiRunnerRangeMultiplier: Double?
        let runnerAntiRunnerWickRatio: Double?
        let runnerATRLookback: Int?
    }
}