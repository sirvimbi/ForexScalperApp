// CorrelationFilter.swift - GOD MODE V7.0 ELITE
import Foundation

actor CorrelationFilter {
    static let shared = CorrelationFilter()
    
    // ELITE: Stricter correlation groups
    private let correlatedGroups: [[String]] = [
        // EUR Group - Never trade more than 1
        ["EURUSD", "EURJPY", "EURGBP", "EURCHF", "EURAUD", "EURCAD"],
        // GBP Group - Never trade more than 1
        ["GBPUSD", "GBPJPY", "GBPCHF", "GBPAUD", "EURGBP"],
        // JPY Group - Never trade more than 1
        ["USDJPY", "EURJPY", "GBPJPY", "AUDJPY", "CADJPY", "NZDJPY", "CHFJPY"],
        // AUD Group - Never trade more than 1
        ["AUDUSD", "AUDJPY", "AUDCHF", "AUDCAD", "AUDNZD", "EURAUD"],
        // USD Group - Never trade more than 2
        ["USDJPY", "USDCAD", "USDCHF", "AUDUSD", "GBPUSD", "EURUSD", "NZDUSD"],
        // CAD Group - Never trade more than 1
        ["USDCAD", "CADJPY", "AUDCAD", "NZDCAD", "EURCAD", "GBPCAD"]
    ]
    
    private var activeSymbols: Set<String> = []
    
    func canOpenTrade(symbol: String, confidence: Double = 0) async -> Bool {
        // 1. Already active
        if activeSymbols.contains(symbol) {
            godLog("🔄 Already have active trade in \(symbol) - BLOCKED", level: .warning)
            return false
        }
        
        // 2. Check each group
        for group in correlatedGroups {
            if group.contains(symbol) {
                let activeInGroup = group.filter { activeSymbols.contains($0) }
                
                // If we already have a trade in this group, block
                if !activeInGroup.isEmpty {
                    // ELITE: Allow only if confidence > 95% (God Mode bypass)
                    if confidence >= 95.0 {
                        godLog("💎 GOD MODE BYPASS: Allowing \(symbol) despite correlation with \(activeInGroup.joined(separator: ", "))", level: .success)
                        continue
                    }
                    
                    godLog("🔄 Correlation BLOCKED: \(symbol) correlated with \(activeInGroup.joined(separator: ", "))", level: .warning)
                    return false
                }
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
    
    func syncActiveSymbols(_ symbols: Set<String>) async {
        self.activeSymbols = symbols
        godLog("📊 Correlation: Force-synced \(activeSymbols.count) active symbols", level: .info)
    }
}
