// ScalpingRiskManager.swift - GOD MODE V3.2 MT5 OPTIMIZED
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
        maxDailyRisk: 0.05,   // Optimized: 5% (was 2%)
        maxConcurrentTrades: 3
    )
    
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]
    private var symbolATRCache: [String: (atr: Double, timestamp: Date)] = [:]
    private let atrCacheDuration: TimeInterval = 60
    
    // 📊 ELITE R:R CONFIGURATION
    private let targetWinRate: Double = 0.80
    private var minRR: Double = 1.2
    private var idealRR: Double = 1.5
    private let maxRR: Double = 2.0
    
    // 🎯 DYNAMIC ATR SHIELDS
    private var atrMultiplierSL: Double = 0.35
    private var atrMultiplierTP: Double = 0.50
    
    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        godLog("🛡 Risk Manager: Updated balance to KES \(String(format: "%.2f", params.accountBalance))", level: .info)
        
        if params.accountBalance > 50000 {
            minRR = 1.3
            idealRR = 1.6
        }
    }
    
    func refreshATR(symbol: String) async {
        symbolATRCache.removeValue(forKey: symbol)
    }
    
    func canOpenTrade(for symbol: String) async -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        
        if todayPnL <= -parameters.accountBalance * parameters.maxDailyRisk {
            godLog("⚠️ Daily loss limit reached: KES \(String(format: "%.2f", todayPnL))", level: .warning)
            return false
        }
        
        let isInProfit = todayPnL > 0
        let currentHour = calendar.startOfHour(for: now)
        let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
        let maxHourlyTrades = isInProfit ? max(4, min(10, parameters.maxConcurrentTrades * 2)) : max(2, min(6, parameters.maxConcurrentTrades * 2))
        
        if hourlyTrades >= maxHourlyTrades {
            godLog("⚠️ Hourly limit reached: \(hourlyTrades)/\(maxHourlyTrades)", level: .warning)
            return false
        }
        
        if activeTrades.count >= parameters.maxConcurrentTrades {
            godLog("⚠️ Max concurrent: \(activeTrades.count)/\(parameters.maxConcurrentTrades)", level: .warning)
            return false
        }
        
        guard await MT5Service.shared.isSymbolTradable(symbol) else {
            godLog("⚠️ \(symbol) not tradable on MT5", level: .warning)
            return false
        }
        
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 4 {
            godLog("⚠️ \(losses) consecutive losses for \(symbol) - 15min COOLDOWN", level: .warning)
            return false
        }
        
        var cooldown: TimeInterval = 45
        if losses >= 2 { cooldown += Double(losses) * 30 }
        
        let hour = calendar.component(.hour, from: now)
        if hour >= 0 && hour < 6 { cooldown *= 1.5 }
        
        if let lastTrade = tradeOpenTime[symbol], now.timeIntervalSince(lastTrade) < cooldown {
            return false
        }
        
        if let spread = try? await MT5Service.shared.getCurrentSpread(symbol: symbol) {
            let maxSpread = symbol.contains("JPY") ? 8.0 : 5.0
            if spread > maxSpread {
                godLog("⚠️ Spread too high: \(String(format: "%.1f", spread)) pips", level: .warning)
                return false
            }
        }
        
        godLog("✅ Risk check PASSED for \(symbol)")
        return true
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let balance = parameters.accountBalance
        let riskAmount = balance * parameters.riskPerTrade
        
        let atr = await getATRFromMT5(symbol: signal.symbol)
        let pipSize: Double = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        
        let marketMultiplier = await getMarketMultiplier()
        let slMultiplier = atrMultiplierSL * marketMultiplier
        
        let slDistance = max(atr * slMultiplier, pipSize * 5)
        let tpDistance = slDistance * idealRR
        
        let kesToUsdRate = await getKESTousdRate()
        let riskInUsd = riskAmount / kesToUsdRate
        var lotSize = riskInUsd / (slDistance * 100000)
        
        let (useManual, manualSize) = await MainActor.run { (ScalpingConfig.shared.useManualLot, ScalpingConfig.shared.manualLotSize) }
        if useManual { lotSize = manualSize }
        
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)
        let steps = round(lotSize / limits.step)
        let finalLotSize = max(limits.min, min(steps * limits.step, limits.max))
        
        let sl = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let tp = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance
        
        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let rrRatio = reward / max(risk, 0.00001)
        
        var finalTP = tp
        var finalRR = rrRatio
        if rrRatio < minRR {
            let minTPDistance = risk * minRR
            finalTP = signal.type == .buy ? signal.price + minTPDistance : signal.price - minTPDistance
            finalRR = minRR
        }
        
        if finalRR > maxRR {
            let cappedTPDistance = risk * maxRR
            finalTP = signal.type == .buy ? signal.price + cappedTPDistance : signal.price - cappedTPDistance
            finalRR = maxRR
        }
        
        godLog("""
        📐 GOD MODE POSITION (MT5 OPTIMIZED):
           Symbol: \(signal.symbol)
           ATR: \(String(format: "%.5f", atr))
           SL: \(String(format: "%.5f", sl)) (≈\(Int(slDistance/pipSize)) pips)
           TP: \(String(format: "%.5f", finalTP)) (≈\(Int(abs(finalTP - signal.price)/pipSize)) pips)
           Lot: \(String(format: "%.3f", finalLotSize))
           R:R: \(String(format: "%.2f", finalRR)):1
        """, level: .info)
        
        return PositionSize(units: finalLotSize, stopLoss: sl, takeProfit: finalTP, riskAmount: riskAmount, potentialReward: riskAmount * finalRR)
    }
    
    private func getATRFromMT5(symbol: String) async -> Double {
        if let cached = symbolATRCache[symbol], Date().timeIntervalSince(cached.timestamp) < atrCacheDuration {
            return cached.atr
        }
        
        do {
            let atr = try await MT5Service.shared.getATR(symbol: symbol, period: 14)
            symbolATRCache[symbol] = (atr: atr, timestamp: Date())
            return atr
        } catch {
            let defaultATR = symbol.contains("JPY") ? 0.20 : 0.0020
            godLog("⚠️ Using default ATR for \(symbol): \(defaultATR)", level: .warning)
            return defaultATR
        }
    }
    
    private func getMarketMultiplier() async -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 0 && hour < 6 { return 0.8 }
        if hour >= 8 && hour < 10 { return 1.2 }
        if hour >= 14 && hour < 16 { return 1.3 }
        return 1.0
    }
    
    private func getKESTousdRate() async -> Double {
        if let account = try? await MT5Service.shared.getAccountInfo() {
            if account.currency.uppercased() == "KES" { return 1.0 }
        }
        return 130.0
    }
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
        let currentHour = Calendar.current.startOfHour(for: Date())
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
        godLog("📊 MT5 Trade Registered: \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice))")
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
        let today = Calendar.current.startOfDay(for: now)
        let currentHour = Calendar.current.startOfHour(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        let isInProfit = todayPnL > 0
        
        return RiskMetrics(
            dailyPnL: todayPnL,
            dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk,
            hourlyTrades: hourlyTradeCount[currentHour] ?? 0,
            maxHourlyTrades: isInProfit ? max(4, min(10, parameters.maxConcurrentTrades * 2)) : max(2, min(6, parameters.maxConcurrentTrades * 2)),
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
    
    func resetDailyLimits() async {
        dailyPnL.removeAll(); hourlyTradeCount.removeAll(); consecutiveLosses.removeAll(); symbolATRCache.removeAll()
        godLog("✅ MT5 Risk limits reset")
    }
}
