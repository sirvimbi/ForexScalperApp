// CorrelationFilter.swift - GOD MODE CORRELATION MANAGEMENT
import Foundation

actor CorrelationFilter {
    static let shared = CorrelationFilter()
    
    // 📊 MT5-SPECIFIC CORRELATION MATRIX
    private let correlationThreshold: Double = 0.70 // 70% correlation = block
    private var activeSymbols: Set<String> = []
    private var symbolCorrelations: [String: [String: Double]] = [:]
    private var lastUpdate: Date = Date()
    private let updateInterval: TimeInterval = 300 // 5 minutes
    
    // 🎯 PAIR GROUPS - Never trade these together
    private let correlatedGroups: [[String]] = [
        // EUR Group
        ["EURUSD", "EURJPY", "EURGBP", "EURCHF", "EURAUD"],
        // GBP Group
        ["GBPUSD", "GBPJPY", "GBPCHF", "GBPAUD"],
        // JPY Group
        ["USDJPY", "EURJPY", "GBPJPY", "AUDJPY", "CADJPY", "NZDJPY", "CHFJPY"],
        // AUD Group
        ["AUDUSD", "AUDJPY", "AUDCHF", "AUDCAD", "AUDNZD"],
        // USD Group
        ["USDJPY", "USDCAD", "USDCHF", "AUDUSD", "GBPUSD", "EURUSD", "NZDUSD"],
        // CAD Group
        ["USDCAD", "CADJPY", "AUDCAD", "NZDCAD", "EURCAD", "GBPCAD"]
    ]
    
    func canOpenTrade(symbol: String) async -> Bool {
        // 1. Check active symbols
        if activeSymbols.contains(symbol) {
            godLog("🔄 Correlation: Already have active trade in \(symbol)", level: .warning)
            return false
        }
        
        // 2. Update correlation data if stale
        if Date().timeIntervalSince(lastUpdate) > updateInterval {
            await updateCorrelations()
        }
        
        // 3. Check against active trades
        for activeSymbol in activeSymbols {
            // Check if in same group
            if areInSameGroup(symbol, activeSymbol) {
                godLog("🔄 Correlation: \(symbol) and \(activeSymbol) in same group - BLOCKED", level: .warning)
                return false
            }
            
            // Check numerical correlation
            if let correlation = await getCorrelation(symbol, activeSymbol),
               abs(correlation) > correlationThreshold {
                godLog("🔄 Correlation: \(symbol) vs \(activeSymbol) = \(String(format: "%.2f", correlation)) - BLOCKED", level: .warning)
                return false
            }
        }
        
        return true
    }
    
    func registerTrade(symbol: String) async {
        activeSymbols.insert(symbol)
        godLog("📊 Correlation: Registered \(symbol) - Active: \(activeSymbols.count)", level: .info)
    }
    
    func removeTrade(symbol: String) async {
        activeSymbols.remove(symbol)
        godLog("📊 Correlation: Removed \(symbol) - Active: \(activeSymbols.count)", level: .info)
    }
    
    private func areInSameGroup(_ symbol1: String, _ symbol2: String) -> Bool {
        for group in correlatedGroups {
            if group.contains(symbol1) && group.contains(symbol2) {
                return true
            }
        }
        return false
    }
    
    private func updateCorrelations() async {
        // Fetch from MT5
        do {
            // Note: Since getCorrelationMatrix isn't in MT5Service yet, we fallback to default
            // In a future update, we can add this endpoint to the bridge.
            godLog("⚠️ Using default correlation matrix (MT5 Bridge endpoint pending)", level: .warning)
            symbolCorrelations = getDefaultCorrelations()
            lastUpdate = Date()
        }
    }
    
    private func getCorrelation(_ symbol1: String, _ symbol2: String) async -> Double? {
        return symbolCorrelations[symbol1]?[symbol2]
    }
    
    private func getDefaultCorrelations() -> [String: [String: Double]] {
        // Simplified default correlations
        var matrix: [String: [String: Double]] = [:]
        
        let symbols = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", 
                       "EURJPY", "GBPJPY", "AUDJPY", "CADJPY"]
        
        for s1 in symbols {
            matrix[s1] = [:]
            for s2 in symbols {
                if s1 == s2 { continue }
                // Rough correlation estimates
                let value: Double
                if s1.prefix(3) == s2.prefix(3) || s1.suffix(3) == s2.suffix(3) {
                    value = 0.80 // Same base or quote
                } else if s1.prefix(3) == "USD" || s2.prefix(3) == "USD" {
                    value = 0.60 // USD pair
                } else {
                    value = 0.30 // Different groups
                }
                matrix[s1]?[s2] = value
            }
        }
        return matrix
    }
}
