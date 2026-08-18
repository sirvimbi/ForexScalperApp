// ScalpingRiskManager.swift - ADAPTIVE POSITION SIZING + NORMALIZED RISK DIAGNOSTICS
import Foundation

actor ScalpingRiskManager: RiskManagerProtocol {
    static let shared = ScalpingRiskManager()

    private var parameters = RiskParameters(accountBalance: 10000, riskPerTrade: 0.008, maxDailyRisk: 0.02, maxConcurrentTrades: 2)
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]
    private var dailyTradeCount: Int = 0
    private var lastResetDate: Date = Date()
    private var symbolATRCache: [String: (atr: Double, timestamp: Date)] = [:]
    private let atrCacheDuration: TimeInterval = 60
    private var averageATRCache: [String: [Double]] = [:]
    private let maxAvgATRCount = 50

    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        godLog("🛡 RISK CONFIG | balance=KES \(String(format: "%.2f", params.accountBalance)) | risk/trade=\(String(format: "%.2f", params.riskPerTrade * 100))% | maxDailyRisk=\(String(format: "%.2f", params.maxDailyRisk * 100))% | maxConcurrent=\(params.maxConcurrentTrades)", level: .info)
    }

    func riskGateDetails(for symbol: String) async -> (allowed: Bool, summary: String) {
        let now = Date()
        let calendar = Calendar.current
        if !calendar.isDate(lastResetDate, inSameDayAs: now) {
            dailyTradeCount = 0
            dailyPnL.removeAll()
            hourlyTradeCount.removeAll()
            consecutiveLosses.removeAll()
            lastResetDate = now
            godLog("🔄 RISK RESET | New trading day | daily/hourly/loss counters reset", level: .info)
        }

        let (maxDaily, hourlyEnabled, maxHourly, cooldown, maxSpreadPips) = await MainActor.run {
            let config = ScalpingConfig.shared
            return (config.maxDailyTrades, config.enableHourlyLimit, config.maxHourlyTrades, config.cooldownSeconds, config.spreadTolerance)
        }

        let dailyLossLimit = parameters.accountBalance * parameters.maxDailyRisk
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0
        let dailyCountOK = dailyTradeCount < maxDaily
        let dailyLossOK = todayPnL > -dailyLossLimit

        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        let hourlyCount = hourlyTradeCount[currentHour] ?? 0
        let hourlyOK = !hourlyEnabled || hourlyCount < maxHourly
        let concurrentOK = activeTrades.count < parameters.maxConcurrentTrades
        let symbolOK = !activeTrades.contains(symbol)
        let losses = consecutiveLosses[symbol] ?? 0
        let lossesOK = losses < 3

        let cooldownRemaining: Int
        if let lastTrade = tradeOpenTime[symbol] {
            cooldownRemaining = max(0, Int(ceil(cooldown - now.timeIntervalSince(lastTrade))))
        } else {
            cooldownRemaining = 0
        }
        let cooldownOK = cooldownRemaining == 0

        var spreadOK = true
        var spreadDetail = "unavailable — fail-open for analysis; execution rechecks broker state"
        if let rawSpreadPoints = try? await MT5Service.shared.getCurrentSpread(symbol: symbol) {
            // MT5 reports broker points while ScalpingConfig.spreadTolerance is in pips.
            // For standard 5/3-digit FX pricing, 10 broker points = 1 pip.
            let spreadPips = rawSpreadPoints / 10.0
            spreadOK = spreadPips <= maxSpreadPips
            spreadDetail = String(format: "raw=%.1f points | normalized=%.2f pips | limit=%.2f pips", rawSpreadPoints, spreadPips, maxSpreadPips)
        }

        let allowed = dailyCountOK && dailyLossOK && hourlyOK && concurrentOK && symbolOK && lossesOK && cooldownOK && spreadOK

        godLog("🛡️ RISK CHECK | \(symbol) | decision=\(allowed ? "ALLOW" : "BLOCK") | daily=\(dailyTradeCount)/\(maxDaily) | dailyPnL=\(String(format: "%.2f", todayPnL))", level: allowed ? .success : .warning)
        godLog("   ├─ \(dailyCountOK ? "✅" : "❌") DailyTradeLimit | count=\(dailyTradeCount)/\(maxDaily)", level: dailyCountOK ? .info : .warning)
        godLog("   ├─ \(dailyLossOK ? "✅" : "❌") DailyLoss | pnl=\(String(format: "%.2f", todayPnL)) | limit=-\(String(format: "%.2f", dailyLossLimit))", level: dailyLossOK ? .info : .warning)
        godLog("   ├─ \(hourlyOK ? "✅" : "❌") HourlyLimit | count=\(hourlyCount)/\(maxHourly) | enabled=\(hourlyEnabled)", level: hourlyOK ? .info : .warning)
        godLog("   ├─ \(concurrentOK ? "✅" : "❌") ConcurrentTrades | active=\(activeTrades.count)/\(parameters.maxConcurrentTrades)", level: concurrentOK ? .info : .warning)
        godLog("   ├─ \(symbolOK ? "✅" : "❌") ActiveSymbol | active=\(activeTrades.contains(symbol))", level: symbolOK ? .info : .warning)
        godLog("   ├─ \(lossesOK ? "✅" : "❌") ConsecutiveLosses | losses=\(losses)/3", level: lossesOK ? .info : .warning)
        godLog("   ├─ \(cooldownOK ? "✅" : "❌") Cooldown | remaining=\(cooldownRemaining)s | configured=\(Int(cooldown))s", level: cooldownOK ? .info : .warning)
        godLog("   └─ \(spreadOK ? "✅" : "❌") Spread | \(spreadDetail)", level: spreadOK ? .info : .warning)

        if !allowed {
            var reasons: [String] = []
            if !dailyCountOK { reasons.append("DailyTradeLimit") }
            if !dailyLossOK { reasons.append("DailyLoss") }
            if !hourlyOK { reasons.append("HourlyLimit") }
            if !concurrentOK { reasons.append("ConcurrentTrades") }
            if !symbolOK { reasons.append("ActiveSymbol") }
            if !lossesOK { reasons.append("ConsecutiveLosses") }
            if !cooldownOK { reasons.append("Cooldown") }
            if !spreadOK { reasons.append("Spread") }
            godLog("🛑 RISK BLOCK REASONS | \(symbol) | \(reasons.joined(separator: ", "))", level: .warning)
        }

        godLog("🛡️ RISK SUMMARY | \(symbol) | \(allowed ? "EXECUTION ALLOWED" : "EXECUTION BLOCKED") | signal analysis remains independent", level: allowed ? .success : .warning)
        return (allowed, "dailyTrades=\(dailyTradeCount)/\(maxDaily), dailyPnL=\(String(format: "%.2f", todayPnL)), hourly=\(hourlyCount)/\(maxHourly), active=\(activeTrades.count)/\(parameters.maxConcurrentTrades), symbolActive=\(activeTrades.contains(symbol)), consecutiveLosses=\(losses), cooldown=\(cooldownRemaining)s, spread=\(spreadDetail)")
    }

    /// Analysis-stage gate: signal calculation continues even when execution risk is blocked.
    /// Actual execution is re-checked immediately before position sizing/order placement.
    func canOpenTrade(for symbol: String) async -> Bool {
        // Diagnostic check - we don't block here because the coordinator handles the accept/deny flow
        return true
    }

    private func getPipSize(for symbol: String) async -> Double {
        do {
            let info = try await MT5Service.shared.getSymbolInfo(symbol)
            if let point = info.point, point > 0 {
                // For standard FX, 1 pip = 10 points. For indices/gold, we usually treat 1 point as 1 pip equivalent in this engine's math
                let normalizedSymbol = symbol.uppercased()
                if normalizedSymbol.contains("JPY") || normalizedSymbol.contains("XAU") || normalizedSymbol.contains("XAG") {
                    return point * 10.0 // Gold 0.1, JPY 0.01
                } else if normalizedSymbol.contains("OIL") || normalizedSymbol.contains("US30") || normalizedSymbol.contains("NAS") || normalizedSymbol.contains("GER") {
                    return point // 1.0 or 0.1 depending on broker
                }
                return point * 10.0 // Default 0.0001
            }
        } catch {
            godLog("⚠️ RISK | Could not get dynamic point size for \(symbol), using fallback", level: .warning)
        }
        return symbol.contains("JPY") || symbol.contains("XAU") ? 0.01 : 0.0001
    }

    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let risk = await riskGateDetails(for: signal.symbol)
        guard risk.allowed else {
            godLog("🛑 EXECUTION BLOCKED | \(signal.symbol) | position sizing aborted | risk gate failed", level: .warning)
            return nil
        }

        let (useManual, manualSize, minMult, maxMult, fixedSL, useFixed) = await MainActor.run {
            let config = ScalpingConfig.shared
            return (config.useManualLot, config.manualLotSize, config.volatilityMultiplierMin, config.volatilityMultiplierMax, config.fixedSLPips, config.useFixedSL)
        }
        let balance = parameters.accountBalance
        let baseRiskAmount = balance * parameters.riskPerTrade
        let atr = await getATR(symbol: signal.symbol)
        let pipSize = await getPipSize(for: signal.symbol)
        let atrPips = atr / pipSize
        let volatilityMultiplier = getATRMultiplier(symbol: signal.symbol, currentATR: atr, minMult: minMult, maxMult: maxMult)
        let adjustedRiskAmount = baseRiskAmount * volatilityMultiplier
        let slPips = useFixed ? fixedSL : max(6.0, min(15.0, atrPips * 1.5))
        let slDistance = slPips * pipSize
        let tpPips = max(8.0, min(25.0, atrPips * 2.5))
        let tpDistance = tpPips * pipSize
        var lotSize: Double
        if useManual {
            lotSize = manualSize
            godLog("🛡 Risk Manager: Using manual lot size: \(lotSize)", level: .info)
        } else {
            let kesToUsdRate = 130.0
            let riskInUsd = adjustedRiskAmount / kesToUsdRate
            lotSize = min(riskInUsd / (slDistance * 100000), 0.1)
            let losses = consecutiveLosses[signal.symbol] ?? 0
            if losses >= 2 { lotSize *= 0.5 }
            if losses >= 3 { lotSize *= 0.5 }
        }
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)
        let steps = round(lotSize / limits.step)
        lotSize = max(limits.min, min(steps * limits.step, limits.max))
        let stopLoss = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let takeProfit = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance
        return PositionSize(units: lotSize, stopLoss: stopLoss, takeProfit: takeProfit, riskAmount: adjustedRiskAmount, potentialReward: adjustedRiskAmount * 1.5)
    }

    private func getAverageATR(symbol: String, currentATR: Double) -> Double {
        var history = averageATRCache[symbol] ?? []
        history.append(currentATR)
        if history.count > maxAvgATRCount { history.removeFirst() }
        averageATRCache[symbol] = history
        let sum = history.reduce(0, +)
        return history.isEmpty ? currentATR : sum / Double(history.count)
    }

    private func getATRMultiplier(symbol: String, currentATR: Double, minMult: Double, maxMult: Double) -> Double {
        let avgATR = getAverageATR(symbol: symbol, currentATR: currentATR)
        guard avgATR > 0 else { return 1.0 }
        return min(max(currentATR / avgATR, minMult), maxMult)
    }

    private func getATR(symbol: String) async -> Double {
        if let cached = symbolATRCache[symbol], Date().timeIntervalSince(cached.timestamp) < atrCacheDuration { return cached.atr }
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

    func syncActiveTrades(_ symbols: Set<String>) {
        self.activeTrades = symbols
        godLog("🛡️ RISK SYNC | activeTrades=\(symbols.sorted().joined(separator: ", ")) | count=\(symbols.count)", level: .info)
    }

    func getCurrentRiskMetrics() async -> RiskMetrics {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let calendar = Calendar.current
        let currentHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        let maxHourly = await MainActor.run { ScalpingConfig.shared.maxHourlyTrades }
        return RiskMetrics(dailyPnL: dailyPnL[today] ?? 0, dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk, hourlyTrades: hourlyTradeCount[currentHour] ?? 0, maxHourlyTrades: maxHourly, activeTrades: activeTrades.count, maxConcurrentTrades: parameters.maxConcurrentTrades, consecutiveLosses: consecutiveLosses)
    }
}