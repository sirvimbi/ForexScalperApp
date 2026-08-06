// ScalpingRiskManager.swift - ADAPTIVE POSITION SIZING
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
    private var symbolATRCache: [String: (atr: Double, timestamp: Date)] = [:]
    private let atrCacheDuration: TimeInterval = 60
    
    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        godLog("🛡 Risk Manager: Updated balance to KES \(String(format: "%.2f", params.accountBalance))", level: .info)
    }
    
    func canOpenTrade(for symbol: String) async -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        if !calendar.isDate(lastResetDate, inSameDayAs: now) {
            dailyTradeCount = 0
            dailyPnL.removeAll()
            lastResetDate = now
        }
        
        let maxDaily = await MainActor.run { ScalpingConfig.shared.maxDailyTrades }
        guard dailyTradeCount < maxDaily else { return false }
        
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        let maxLoss = parameters.accountBalance * parameters.maxDailyRisk
        if todayPnL <= -maxLoss { return false }
        
        let (hourlyEnabled, maxHourly) = await MainActor.run { 
            (ScalpingConfig.shared.enableHourlyLimit, ScalpingConfig.shared.maxHourlyTrades)
        }
        if hourlyEnabled {
            let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
            let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
            if hourlyTrades >= maxHourly { return false }
        }
        
        if activeTrades.count >= parameters.maxConcurrentTrades { return false }
        if activeTrades.contains(symbol) { return false }
        
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 3 { return false }
        
        let cooldown = await MainActor.run { ScalpingConfig.shared.cooldownSeconds }
        if let lastTrade = tradeOpenTime[symbol], now.timeIntervalSince(lastTrade) < cooldown { return false }
        
        if let spread = try? await MT5Service.shared.getCurrentSpread(symbol: symbol) {
            let symbolConfig = await MainActor.run { ScalpingConfig.shared.getSymbolConfig(symbol) }
            if spread > symbolConfig.maxSpread { return false }
        }
        
        return true
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let (useManual, manualSize) = await MainActor.run {
            (ScalpingConfig.shared.useManualLot, ScalpingConfig.shared.manualLotSize)
        }
        
        let balance = parameters.accountBalance
        let riskAmount = balance * parameters.riskPerTrade
        
        let atr = await getATR(symbol: signal.symbol)
        let pipSize = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        let atrPips = atr / pipSize
        
        let slPips = max(6.0, min(15.0, atrPips * 1.5))
        let slDistance = slPips * pipSize
        
        let tpPips = max(8.0, min(25.0, atrPips * 2.5))
        let tpDistance = tpPips * pipSize
        
        var lotSize: Double
        
        if useManual {
            lotSize = manualSize
            godLog("🛡 Risk Manager: Using manual lot size: \(lotSize)", level: .info)
        } else {
            let kesToUsdRate = 130.0
            let riskInUsd = riskAmount / kesToUsdRate
            lotSize = riskInUsd / (slDistance * 100000)
            
            // 1. Hard cap before broker limits
            lotSize = min(lotSize, 0.1) // Increased cap to 0.1 for more flexibility
            
            // 2. Reduce risk based on performance
            let losses = consecutiveLosses[signal.symbol] ?? 0
            if losses >= 2 { lotSize *= 0.5 }
            if losses >= 3 { lotSize *= 0.5 }
        }
        
        // 3. Apply broker limits (Final step ensures validity)
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)
        let steps = round(lotSize / limits.step)
        lotSize = max(limits.min, min(steps * limits.step, limits.max))
        
        let stopLoss = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let takeProfit = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance
        
        return PositionSize(
            units: lotSize,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            riskAmount: riskAmount,
            potentialReward: riskAmount * 1.5
        )
    }
    
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
            return symbol.contains("JPY") ? 0.15 : 0.0015
        }
    }
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
        dailyTradeCount += 1
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
        godLog("📊 MT5 Trade Registered: \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice))", level: .trade)
    }
    
    func closeTrade(_ trade: TradeRecord) async {
        activeTrades.remove(trade.symbol)
        if let pnl = trade.pnl {
            let today = Calendar.current.startOfDay(for: Date())
            dailyPnL[today] = (dailyPnL[today] ?? 0) + pnl
            if pnl < 0 { consecutiveLosses[trade.symbol] = (consecutiveLosses[trade.symbol] ?? 0) + 1 }
            else { consecutiveLosses[trade.symbol] = 0 }
        }
    }
    
    func syncActiveTrades(_ symbols: Set<String>) { self.activeTrades = symbols }
    
    func getCurrentRiskMetrics() async -> RiskMetrics {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let calendar = Calendar.current
        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        let maxHourly = await MainActor.run { ScalpingConfig.shared.maxHourlyTrades }
        return RiskMetrics(
            dailyPnL: dailyPnL[today] ?? 0,
            dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk,
            hourlyTrades: hourlyTradeCount[currentHour] ?? 0,
            maxHourlyTrades: maxHourly,
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
}