// ScalpingRiskManager.swift - GOD MODE V3.1 MT5 OPTIMIZED
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
        riskPerTrade: 0.005,  // 0.5% risk per trade
        maxDailyRisk: 0.02,   // 2% max daily loss
        maxConcurrentTrades: 3
    )
    
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]
    private var symbolATRCache: [String: (atr: Double, timestamp: Date)] = [:]
    private let atrCacheDuration: TimeInterval = 60 // Cache ATR for 60 seconds
    
    // 🎯 ELITE R:R CONFIGURATION FOR 80%+ WIN RATE
    private let targetWinRate: Double = 0.80
    private var minRR: Double = 1.2   // Dynamic: 1.2-1.5
    private var idealRR: Double = 1.5
    private let maxRR: Double = 2.0   // Cap to prevent over-reaching
    
    // 📊 MT5-SPECIFIC: Dynamic SL based on ATR from MT5
    private var atrMultiplierSL: Double = 0.35  // 35% of ATR for SL
    private var atrMultiplierTP: Double = 0.50  // 50% of ATR for TP (1.43:1)
    
    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        godLog("🛡 Risk Manager: Updated balance to KES \(String(format: "%.2f", params.accountBalance))", level: .info)
        
        // Auto-adjust R:R based on balance
        if params.accountBalance > 50000 {
            minRR = 1.3
            idealRR = 1.6
        } else if params.accountBalance > 100000 {
            minRR = 1.5
            idealRR = 1.8
        }
    }
    
    func canOpenTrade(for symbol: String) async -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        // 1. Check daily loss limit
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        
        if todayPnL <= -parameters.accountBalance * parameters.maxDailyRisk {
            godLog("⚠️ Daily loss limit reached: KES \(String(format: "%.2f", todayPnL))", level: .warning)
            return false
        }
        
        // 2. Check if account is in profit for the day (allow more trades)
        let isInProfit = todayPnL > 0
        
        // 3. Hourly trade limit (higher when in profit)
        let currentHour = calendar.startOfHour(for: now)
        let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
        let maxHourlyTrades = isInProfit ? 
            max(4, min(10, parameters.maxConcurrentTrades * 2)) : 
            max(2, min(6, parameters.maxConcurrentTrades * 2))
        
        if hourlyTrades >= maxHourlyTrades {
            godLog("⚠️ Hourly limit reached: \(hourlyTrades)/\(maxHourlyTrades)", level: .warning)
            return false
        }
        
        // 4. Check concurrent trades
        if activeTrades.count >= parameters.maxConcurrentTrades {
            godLog("⚠️ Max concurrent: \(activeTrades.count)/\(parameters.maxConcurrentTrades)", level: .warning)
            return false
        }
        
        // 5. MT5-SPECIFIC: Check if symbol is tradable
        guard await MT5Service.shared.isSymbolTradable(symbol) else {
            godLog("⚠️ \(symbol) not tradable on MT5", level: .warning)
            return false
        }
        
        // 6. Consecutive losses - Adaptive cooldown
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 3 {
            let cooldownMinutes = losses >= 5 ? 30 : 15
            godLog("⚠️ \(losses) consecutive losses - \(cooldownMinutes)min COOLDOWN for \(symbol)", level: .warning)
            return false
        }
        
        // 7. Dynamic cooldown based on MT5 market hours
        var cooldown: TimeInterval = 45 // Base 45 seconds
        if losses >= 2 { cooldown += Double(losses) * 30 }
        
        // Extended cooldown during low liquidity (Asian session)
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 0 && hour < 6 { cooldown *= 1.5 }
        
        if let lastTrade = tradeOpenTime[symbol],
           now.timeIntervalSince(lastTrade) < cooldown {
            return false
        }
        
        // 8. MT5-SPECIFIC: Check spread via MT5
        let spread = try? await MT5Service.shared.getCurrentSpread(symbol: symbol)
        if let spread = spread {
            let maxSpread = symbol.contains("JPY") ? 8.0 : 5.0 // In pips
            if spread > maxSpread {
                godLog("⚠️ Spread too high: \(String(format: "%.1f", spread)) pips", level: .warning)
                return false
            }
        }
        
        godLog("✅ Risk check PASSED for \(symbol) [Hourly: \(hourlyTrades)/\(maxHourlyTrades)]")
        return true
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let balance = parameters.accountBalance
        let riskAmount = balance * parameters.riskPerTrade
        
        // 📊 GET ATR FROM MT5 (with caching)
        let atr = await getATRFromMT5(symbol: signal.symbol)
        let pipSize: Double = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        
        // 🎯 DYNAMIC SL/TP based on ATR and market conditions
        let marketMultiplier = await getMarketMultiplier()
        let slMultiplier = atrMultiplierSL * marketMultiplier
        let tpMultiplier = atrMultiplierTP * marketMultiplier
        
        let slDistance = max(atr * slMultiplier, pipSize * 5)  // Minimum 5 pips
        let tpDistance = slDistance * idealRR
        
        // 💰 Position sizing for KES account via MT5
        let kesToUsdRate = await getKESTousdRate()
        let riskInUsd = riskAmount / kesToUsdRate
        var lotSize = riskInUsd / (slDistance * 100000)
        
        // ⚡ Manual override from settings
        let (useManual, manualSize) = await MainActor.run {
            (ScalpingConfig.shared.useManualLot, ScalpingConfig.shared.manualLotSize)
        }
        if useManual { lotSize = manualSize }
        
        // 🔧 MT5 Volume validation
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)
        let steps = round(lotSize / limits.step)
        let finalLotSize = max(limits.min, min(steps * limits.step, limits.max))
        
        // 🎯 Calculate SL and TP
        let sl = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let tp = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance
        
        // ✅ Validate R:R
        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let rrRatio = reward / max(risk, 0.00001)
        
        // If R:R is below minimum, adjust TP to meet minimum
        var finalTP = tp
        var finalRR = rrRatio
        if rrRatio < minRR {
            let minTPDistance = risk * minRR
            finalTP = signal.type == .buy ? signal.price + minTPDistance : signal.price - minTPDistance
            finalRR = minRR
            godLog("⚠️ R:R \(String(format: "%.2f", rrRatio)) adjusted to \(String(format: "%.2f", minRR))", level: .info)
        }
        
        // Cap R:R to prevent unrealistic targets
        if finalRR > maxRR {
            let cappedTPDistance = risk * maxRR
            finalTP = signal.type == .buy ? signal.price + cappedTPDistance : signal.price - cappedTPDistance
            finalRR = maxRR
        }
        
        godLog("""
        📐 GOD MODE POSITION (MT5 OPTIMIZED):
           Symbol: \(signal.symbol)
           ATR: \(String(format: "%.5f", atr))
           SL: \(String(format: "%.5f", sl)) (\(Int(slDistance/pipSize)) pips)
           TP: \(String(format: "%.5f", finalTP)) (\(Int(abs(finalTP - signal.price)/pipSize)) pips)
           Lot: \(String(format: "%.3f", finalLotSize))
           R:R: \(String(format: "%.2f", finalRR)):1
           Risk: KES \(String(format: "%.2f", riskAmount))
        """, level: .info)
        
        return PositionSize(
            units: finalLotSize,
            stopLoss: sl,
            takeProfit: finalTP,
            riskAmount: riskAmount,
            potentialReward: riskAmount * finalRR
        )
    }
    
    // MARK: - MT5-SPECIFIC HELPERS
    
    private func getATRFromMT5(symbol: String) async -> Double {
        // Check cache first
        if let cached = symbolATRCache[symbol],
           Date().timeIntervalSince(cached.timestamp) < atrCacheDuration {
            return cached.atr
        }
        
        // Fetch from MT5
        do {
            let atr = try await MT5Service.shared.getATR(symbol: symbol, period: 14)
            symbolATRCache[symbol] = (atr: atr, timestamp: Date())
            return atr
        } catch {
            // Fallback: use symbol-specific default
            let defaultATR = symbol.contains("JPY") ? 0.20 : 0.0020
            godLog("⚠️ ATR fetch failed for \(symbol): \(error.localizedDescription). Using default: \(defaultATR)", level: .warning)
            return defaultATR
        }
    }
    
    private func getMarketMultiplier() async -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Asian session: lower volatility, tighter stops
        if hour >= 0 && hour < 6 { return 0.8 }
        // London open: higher volatility, wider stops
        if hour >= 8 && hour < 10 { return 1.2 }
        // US open: highest volatility
        if hour >= 14 && hour < 16 { return 1.3 }
        // London close: normal
        if hour >= 16 && hour < 18 { return 1.1 }
        // Default
        return 1.0
    }
    
    private func getKESTousdRate() async -> Double {
        // Try to get from MT5 account info
        if let account = try? await MT5Service.shared.getAccountInfo() {
            // If account currency is KES, use 1:1
            if account.currency.uppercased() == "KES" {
                return 1.0
            }
            // Otherwise use a reasonable default
        }
        return 130.0 // Conservative KES/USD rate
    }
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
        
        let now = Date()
        let currentHour = Calendar.current.startOfHour(for: now)
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
        
        // MT5: Log to terminal for verification
        godLog("📊 MT5 Trade Registered: \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice))", level: .info)
    }
    
    func closeTrade(_ trade: TradeRecord) async {
        activeTrades.remove(trade.symbol)
        
        if let pnl = trade.pnl {
            let today = Calendar.current.startOfDay(for: Date())
            dailyPnL[today] = (dailyPnL[today] ?? 0) + pnl
            
            if pnl < 0 {
                consecutiveLosses[trade.symbol] = (consecutiveLosses[trade.symbol] ?? 0) + 1
                godLog("📉 Loss streak: \(consecutiveLosses[trade.symbol] ?? 0) for \(trade.symbol)", level: .warning)
            } else {
                consecutiveLosses[trade.symbol] = 0
                godLog("📈 Win registered for \(trade.symbol) - P&L: KES \(String(format: "%.2f", pnl))", level: .success)
            }
            
            // MT5: Update daily P&L in terminal
            let totalPnL = dailyPnL[today] ?? 0
            if abs(totalPnL) > 0 {
                godLog("💰 Daily P&L Update: KES \(String(format: "%.2f", totalPnL))", level: .info)
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
            maxHourlyTrades: isInProfit ? 
                max(4, min(10, parameters.maxConcurrentTrades * 2)) : 
                max(2, min(6, parameters.maxConcurrentTrades * 2)),
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
    
    func resetDailyLimits() async {
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        consecutiveLosses.removeAll()
        symbolATRCache.removeAll()
        godLog("✅ MT5 Risk limits reset", level: .info)
    }
}
