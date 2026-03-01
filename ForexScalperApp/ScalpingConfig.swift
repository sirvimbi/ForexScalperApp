// ScalpingConfig.swift - Optimized for High Win Rate
import Foundation
import Combine

@MainActor
class ScalpingConfig: ObservableObject {
    static let shared = ScalpingConfig()
    
    // Core settings - RAISED THRESHOLDS FOR QUALITY
    @Published var confidenceThreshold: Double = 75.0 { didSet { saveConfig() } } // Must be >75% confidence
    @Published var spreadTolerance: Double = 10.0 { didSet { saveConfig() } }
    @Published var rsiWeight: Double = 15.0 { didSet { saveConfig() } }
    
    // Advanced settings
    @Published var stochasticWeight: Double = 15.0 { didSet { saveConfig() } }
    @Published var cciWeight: Double = 10.0 { didSet { saveConfig() } }
    @Published var maWeight: Double = 20.0 { didSet { saveConfig() } }
    @Published var bbWeight: Double = 10.0 { didSet { saveConfig() } }
    @Published var volumeWeight: Double = 10.0 { didSet { saveConfig() } }
    @Published var patternWeight: Double = 5.0 { didSet { saveConfig() } }
    
    // Exit strategy settings
    @Published var enableTrailingStop: Bool = true { didSet { saveConfig() } }
    @Published var trailActivationPips: Double = 3.0 { didSet { saveConfig() } } // Activate sooner
    @Published var trailDistance: Double = 2.0 { didSet { saveConfig() } } // Tighter trail
    @Published var maxHoldMinutes: Double = 30.0 { didSet { saveConfig() } }
    @Published var enableIndicatorExit: Bool = true { didSet { saveConfig() } }
    
    // Risk settings
    @Published var minScore: Double = 50.0 { didSet { saveConfig() } } // Higher bar for entry
    @Published var maxSpreadBps: Double = 10.0 { didSet { saveConfig() } }
    @Published var cooldownSeconds: Double = 300.0 { didSet { saveConfig() } } // 5 min cooldown to prevent overtrading
    @Published var maxDailyTrades: Int = 10 { didSet { saveConfig() } } // Limit trades to only best ones
    @Published var maxConcurrentScalps: Int = 2 { didSet { saveConfig() } }
    
    private let savePath: URL
    
    init() {
        savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scalping_config.json")
        loadConfig()
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
            maxDailyTrades: maxDailyTrades, maxConcurrentScalps: maxConcurrentScalps
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
        } catch {
            print("📝 No existing scalping config, using HIGH QUALITY defaults")
        }
    }
    
    func resetToDefaults() {
        confidenceThreshold = 75.0
        minScore = 50.0
        cooldownSeconds = 300.0
        maxDailyTrades = 10
        saveConfig()
    }
    
    private struct ConfigData: Codable {
        let confidenceThreshold: Double; let spreadTolerance: Double; let rsiWeight: Double
        let stochasticWeight: Double; let cciWeight: Double; let maWeight: Double
        let bbWeight: Double; let volumeWeight: Double; let patternWeight: Double
        let enableTrailingStop: Bool; let trailActivationPips: Double; let trailDistance: Double
        let maxHoldMinutes: Double; let enableIndicatorExit: Bool; let minScore: Double
        let maxSpreadBps: Double; let cooldownSeconds: Double; let maxDailyTrades: Int
        let maxConcurrentScalps: Int
    }
}
