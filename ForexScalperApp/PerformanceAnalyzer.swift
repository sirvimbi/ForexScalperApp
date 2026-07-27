// PerformanceAnalyzer.swift - GOD MODE SELF-LEARNING
import Foundation

actor PerformanceAnalyzer {
    static let shared = PerformanceAnalyzer()
    
    // 🎯 ADAPTIVE LEARNING
    private var symbolStats: [String: SymbolPerformance] = [:]
    private var sessionStats: [String: SessionPerformance] = [:]
    
    struct SymbolPerformance: Codable {
        var totalTrades: Int = 0
        var wins: Int = 0
        var losses: Int = 0
        var totalPnL: Double = 0
        var avgWin: Double = 0
        var avgLoss: Double = 0
        var bestTrade: Double = 0
        var worstTrade: Double = 0
        var lastUpdated: Date = Date()
        var consecutiveWins: Int = 0
        var consecutiveLosses: Int = 0
        
        var winRate: Double {
            guard totalTrades > 0 else { return 0 }
            return Double(wins) / Double(totalTrades)
        }
        
        var profitFactor: Double {
            guard totalTrades > 0 else { return 0 }
            let grossProfit = Double(wins) * avgWin
            let grossLoss = Double(losses) * avgLoss
            return grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? .infinity : 0)
        }
        
        var expectedValue: Double {
            guard totalTrades > 0 else { return 0 }
            return (winRate * avgWin) - ((1 - winRate) * avgLoss)
        }
    }
    
    struct SessionPerformance: Codable {
        var totalTrades: Int = 0
        var wins: Int = 0
        var losses: Int = 0
        var totalPnL: Double = 0
        var winRate: Double {
            guard totalTrades > 0 else { return 0 }
            return Double(wins) / Double(totalTrades)
        }
    }
    
    func recordTrade(_ trade: TradeRecord) async {
        guard let pnl = trade.pnl else { return }
        
        // Update symbol stats
        var stats = symbolStats[trade.symbol] ?? SymbolPerformance()
        stats.totalTrades += 1
        stats.totalPnL += pnl
        stats.lastUpdated = Date()
        
        if pnl > 0 {
            stats.wins += 1
            stats.consecutiveWins += 1
            stats.consecutiveLosses = 0
            stats.avgWin = (stats.avgWin * Double(stats.wins - 1) + pnl) / Double(stats.wins)
            if pnl > stats.bestTrade { stats.bestTrade = pnl }
        } else {
            stats.losses += 1
            stats.consecutiveLosses += 1
            stats.consecutiveWins = 0
            stats.avgLoss = (stats.avgLoss * Double(stats.losses - 1) + abs(pnl)) / Double(stats.losses)
            if pnl < stats.worstTrade { stats.worstTrade = pnl }
        }
        
        symbolStats[trade.symbol] = stats
        
        // Update session stats
        let hour = Calendar.current.component(.hour, from: Date())
        let session: String
        if hour >= 0 && hour < 8 { session = "Asian" }
        else if hour >= 8 && hour < 16 { session = "London" }
        else if hour >= 16 && hour < 24 { session = "US" }
        else { session = "Off-Hours" }
        
        var sessionStat = sessionStats[session] ?? SessionPerformance()
        sessionStat.totalTrades += 1
        sessionStat.totalPnL += pnl
        if pnl > 0 { sessionStat.wins += 1 } else { sessionStat.losses += 1 }
        sessionStats[session] = sessionStat
        
        godLog("📊 Performance recorded: \(trade.symbol) - KES \(String(format: "%.2f", pnl)) - Win Rate: \(String(format: "%.1f", stats.winRate * 100))%", level: .info)
    }
    
    func getSymbolScore(_ symbol: String) -> Double {
        guard let stats = symbolStats[symbol], stats.totalTrades >= 5 else {
            return 1.0 // Neutral for new symbols
        }
        
        let winRate = stats.winRate
        let profitFactor = stats.profitFactor
        let expectedValue = stats.expectedValue
        
        var score = 1.0
        score *= (0.5 + winRate)
        
        if profitFactor > 0 {
            score *= min(1.5, 0.5 + profitFactor / 2)
        }
        
        if expectedValue > 0 {
            score *= min(1.3, 1 + expectedValue / 100)
        } else {
            score *= max(0.5, 1 + expectedValue / 100)
        }
        
        if stats.consecutiveLosses >= 3 {
            score *= 0.5
        }
        
        return min(1.5, max(0.3, score))
    }
    
    func getRecommendation(symbol: String) -> (shouldTrade: Bool, reason: String, confidenceMultiplier: Double) {
        guard let stats = symbolStats[symbol], stats.totalTrades >= 5 else {
            return (true, "Insufficient data", 1.0)
        }
        
        let score = getSymbolScore(symbol)
        
        if score < 0.4 {
            return (false, "Poor performance: \(String(format: "%.1f", stats.winRate * 100))% win rate", 0)
        } else if score < 0.7 {
            return (true, "Average performance: \(String(format: "%.1f", stats.winRate * 100))% win rate", 0.8)
        } else if score > 1.2 {
            return (true, "Excellent performance: \(String(format: "%.1f", stats.winRate * 100))% win rate", 1.2)
        } else {
            return (true, "Stable performance: \(String(format: "%.1f", stats.winRate * 100))% win rate", 1.0)
        }
    }
    
    func getPerformanceReport() -> String {
        var report = "📊 GOD MODE PERFORMANCE REPORT\n"
        report += "=============================\n\n"
        
        let topSymbols = symbolStats
            .filter { $0.value.totalTrades >= 5 }
            .sorted { $0.value.winRate > $1.value.winRate }
            .prefix(5)
        
        report += "🏆 TOP PERFORMERS:\n"
        for (symbol, stats) in topSymbols {
            report += "  \(symbol): \(String(format: "%.1f", stats.winRate * 100))% (\(stats.totalTrades) trades, P&L: \(String(format: "%.2f", stats.totalPnL)))\n"
        }
        
        let bottomSymbols = symbolStats
            .filter { $0.value.totalTrades >= 5 }
            .sorted { $0.value.winRate < $1.value.winRate }
            .prefix(5)
        
        report += "\n📉 NEEDS IMPROVEMENT:\n"
        for (symbol, stats) in bottomSymbols {
            report += "  \(symbol): \(String(format: "%.1f", stats.winRate * 100))% (\(stats.totalTrades) trades, P&L: \(String(format: "%.2f", stats.totalPnL)))\n"
        }
        
        report += "\n🕐 SESSION PERFORMANCE:\n"
        for (session, stats) in sessionStats.sorted(by: { $0.value.winRate > $1.value.winRate }) {
            report += "  \(session): \(String(format: "%.1f", stats.winRate * 100))% (\(stats.totalTrades) trades)\n"
        }
        
        return report
    }
}
