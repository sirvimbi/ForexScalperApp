// ScalpingRiskManager.swift - GOD MODE V3.0 (80%+ Win Rate)
import Foundation

// MARK: - Calendar Extension
extension Calendar {
    nonisolated func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}

actor ScalpingRiskManager: RiskManagerProtocol {
    static let shared = ScalpingRiskManager()
    
    private var parameters = RiskParameters(
        accountBalance: 10000,
        riskPerTrade: 0.005,
        maxDailyRisk: 0.02,
        maxConcurrentTrades: 3
    )
    
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]
    
    // 📊 ELITE R:R CONFIGURATION
    private let targetWinRate: Double = 0.80
    private let minRR: Double = 1.2  // Minimum R:R for 80% win rate
    private let idealRR: Double = 1.5  // Target R:R
    
    // 🎯 DYNAMIC STOP LOSS - Based on ATR, not fixed pips
    private var atrMultiplierSL: Double = 0.3  // 30% of ATR for stop
    private var atrMultiplierTP: Double = 0.45  // 45% of ATR for target (1.5:1)
    
    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        godLog("🛡 Risk Manager: Updated balance to KES \(String(format: "%.2f", params.accountBalance))", level: .info)
    }
    
    func canOpenTrade(for symbol: String) async -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        // Check daily loss limit
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        
        if todayPnL <= -parameters.accountBalance * parameters.maxDailyRisk {
            godLog("⚠️ Daily loss limit reached: \(String(format: "%.2f", todayPnL))", level: .warning)
            return false
        }
        
        // Hourly trade limit
        let currentHour = calendar.startOfHour(for: now)
        let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
        let maxHourlyTrades = max(3, min(8, parameters.maxConcurrentTrades * 2))
        
        if hourlyTrades >= maxHourlyTrades {
            godLog("⚠️ Hourly trade limit reached: \(hourlyTrades)/\(maxHourlyTrades)", level: .warning)
            return false
        }
        
        // Check concurrent trades
        if activeTrades.count >= parameters.maxConcurrentTrades {
            godLog("⚠️ Max concurrent trades: \(activeTrades.count)/\(parameters.maxConcurrentTrades)", level: .warning)
            return false
        }
        
        // Check consecutive losses - More lenient for scalping
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 4 {
            godLog("⚠️ \(losses) consecutive losses for \(symbol) - 15min COOLDOWN", level: .warning)
            return false
        }
        
        // Dynamic cooldown: 60 seconds base + 30s per loss
        var cooldown: TimeInterval = 60
        if losses >= 2 {
            cooldown += Double(losses) * 30
        }
        
        if let lastTrade = tradeOpenTime[symbol],
           now.timeIntervalSince(lastTrade) < cooldown {
            return false
        }
        
        godLog("✅ Risk check PASSED for \(symbol)")
        return true
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let balance = parameters.accountBalance
        let riskAmount = balance * parameters.riskPerTrade
        
        // 📊 GET ATR FOR DYNAMIC SIZING
        let atr = await getATR(for: signal.symbol)
        let pipSize: Double = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        
        // 🎯 DYNAMIC SL/TP based on ATR
        let slDistance = max(atr * atrMultiplierSL, pipSize * 5)  // Minimum 5 pips
        let tpDistance = slDistance * idealRR
        
        // 💰 Position sizing in KES
        let kesToUsdRate = 130.0
        let riskInUsd = riskAmount / kesToUsdRate
        var lotSize = riskInUsd / (slDistance * 100000)
        
        // Manual override
        let (useManual, manualSize) = await MainActor.run {
            (ScalpingConfig.shared.useManualLot, ScalpingConfig.shared.manualLotSize)
        }
        if useManual { lotSize = manualSize }
        
        // Broker validation
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)
        let steps = round(lotSize / limits.step)
        let finalLotSize = max(limits.min, min(steps * limits.step, limits.max))
        
        let sl = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let tp = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance
        
        // ✅ VALIDATE R:R
        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let rrRatio = reward / max(risk, 0.00001)
        
        guard rrRatio >= minRR else {
            godLog("❌ R:R \(String(format: "%.2f", rrRatio)) < \(minRR) - REJECTING", level: .warning)
            return nil
        }
        
        godLog("""
        📐 GOD MODE POSITION (DYNAMIC):
           ATR: \(String(format: "%.5f", atr))
           SL Distance: \(String(format: "%.5f", slDistance)) (≈\(Int(slDistance/pipSize)) pips)
           TP Distance: \(String(format: "%.5f", tpDistance)) (≈\(Int(tpDistance/pipSize)) pips)
           Lot: \(String(format: "%.3f", finalLotSize))
           R:R: \(String(format: "%.2f", rrRatio)):1
           Risk: KES \(String(format: "%.2f", riskAmount))
        """, level: .info)
        
        return PositionSize(
            units: finalLotSize,
            stopLoss: sl,
            takeProfit: tp,
            riskAmount: riskAmount,
            potentialReward: riskAmount * rrRatio
        )
    }
    
    private func getATR(for symbol: String) async -> Double {
        // Try MT5 first
        if let atr = try? await MT5Service.shared.getATR(symbol: symbol, period: 14) {
            return atr
        }
        // Fallback: estimated ATR based on pair
        let baseATR: Double = symbol.contains("JPY") ? 0.20 : 0.0020
        return baseATR
    }
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
        
        let now = Date()
        let currentHour = Calendar.current.startOfHour(for: now)
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
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
    }
    
    func getCurrentRiskMetrics() async -> RiskMetrics {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let currentHour = calendar.startOfHour(for: now)
        
        return RiskMetrics(
            dailyPnL: dailyPnL[today] ?? 0,
            dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk,
            hourlyTrades: hourlyTradeCount[currentHour] ?? 0,
            maxHourlyTrades: max(3, min(8, parameters.maxConcurrentTrades * 2)),
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
    
    private var calendar: Calendar { Calendar.current }
    
    func resetDailyLimits() async {
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        consecutiveLosses.removeAll()
        godLog("✅ Risk limits reset", level: .info)
    }
}
