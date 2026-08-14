// MARK: - Enhanced RiskManager
import Foundation

actor RefactoredRiskManager: RiskManagerProtocol {
    static let shared = RefactoredRiskManager()
    
    private var parameters = RiskParameters(
        accountBalance: 10000,
        riskPerTrade: 0.01,
        maxDailyRisk: 0.03,
        maxConcurrentTrades: 3
    )
    
    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    
    func updateParameters(_ params: RiskParameters) {
        parameters = params
        godLog("🛡️ RISK CONFIG | balance=\(String(format: "%.2f", params.accountBalance)) | risk/trade=\(String(format: "%.2f", params.riskPerTrade * 100))% | maxDailyRisk=\(String(format: "%.2f", params.maxDailyRisk * 100))% | maxConcurrent=\(params.maxConcurrentTrades)", level: .diagnostic)
    }

    /// Full, non-mutating risk-gate explanation used by the signal engine.
    /// The returned checks are intentionally human-readable so the runtime console
    /// can show exactly why a symbol was allowed or rejected.
    func riskGateDetails(for symbol: String) -> (allowed: Bool, checks: [String]) {
        let today = Calendar.current.startOfDay(for: Date())
        let todayPnL = dailyPnL[today] ?? 0
        let dailyLimit = parameters.accountBalance * parameters.maxDailyRisk
        let dailyLossOK = todayPnL > -dailyLimit

        let activeSymbolOK = !activeTrades.contains(symbol)
        let concurrentOK = activeTrades.count < parameters.maxConcurrentTrades

        let cooldownSeconds: TimeInterval = 300
        let cooldownRemaining: Int
        if let lastTrade = tradeOpenTime[symbol] {
            cooldownRemaining = max(0, Int(ceil(cooldownSeconds - Date().timeIntervalSince(lastTrade))))
        } else {
            cooldownRemaining = 0
        }
        let cooldownOK = cooldownRemaining == 0

        var checks: [String] = []
        checks.append("DailyLoss \(dailyLossOK ? "PASS" : "FAIL") | PnL=\(String(format: "%.2f", todayPnL)) | limit=-\(String(format: "%.2f", dailyLimit))")
        checks.append("ActiveSymbol \(activeSymbolOK ? "PASS" : "FAIL") | active=\(activeTrades.contains(symbol))")
        checks.append("ConcurrentTrades \(concurrentOK ? "PASS" : "FAIL") | activeCount=\(activeTrades.count)/\(parameters.maxConcurrentTrades)")
        checks.append("SymbolCooldown \(cooldownOK ? "PASS" : "FAIL") | remaining=\(cooldownRemaining)s")

        let allowed = dailyLossOK && activeSymbolOK && concurrentOK && cooldownOK
        godLog("🛡️ RISK CHECK | \(symbol) | DailyLoss=\(dailyLossOK ? "PASS" : "FAIL") | ActiveSymbol=\(activeSymbolOK ? "PASS" : "FAIL") | Concurrent=\(concurrentOK ? "PASS" : "FAIL") | Cooldown=\(cooldownOK ? "PASS" : "FAIL")", level: allowed ? .success : .warning)

        for check in checks {
            let passed = check.contains(" PASS ")
            godLog("   ├─ \(passed ? "✅" : "❌") \(check)", level: passed ? .diagnostic : .warning)
        }

        godLog("🛡️ RISK DECISION | \(symbol) | \(allowed ? "ALLOW" : "BLOCK") | balance=\(String(format: "%.2f", parameters.accountBalance)) | risk/trade=\(String(format: "%.2f", parameters.riskPerTrade * 100))% | dailyPnL=\(String(format: "%.2f", todayPnL))", level: allowed ? .success : .warning)
        return (allowed, checks)
    }
    
    func canOpenTrade(for symbol: String) async -> Bool {
        return riskGateDetails(for: symbol).allowed
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let riskAmount = parameters.accountBalance * parameters.riskPerTrade
        
        let kesToUsdRate = 130.0
        let riskInUsd = riskAmount / kesToUsdRate
        
        let volatility = signal.volume > 0 ? signal.volume / 1000 : 0.001
        let baseUnits = riskInUsd / (signal.price * volatility)
        
        let adjustedUnits = baseUnits * getPositionSizeMultiplier(for: signal)
        
        let stopLossDistance = signal.price * 0.001
        let takeProfitDistance = stopLossDistance * 2
        
        let stopLoss = signal.type == .buy ?
            signal.price - stopLossDistance :
            signal.price + stopLossDistance
        
        let takeProfit = signal.type == .buy ?
            signal.price + takeProfitDistance :
            signal.price - takeProfitDistance
        
        return PositionSize(
            units: adjustedUnits,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            riskAmount: riskAmount,
            potentialReward: riskAmount * 2
        )
    }
    
    private func getPositionSizeMultiplier(for signal: Signal) -> Double {
        if signal.confidence > 85 {
            return 1.2
        } else if signal.confidence < 70 {
            return 0.5
        }
        return 1.0
    }
    
    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()
    }
    
    func closeTrade(_ trade: TradeRecord) async {
        activeTrades.remove(trade.symbol)
        
        if let pnl = trade.pnl {
            let today = Calendar.current.startOfDay(for: Date())
            dailyPnL[today] = (dailyPnL[today] ?? 0) + pnl
        }
    }

    func syncActiveTrades(_ symbols: Set<String>) {
        self.activeTrades = symbols
        godLog("🛡️ RISK SYNC | activeTrades=\(symbols.sorted().joined(separator: ", ")) | count=\(symbols.count)", level: .diagnostic)
    }
}
