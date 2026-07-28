// ScalpingRiskManager.swift - GOD MODE V7.0 ELITE
import Foundation

actor ScalpingRiskManager: RiskManagerProtocol {
    static let shared = ScalpingRiskManager()
    
    private var parameters = RiskParameters(
        accountBalance: 10000,
        riskPerTrade: 0.008,  // 0.8% per trade
        maxDailyRisk: 0.02,   // 2% max daily loss
        maxConcurrentTrades: 2
    )
    
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]
    private var dailyTradeCount: Int = 0
    private var lastResetDate: Date = Date()
    
    // ATR Cache
    private var symbolATRCache: [String: (atr: Double, timestamp: Date)] = [:]
    private let atrCacheDuration: TimeInterval = 60
    
    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        godLog("🛡 Risk Manager: Updated balance to KES \(String(format: "%.2f", params.accountBalance))", level: .info)
    }
    
    // MARK: - CAN OPEN TRADE (ELITE)
    
    func canOpenTrade(for symbol: String) async -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        // 1. Daily reset
        if !calendar.isDate(lastResetDate, inSameDayAs: now) {
            dailyTradeCount = 0
            dailyPnL.removeAll()
            lastResetDate = now
        }
        
        // 2. Daily trade limit
        let maxDaily = await MainActor.run { ScalpingConfig.shared.maxDailyTrades }
        guard dailyTradeCount < maxDaily else {
            godLog("⚠️ Daily trade limit reached: \(maxDaily)", level: .warning)
            return false
        }
        
        // 3. Daily loss limit
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        let maxLoss = parameters.accountBalance * parameters.maxDailyRisk
        
        if todayPnL <= -maxLoss {
            godLog("⚠️ Daily loss limit reached: KES \(String(format: "%.2f", todayPnL))", level: .warning)
            return false
        }
        
        // 4. Hourly limit (max 3 per hour for quality)
        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
        if hourlyTrades >= 3 {
            godLog("⚠️ Hourly limit reached: 3 trades", level: .warning)
            return false
        }
        
        // 5. Concurrent trades
        if activeTrades.count >= parameters.maxConcurrentTrades {
            godLog("⚠️ Max concurrent: \(activeTrades.count)/\(parameters.maxConcurrentTrades)", level: .warning)
            return false
        }
        
        // 6. Symbol already active
        if activeTrades.contains(symbol) {
            godLog("⚠️ Already have active trade in \(symbol)", level: .warning)
            return false
        }
        
        // 7. Consecutive losses
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 3 {
            godLog("⚠️ \(losses) consecutive losses for \(symbol) - PAUSED", level: .warning)
            return false
        }
        
        // 8. Cooldown
        let cooldown = await MainActor.run { ScalpingConfig.shared.cooldownSeconds }
        if let lastTrade = tradeOpenTime[symbol], now.timeIntervalSince(lastTrade) < cooldown {
            let remaining = Int(cooldown - now.timeIntervalSince(lastTrade))
            godLog("⏳ Cooldown: \(remaining)s remaining", level: .diagnostic)
            return false
        }
        
        // 9. Spread check
        if let spread = try? await MT5Service.shared.getCurrentSpread(symbol: symbol) {
            let symbolConfig = await MainActor.run { ScalpingConfig.shared.getSymbolConfig(symbol) }
            if spread > symbolConfig.maxSpread {
                godLog("⚠️ Spread too high: \(String(format: "%.1f", spread)) pips", level: .warning)
                return false
            }
        }
        
        godLog("✅ Risk check PASSED for \(symbol)")
        return true
    }
    
    // MARK: - CALCULATE POSITION SIZE (ELITE)
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let balance = parameters.accountBalance
        let riskAmount = balance * parameters.riskPerTrade
        
        // Get ATR for dynamic sizing
        let sessionMultiplier = await MainActor.run { ScalpingConfig.shared.getSessionMultiplier() }
        let symbolConfig = await MainActor.run { ScalpingConfig.shared.getSymbolConfig(signal.symbol) }
        let minSL = await MainActor.run { ScalpingConfig.shared.minSLPips }
        let maxSL = await MainActor.run { ScalpingConfig.shared.maxSLPips }
        let minTP = await MainActor.run { ScalpingConfig.shared.minTPPips }
        let maxTP = await MainActor.run { ScalpingConfig.shared.maxTPPips }

        // Calculate SL distance (ELITE: 6-15 pips)
        let pipSize = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        let baseSLPips = symbolConfig.baseSL * sessionMultiplier.sl
        let finalSLPips = min(max(baseSLPips, minSL), maxSL)
        let slDistance = finalSLPips * pipSize
        
        // Calculate TP distance (ELITE: 8-25 pips, always > SL)
        let baseTPPips = symbolConfig.baseTP * sessionMultiplier.tp
        let finalTPPips = min(max(baseTPPips, minTP), maxTP)
        let tpDistance = finalTPPips * pipSize
        
        // Position size
        let kesToUsdRate = 130.0
        let riskInUsd = riskAmount / kesToUsdRate
        var lotSize = riskInUsd / (slDistance * 100000)
        
        // Round to valid lot size
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)
        let steps = round(lotSize / limits.step)
        lotSize = max(limits.min, min(steps * limits.step, limits.max))
        lotSize = min(lotSize, 0.05) // Cap at 0.05 for safety
        
        // ELITE: Reduce size after losses
        let losses = consecutiveLosses[signal.symbol] ?? 0
        if losses >= 2 {
            lotSize *= 0.5
        }
        if losses >= 3 {
            lotSize *= 0.5 // 0.25x after 3 losses
        }
        
        // Final SL and TP
        let stopLoss = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let takeProfit = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance
        
        // Verify R:R is at least 1.5
        let risk = abs(signal.price - stopLoss)
        let reward = abs(takeProfit - signal.price)
        let rrRatio = reward / max(risk, 0.00001)
        
        var finalTP = takeProfit
        if rrRatio < 1.5 {
            let minTPDistance = risk * 1.5
            finalTP = signal.type == .buy ? signal.price + minTPDistance : signal.price - minTPDistance
        }
        
        godLog("""
        📐 ELITE POSITION:
           Symbol: \(signal.symbol)
           SL: \(String(format: "%.5f", stopLoss)) (\(Int(finalSLPips)) pips)
           TP: \(String(format: "%.5f", finalTP)) (\(Int(abs(finalTP - signal.price) / pipSize)) pips)
           Lot: \(String(format: "%.3f", lotSize))
           R:R: \(String(format: "%.2f", abs(finalTP - signal.price) / max(abs(stopLoss - signal.price), 0.00001))):1
        """, level: .info)
        
        return PositionSize(
            units: lotSize,
            stopLoss: stopLoss,
            takeProfit: finalTP,
            riskAmount: riskAmount,
            potentialReward: riskAmount * 1.5
        )
    }
    
    // MARK: - GET ATR
    
    private func getATR(symbol: String) async -> Double {
        if let cached = symbolATRCache[symbol],
           Date().timeIntervalSince(cached.timestamp) < atrCacheDuration {
            return cached.atr
        }
        
        do {
            let atr = try await MT5Service.shared.getATR(symbol: symbol, period: 14)
            symbolATRCache[symbol] = (atr: atr, timestamp: Date())
            return atr
        } catch {
            let defaultATR = symbol.contains("JPY") ? 0.15 : 0.0015
            return defaultATR
        }
    }
    
    // MARK: - REGISTER/CLOSE TRADE
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
        dailyTradeCount += 1
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
        
        godLog("📊 MT5 Trade Registered: \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice))", level: .trade)
    }
    
    func closeTrade(_ trade: TradeRecord) async {
        activeTrades.remove(trade.symbol)
        
        if let pnl = trade.pnl {
            let today = Calendar.current.startOfDay(for: Date())
            dailyPnL[today] = (dailyPnL[today] ?? 0) + pnl
            
            if pnl < 0 {
                consecutiveLosses[trade.symbol] = (consecutiveLosses[trade.symbol] ?? 0) + 1
            } else {
                consecutiveLosses[trade.symbol] = 0
            }
        }
        
        godLog("📊 Risk Manager: Removed \(trade.symbol) from active list", level: .diagnostic)
    }
    
    func syncActiveTrades(_ symbols: Set<String>) {
        self.activeTrades = symbols
    }
    
    func getCurrentRiskMetrics() async -> RiskMetrics {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let calendar = Calendar.current
        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        
        return RiskMetrics(
            dailyPnL: dailyPnL[today] ?? 0,
            dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk,
            hourlyTrades: hourlyTradeCount[currentHour] ?? 0,
            maxHourlyTrades: 3,
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
    
    func resetDailyLimits() async {
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        dailyTradeCount = 0
        godLog("✅ Risk limits reset", level: .success)
    }
}
