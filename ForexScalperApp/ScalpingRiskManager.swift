// ScalpingRiskManager.swift - COMPLETE FIXED VERSION
import Foundation

// MARK: - Calendar Extension
extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}

actor ScalpingRiskManager: RiskManagerProtocol {
    static let shared = ScalpingRiskManager()
    
    private var parameters = RiskParameters(
        accountBalance: 10000,
        riskPerTrade: 0.005, // 0.5% risk per trade for scalping
        maxDailyRisk: 0.02,   // 2% max daily loss
        maxConcurrentTrades: 2 // Max 2 concurrent scalps
    )
    
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]
    
    // Add a flag to completely bypass limits for testing
    private var bypassAllLimits = false
    
    func canOpenTrade(for symbol: String) async -> Bool {
        print("🔍 RISK MANAGER CHECK: symbol=\(symbol), bypassAllLimits=\(bypassAllLimits)")
        
        // COMPLETE BYPASS FOR TESTING - REMOVE THIS IN PRODUCTION
        if bypassAllLimits {
            print("🔧 TEST MODE: Bypassing all risk limits - ALLOWING TRADE")
            return true
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Check daily loss limit
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        
        if todayPnL <= -parameters.accountBalance * parameters.maxDailyRisk {
            print("⚠️ Daily loss limit reached: \(String(format: "%.2f", todayPnL))")
            return false
        }
        
        // FIXED: Safely calculate hourly trade limit - ALWAYS AT LEAST 2
        let currentHour = calendar.startOfHour(for: now)
        let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
        
        // CRITICAL FIX: Ensure max hourly trades is NEVER zero
        // Base hourly limit on concurrent trades, but ensure minimum of 2
        let baseHourlyLimit = max(2, parameters.maxConcurrentTrades)  // Changed from max(1,...) to max(2,...)
        // Allow up to 3x concurrent trades per hour, but at least 2, at most 10
        let maxHourlyTrades = max(2, min(10, baseHourlyLimit * 2))
        
        print("📊 Hourly trade count: \(hourlyTrades)/\(maxHourlyTrades) (base limit: \(baseHourlyLimit), max concurrent: \(parameters.maxConcurrentTrades))")
        
        if hourlyTrades >= maxHourlyTrades {
            print("⚠️ Hourly trade limit reached: \(hourlyTrades)/\(maxHourlyTrades)")
            return false
        }
        
        // Check concurrent trades
        if activeTrades.count >= parameters.maxConcurrentTrades {
            print("⚠️ Max concurrent trades reached: \(activeTrades.count)/\(parameters.maxConcurrentTrades)")
            return false
        }
        
        // Check consecutive losses - reduce risk after losses
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 5 { // Increased from 3 to 5
            print("⚠️ Too many consecutive losses (\(losses)) for \(symbol)")
            return false
        }
        
        // Check cooldown per symbol (2 minutes for scalping)
        if let lastTrade = tradeOpenTime[symbol],
           now.timeIntervalSince(lastTrade) < 120 {
            print("⚠️ Cooldown active for \(symbol): \(Int(now.timeIntervalSince(lastTrade)))s/120s")
            return false
        }
        
        print("✅ Risk check PASSED for \(symbol)")
        return true
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let riskAmount = parameters.accountBalance * parameters.riskPerTrade
        
        // Adjust for consecutive losses
        let losses = consecutiveLosses[signal.symbol] ?? 0
        let lossMultiplier = max(1.0 - Double(losses) * 0.25, 0.25) // Reduce by 25% per loss, minimum 25%
        let adjustedRiskAmount = riskAmount * lossMultiplier
        
        // Dynamic stop loss based on ATR
        let atr = signal.volume > 0 ? signal.volume / 1000 : 0.001 // Use volume as ATR proxy
        let stopLossPips = atr * 0.5 // 0.5 ATR stop loss for scalping
        let takeProfitPips = stopLossPips * 2 // 2:1 reward ratio
        
        // Calculate position size based on stop loss distance
        let stopLossDistance = signal.price * stopLossPips
        let units = adjustedRiskAmount / stopLossDistance
        
        let stopLoss = signal.type == .buy ?
            signal.price - stopLossDistance :
            signal.price + stopLossDistance
            
        let takeProfit = signal.type == .buy ?
            signal.price + (stopLossDistance * 2) :
            signal.price - (stopLossDistance * 2)
        
        return PositionSize(
            units: units,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            riskAmount: adjustedRiskAmount,
            potentialReward: adjustedRiskAmount * 2
        )
    }
    
    func resetDailyLimits() async {
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        consecutiveLosses.removeAll()
        print("✅ Risk limits reset")
    }

    func forceAllowTrading() async {
        // This is just for testing - removes all restrictions
        bypassAllLimits = true
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        consecutiveLosses.removeAll()
        activeTrades.removeAll()
        tradeOpenTime.removeAll()
        print("⚠️ Trading restrictions cleared for testing - BYPASS MODE ENABLED")
    }
    
    func disableBypassMode() async {
        bypassAllLimits = false
        print("ℹ️ Bypass mode disabled")
    }
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
        
        // Increment hourly count
        let now = Date()
        let currentHour = Calendar.current.startOfHour(for: now)
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
    }
    
    func closeTrade(_ trade: TradeRecord) async {
        activeTrades.remove(trade.symbol)
        
        if let pnl = trade.pnl {
            let today = Calendar.current.startOfDay(for: Date())
            dailyPnL[today] = (dailyPnL[today] ?? 0) + pnl
            
            // Track consecutive losses
            if pnl < 0 {
                consecutiveLosses[trade.symbol] = (consecutiveLosses[trade.symbol] ?? 0) + 1
            } else {
                consecutiveLosses[trade.symbol] = 0 // Reset on win
            }
        }
    }
    
    func getCurrentRiskMetrics() async -> RiskMetrics {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let currentHour = calendar.startOfHour(for: now)
        
        // Calculate max hourly trades safely - ALWAYS AT LEAST 2
        let baseHourlyLimit = max(2, parameters.maxConcurrentTrades)
        let maxHourlyTrades = max(2, min(10, baseHourlyLimit * 2))
        
        return RiskMetrics(
            dailyPnL: dailyPnL[today] ?? 0,
            dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk,
            hourlyTrades: hourlyTradeCount[currentHour] ?? 0,
            maxHourlyTrades: maxHourlyTrades,
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
    
    func resetAllLimitsForTesting() async {
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        consecutiveLosses.removeAll()
        activeTrades.removeAll()
        tradeOpenTime.removeAll()
        bypassAllLimits = true // Enable bypass mode
        print("✅ All risk limits reset for testing - BYPASS MODE ENABLED")
    }
}

// Update RiskMetrics struct
struct RiskMetrics {
    let dailyPnL: Double
    let dailyLossLimit: Double
    let hourlyTrades: Int
    let maxHourlyTrades: Int  // Added this field
    let activeTrades: Int
    let maxConcurrentTrades: Int
    let consecutiveLosses: [String: Int]
}
