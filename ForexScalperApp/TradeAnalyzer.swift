// TradeAnalyzer.swift - GOD MODE Performance Analysis & Symbol Blacklist Generator
import Foundation

struct TradeAnalyzer {
    
    // MARK: - Main Analysis Function
    static func analyze(_ trades: [TradeRecord]) -> AnalysisReport {
        var symbolStats: [String: SymbolStats] = [:]
        var totalWins = 0
        var totalLosses = 0
        var totalPnL: Double = 0
        var winRate: Double = 0
        var averageWin: Double = 0
        var averageLoss: Double = 0
        var bestTrade: Double = -Double.infinity
        var worstTrade: Double = Double.infinity
        
        // Group by symbol
        for trade in trades where trade.status == .completed {
            guard let pnl = trade.pnl else { continue }
            
            totalPnL += pnl
            bestTrade = max(bestTrade, pnl)
            worstTrade = min(worstTrade, pnl)
            
            if pnl > 0 {
                totalWins += 1
                averageWin += pnl
            } else {
                totalLosses += 1
                averageLoss += pnl
            }
            
            // Symbol-level stats
            var stats = symbolStats[trade.symbol] ?? SymbolStats(symbol: trade.symbol)
            stats.totalTrades += 1
            stats.totalPnL += pnl
            if pnl > 0 {
                stats.wins += 1
                stats.winPnL += pnl
            } else {
                stats.losses += 1
                stats.lossPnL += pnl
            }
            
            // Track max drawdown
            stats.maxDrawdown = min(stats.maxDrawdown, pnl)
            stats.maxProfit = max(stats.maxProfit, pnl)
            
            symbolStats[trade.symbol] = stats
        }
        
        // Calculate derived metrics
        let totalTrades = totalWins + totalLosses
        winRate = totalTrades > 0 ? Double(totalWins) / Double(totalTrades) : 0
        averageWin = totalWins > 0 ? averageWin / Double(totalWins) : 0
        averageLoss = totalLosses > 0 ? averageLoss / Double(totalLosses) : 0
        
        // Calculate expectancy
        let expectancy = (winRate * averageWin) - ((1 - winRate) * abs(averageLoss))
        let profitFactor = abs(averageLoss) > 0 ? averageWin / abs(averageLoss) : 0
        
        // Calculate symbol profitability
        for (symbol, stats) in symbolStats {
            let winRate = stats.totalTrades > 0 ? Double(stats.wins) / Double(stats.totalTrades) : 0
            let avgWin = stats.wins > 0 ? stats.winPnL / Double(stats.wins) : 0
            let avgLoss = stats.losses > 0 ? stats.lossPnL / Double(stats.losses) : 0
            let profitFactor = abs(avgLoss) > 0 ? avgWin / abs(avgLoss) : 0
            
            symbolStats[symbol]?.winRate = winRate
            symbolStats[symbol]?.avgWin = avgWin
            symbolStats[symbol]?.avgLoss = avgLoss
            symbolStats[symbol]?.profitFactor = profitFactor
            symbolStats[symbol]?.expectancy = (winRate * avgWin) - ((1 - winRate) * abs(avgLoss))
        }
        
        // Sort symbols by performance
        let sortedSymbols = symbolStats.values.sorted { $0.totalPnL > $1.totalPnL }
        
        // Generate blacklist
        let blacklist = sortedSymbols.filter { $0.totalPnL < 0 && $0.totalTrades >= 3 }
        
        // Generate whitelist (keepers)
        let whitelist = sortedSymbols.filter { $0.totalPnL > 0 && $0.totalTrades >= 3 }
        
        return AnalysisReport(
            totalTrades: totalTrades,
            totalWins: totalWins,
            totalLosses: totalLosses,
            totalPnL: totalPnL,
            winRate: winRate,
            averageWin: averageWin,
            averageLoss: averageLoss,
            profitFactor: profitFactor,
            expectancy: expectancy,
            bestTrade: bestTrade,
            worstTrade: worstTrade,
            symbolStats: sortedSymbols,
            blacklist: blacklist,
            whitelist: whitelist,
            generatedAt: Date()
        )
    }
    
    // MARK: - Generate Recommendations
    
    static func generateRecommendations(_ report: AnalysisReport) -> String {
        var output = """
        🚀 GOD MODE TRADE ANALYSIS REPORT
        =================================
        Generated: \(formattedDate(report.generatedAt))
        
        📊 OVERALL PERFORMANCE
        ----------------------
        Total Trades: \(report.totalTrades)
        Win Rate: \(String(format: "%.1f%%", report.winRate * 100))
        Total P&L: KES \(String(format: "%.2f", report.totalPnL))
        Average Win: KES \(String(format: "%.2f", report.averageWin))
        Average Loss: KES \(String(format: "%.2f", report.averageLoss))
        Profit Factor: \(String(format: "%.2f", report.profitFactor))
        Expectancy: KES \(String(format: "%.2f", report.expectancy)) per trade
        Best Trade: KES \(String(format: "%.2f", report.bestTrade))
        Worst Trade: KES \(String(format: "%.2f", report.worstTrade))
        
        """
        
        // Top 5 performing symbols
        output += """
        
        🏆 TOP 5 PERFORMING SYMBOLS
        ---------------------------
        """
        for (index, stats) in report.symbolStats.prefix(5).enumerated() {
            output += """
            
            \(index + 1). \(stats.symbol)
               Trades: \(stats.totalTrades) | Win Rate: \(String(format: "%.1f%%", stats.winRate * 100))
               P&L: KES \(String(format: "%.2f", stats.totalPnL))
               Avg Win: KES \(String(format: "%.2f", stats.avgWin))
               Avg Loss: KES \(String(format: "%.2f", stats.avgLoss))
               Profit Factor: \(String(format: "%.2f", stats.profitFactor))
            """
        }
        
        // Bottom 5 performing symbols
        output += """
        
        📉 BOTTOM 5 PERFORMING SYMBOLS (BLACKLIST CANDIDATES)
        ----------------------------------------------------
        """
        let bottom5 = report.symbolStats.suffix(5).reversed()
        for (index, stats) in bottom5.enumerated() {
            output += """
            
            \(index + 1). \(stats.symbol)
               Trades: \(stats.totalTrades) | Win Rate: \(String(format: "%.1f%%", stats.winRate * 100))
               P&L: KES \(String(format: "%.2f", stats.totalPnL))
               Avg Win: KES \(String(format: "%.2f", stats.avgWin))
               Avg Loss: KES \(String(format: "%.2f", stats.avgLoss))
               Profit Factor: \(String(format: "%.2f", stats.profitFactor))
            """
        }
        
        // BLACKLIST GENERATION
        if !report.blacklist.isEmpty {
            output += """
            
            ⛔ RECOMMENDED BLACKLIST (SYMBOLS TO STOP TRADING)
            ------------------------------------------------
            """
            for stats in report.blacklist {
                output += "\n   • \(stats.symbol) (Loss: KES \(String(format: "%.2f", stats.totalPnL)))"
            }
        }
        
        // WHITELIST RECOMMENDATIONS
        if !report.whitelist.isEmpty {
            output += """
            
            ✅ RECOMMENDED WHITELIST (SYMBOLS TO FOCUS ON)
            ---------------------------------------------
            """
            for stats in report.whitelist {
                output += "\n   • \(stats.symbol) (Profit: KES \(String(format: "%.2f", stats.totalPnL)))"
            }
        }
        
        // RECOMMENDATIONS
        output += """
        
        🎯 ACTIONABLE RECOMMENDATIONS
        ----------------------------
        """
        
        if report.profitFactor < 1.0 {
            output += """
            
            ⚠️ CRITICAL: Profit Factor < 1.0 means you're losing money overall.
            """
        }
        
        if report.winRate < 0.3 {
            output += """
            
            ⚠️ LOW WIN RATE: Your win rate is below 30%. Consider:
               - Reducing position size
               - Waiting for stronger confirmations
               - Only trading top 3 symbols
            """
        }
        
        if report.averageLoss > abs(report.averageWin) {
            output += """
            
            ⚠️ POOR RISK MANAGEMENT: Your average loss (\(String(format: "KES %.2f", report.averageLoss))) exceeds average win (\(String(format: "KES %.2f", report.averageWin))).
               - Stop-loss must be tighter
               - Take-profit must be further out
               - R:R ratio must be at least 1.5:1
            """
        }
        
        if !report.blacklist.isEmpty {
            output += """
            
            🔴 IMMEDIATE ACTION: Stop trading these \(report.blacklist.count) symbols:
            """
            for stats in report.blacklist {
                output += "\n   - \(stats.symbol)"
            }
        }
        
        output += """
        
        📋 RECOMMENDED SYMBOL CONFIGURATION
        ----------------------------------
        Copy this to your Settings:
        
        """
        
        // Generate recommended symbol list
        let recommendedSymbols = report.whitelist.map { $0.symbol }
        if !recommendedSymbols.isEmpty {
            output += "ACTIVE_SYMBOLS = ["
            for (index, symbol) in recommendedSymbols.prefix(10).enumerated() {
                output += index == 0 ? "\n    " : "\n    "
                output += "\"\(symbol)\""
                if index < recommendedSymbols.prefix(10).count - 1 {
                    output += ","
                }
            }
            output += "\n]\n"
        }
        
        output += """
        
        =================================
        Analysis complete. Deploy changes immediately.
        
        """
        
        return output
    }
    
    // MARK: - Generate Blacklist Code
    
    static func generateBlacklistCode(_ report: AnalysisReport) -> String {
        let blacklistSymbols = report.blacklist.map { $0.symbol }
        let whitelistSymbols = report.whitelist.map { $0.symbol }
        
        var code = """
        // GOD MODE - AUTO-GENERATED SYMBOL CONFIGURATION
        // Generated: \(formattedDate(report.generatedAt))
        
        #if DEBUG
        let isTestMode = true
        #else
        let isTestMode = false
        #endif
        
        """
        
        if !blacklistSymbols.isEmpty {
            code += """
            
            // MARK: - BLACKLIST (DO NOT TRADE THESE SYMBOLS)
            private let blacklistedSymbols: Set<String> = [
            """
            for symbol in blacklistSymbols {
                code += "\n    \"\(symbol)\","
            }
            code += """
            
            ]
            
            """
        }
        
        if !whitelistSymbols.isEmpty {
            code += """
            // MARK: - WHITELIST (PREFERRED SYMBOLS)
            private let recommendedSymbols: [String] = [
            """
            for symbol in whitelistSymbols {
                code += "\n    \"\(symbol)\","
            }
            code += """
            
            ]
            
            """
        }
        
        code += """
        // MARK: - Symbol Filter Function
        func isSymbolAllowed(_ symbol: String) -> Bool {
            // First check if symbol is in whitelist
            if recommendedSymbols.contains(symbol) {
                return true
            }
            
            // If not in whitelist, check if it's blacklisted
            if blacklistedSymbols.contains(symbol) {
                return false
            }
            
            // Default: only allow majors and tight-spread minors
            let allowedSymbols = [
                "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD",
                "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "EURGBP", "EURCHF",
                "GBPCHF", "CADJPY", "CHFJPY", "AUDCHF", "NZDCAD", "AUDNZD"
            ]
            
            return allowedSymbols.contains(symbol)
        }
        
        """
        
        return code
    }
    
    // MARK: - Helpers
    
    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Data Structures

struct AnalysisReport {
    let totalTrades: Int
    let totalWins: Int
    let totalLosses: Int
    let totalPnL: Double
    let winRate: Double
    let averageWin: Double
    let averageLoss: Double
    let profitFactor: Double
    let expectancy: Double
    let bestTrade: Double
    let worstTrade: Double
    let symbolStats: [SymbolStats]
    let blacklist: [SymbolStats]
    let whitelist: [SymbolStats]
    let generatedAt: Date
}

struct SymbolStats {
    let symbol: String
    var totalTrades: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    var totalPnL: Double = 0
    var winPnL: Double = 0
    var lossPnL: Double = 0
    var maxDrawdown: Double = 0
    var maxProfit: Double = 0
    var winRate: Double = 0
    var avgWin: Double = 0
    var avgLoss: Double = 0
    var profitFactor: Double = 0
    var expectancy: Double = 0
}
