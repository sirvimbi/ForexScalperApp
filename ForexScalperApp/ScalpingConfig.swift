// ScalpingConfig.swift - GOD MODE V3.2 (ELITE DEFAULTS)
import Foundation
import Combine

@MainActor
class ScalpingConfig: ObservableObject {
    static let shared = ScalpingConfig()

    // Core settings - TUNED FOR 80%+ WIN RATE
    @Published var confidenceThreshold: Double = 65.0 { didSet { saveConfig() } }
    @Published var spreadTolerance: Double = 5.0 { didSet { saveConfig() } } // Tighter
    @Published var rsiWeight: Double = 15.0 { didSet { saveConfig() } }

    // Advanced settings
    @Published var stochasticWeight: Double = 15.0 { didSet { saveConfig() } }
    @Published var cciWeight: Double = 10.0 { didSet { saveConfig() } }
    @Published var maWeight: Double = 20.0 { didSet { saveConfig() } }
    @Published var bbWeight: Double = 10.0 { didSet { saveConfig() } }
    @Published var volumeWeight: Double = 10.0 { didSet { saveConfig() } }
    @Published var patternWeight: Double = 10.0 { didSet { saveConfig() } }

    // Exit strategy settings
    @Published var enableTrailingStop: Bool = true { didSet { saveConfig() } }
    @Published var trailActivationPips: Double = 15.0 { didSet { saveConfig() } } // Earlier activation
    @Published var trailDistance: Double = 8.0 { didSet { saveConfig() } } // Tighter trail
    @Published var maxHoldMinutes: Double = 30.0 { didSet { saveConfig() } }
    @Published var enableIndicatorExit: Bool = true { didSet { saveConfig() } }

    // Risk settings
    @Published var minScore: Double = 35.0 { didSet { saveConfig() } } // Lowered for more signals
    @Published var maxSpreadBps: Double = 5.0 { didSet { saveConfig() } }
    @Published var cooldownSeconds: Double = 45.0 { didSet { saveConfig() } } // Shorter for scalping
    @Published var maxDailyTrades: Int = 15 { didSet { saveConfig() } }
    @Published var maxConcurrentScalps: Int = 3 { didSet { saveConfig() } }

    // Confluence settings
    @Published var mandatoryConfluenceLevel: Int = 2 { didSet { saveConfig() } }
    @Published var minConfluencePillars: Double = 2.0 { didSet { saveConfig() } } // Elite requirement (2 of 7)

    @Published var minVolatilityATR: Double = 0.005 { didSet { saveConfig() } } // 0.5% (was 0.05)
    @Published var minVolumeRatio: Double = 0.8 { didSet { saveConfig() } }

    // News Filter settings
    @Published var enableNewsFilter: Bool = true { didSet { saveConfig() } }
    @Published var pauseBeforeHighImpactMinutes: Double = 60.0 { didSet { saveConfig() } }
    @Published var pauseBeforeMediumImpactMinutes: Double = 30.0 { didSet { saveConfig() } }
    @Published var autoRaiseSpreadDuringNews: Bool = true { didSet { saveConfig() } }
    @Published var newsSpreadMultiplier: Double = 3.0 { didSet { saveConfig() } }

    // Broker Suffix (e.g. 'm' for Exness Real)
    @Published var brokerSuffix: String = "m" { didSet { saveConfig() } }

    // Manual Volume/Lot settings
    @Published var useManualLot: Bool = false { didSet { saveConfig() } }
    @Published var manualLotSize: Double = 0.01 { didSet { saveConfig() } }

    // MARK: - Symbol-Specific Confidence Threshold
    @Published var symbolConfidenceThresholds: [String: Double] = [
        "EURUSD": 65.0,
        "USDJPY": 60.0,
        "EURJPY": 60.0,
        "CADJPY": 60.0,
        "NZDJPY": 60.0,
        "GBPUSD": 65.0,
        "AUDUSD": 65.0,
        "USDCAD": 65.0,
        "NZDUSD": 65.0,
        "EURGBP": 70.0,
        "EURCHF": 70.0,
        "GBPCHF": 70.0,
        "CHFJPY": 70.0,
        "AUDCHF": 70.0,
        "NZDCAD": 70.0,
        "AUDNZD": 70.0
    ] { didSet { saveConfig() } }

    private let savePath: URL

    init() {
        savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scalping_config.json")
        
        if !FileManager.default.fileExists(atPath: savePath.path) {
            setGodModeDefaults()
        } else {
            loadConfig()
        }
    }

    func setGodModeDefaults() {
        confidenceThreshold = 65.0
        spreadTolerance = 5.0
        minScore = 35.0
        cooldownSeconds = 45.0
        minVolatilityATR = 0.005
        minVolumeRatio = 0.8
        mandatoryConfluenceLevel = 2
        minConfluencePillars = 2.0
        enableTrailingStop = true
        trailActivationPips = 15
        trailDistance = 8
        maxDailyTrades = 15
        maxConcurrentScalps = 3
        enableNewsFilter = true
        brokerSuffix = "m"
        
        symbolConfidenceThresholds = [
            "EURUSD": 65.0,
            "USDJPY": 60.0,
            "EURJPY": 60.0,
            "CADJPY": 60.0,
            "NZDJPY": 60.0,
            "GBPUSD": 65.0,
            "AUDUSD": 65.0,
            "USDCAD": 65.0,
            "NZDUSD": 65.0,
            "EURGBP": 70.0,
            "EURCHF": 70.0,
            "GBPCHF": 70.0,
            "CHFJPY": 70.0,
            "AUDCHF": 70.0,
            "NZDCAD": 70.0,
            "AUDNZD": 70.0
        ]
        
        saveConfig()
        godLog("🚀 God Mode Optimized Defaults Applied", level: .success)
    }

    func getConfidenceThreshold(for symbol: String) -> Double {
        let normalizedSymbol = normalizeSymbol(symbol)
        return symbolConfidenceThresholds[normalizedSymbol] ?? confidenceThreshold
    }

    private func normalizeSymbol(_ symbol: String) -> String {
        var normalized = symbol.replacingOccurrences(of: "m", with: "")
        if let dotIndex = normalized.firstIndex(of: ".") {
            normalized = String(normalized[..<dotIndex])
        }
        return normalized
    }

    func saveConfig() {
        let config = ConfigData(
            confidenceThreshold: confidenceThreshold, spreadTolerance: spreadTolerance,
            rsiWeight: rsiWeight, stochasticWeight: stochasticWeight, cciWeight: cciWeight,
            maWeight: maWeight, bbWeight: bbWeight, volumeWeight: volumeWeight,
            patternWeight: patternWeight, enableTrailingStop: enableTrailingStop,
            trailActivationPips: trailActivationPips, trailDistance: trailDistance,
            maxHoldMinutes: maxHoldMinutes, enableIndicatorExit: enableIndicatorExit,
            minScore: minScore, maxSpreadBps: maxSpreadBps, cooldownSeconds: cooldownSeconds,
            maxDailyTrades: maxDailyTrades, maxConcurrentScalps: maxConcurrentScalps,
            mandatoryConfluenceLevel: mandatoryConfluenceLevel,
            minConfluencePillars: minConfluencePillars,
            minVolumeRatio: minVolumeRatio,
            useManualLot: useManualLot, manualLotSize: manualLotSize,
            symbolConfidenceThresholds: symbolConfidenceThresholds,
            minVolatilityATR: minVolatilityATR,
            enableNewsFilter: enableNewsFilter,
            pauseBeforeHighImpactMinutes: pauseBeforeHighImpactMinutes,
            pauseBeforeMediumImpactMinutes: pauseBeforeMediumImpactMinutes,
            autoRaiseSpreadDuringNews: autoRaiseSpreadDuringNews,
            newsSpreadMultiplier: newsSpreadMultiplier,
            brokerSuffix: brokerSuffix
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: savePath)
        } catch {
            print("❌ Failed to save scalping config: \(error)")
        }
    }

    private func loadConfig() {
        do {
            let data = try Data(contentsOf: savePath)
            let decoder = JSONDecoder()
            let config = try decoder.decode(ConfigData.self, from: data)
            self.confidenceThreshold = config.confidenceThreshold
            self.spreadTolerance = config.spreadTolerance
            self.rsiWeight = config.rsiWeight
            self.stochasticWeight = config.stochasticWeight
            self.cciWeight = config.cciWeight
            self.maWeight = config.maWeight
            self.bbWeight = config.bbWeight
            self.volumeWeight = config.volumeWeight
            self.patternWeight = config.patternWeight
            self.enableTrailingStop = config.enableTrailingStop
            self.trailActivationPips = config.trailActivationPips
            self.trailDistance = config.trailDistance
            self.maxHoldMinutes = config.maxHoldMinutes
            self.enableIndicatorExit = config.enableIndicatorExit
            self.minScore = config.minScore
            self.maxSpreadBps = config.maxSpreadBps
            self.cooldownSeconds = config.cooldownSeconds
            self.maxDailyTrades = config.maxDailyTrades
            self.maxConcurrentScalps = config.maxConcurrentScalps
            self.mandatoryConfluenceLevel = config.mandatoryConfluenceLevel
            self.minConfluencePillars = config.minConfluencePillars ?? 2.0
            self.minVolumeRatio = config.minVolumeRatio ?? 0.8
            self.useManualLot = config.useManualLot ?? false
            self.manualLotSize = config.manualLotSize ?? 0.01
            self.minVolatilityATR = config.minVolatilityATR ?? 0.005
            self.enableNewsFilter = config.enableNewsFilter ?? true
            self.pauseBeforeHighImpactMinutes = config.pauseBeforeHighImpactMinutes ?? 60.0
            self.pauseBeforeMediumImpactMinutes = config.pauseBeforeMediumImpactMinutes ?? 30.0
            self.autoRaiseSpreadDuringNews = config.autoRaiseSpreadDuringNews ?? true
            self.newsSpreadMultiplier = config.newsSpreadMultiplier ?? 3.0
            self.brokerSuffix = config.brokerSuffix ?? "m"
            self.symbolConfidenceThresholds = config.symbolConfidenceThresholds ?? [:]
        } catch {
            print("📝 Loading defaults (first run or corrupt file)")
            setGodModeDefaults()
        }
    }

    func resetToDefaults() {
        setGodModeDefaults()
    }

    private struct ConfigData: Codable {
        let confidenceThreshold: Double; let spreadTolerance: Double; let rsiWeight: Double
        let stochasticWeight: Double; let cciWeight: Double; let maWeight: Double
        let bbWeight: Double; let volumeWeight: Double; let patternWeight: Double
        let enableTrailingStop: Bool; let trailActivationPips: Double; let trailDistance: Double
        let maxHoldMinutes: Double; let enableIndicatorExit: Bool; let minScore: Double
        let maxSpreadBps: Double; let cooldownSeconds: Double; let maxDailyTrades: Int
        let maxConcurrentScalps: Int
        let mandatoryConfluenceLevel: Int
        let minConfluencePillars: Double?
        let minVolumeRatio: Double?
        let useManualLot: Bool?
        let manualLotSize: Double?
        let symbolConfidenceThresholds: [String: Double]?
        let minVolatilityATR: Double?
        let enableNewsFilter: Bool?
        let pauseBeforeHighImpactMinutes: Double?
        let pauseBeforeMediumImpactMinutes: Double?
        let autoRaiseSpreadDuringNews: Bool?
        let newsSpreadMultiplier: Double?
        let brokerSuffix: String?
    }
}
