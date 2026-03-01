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
    
    func updateParameters(_ params: RiskParameters) { // Add this method
        parameters = params
    }
    
    func canOpenTrade(for symbol: String) async -> Bool {
        // Check daily loss limit
        let today = Calendar.current.startOfDay(for: Date())
        let todayPnL = dailyPnL[today] ?? 0
        
        if todayPnL <= -parameters.accountBalance * parameters.maxDailyRisk {
            print("⚠️ Daily loss limit reached")
            return false
        }
        
        // Check concurrent trades
        if activeTrades.count >= parameters.maxConcurrentTrades {
            print("⚠️ Maximum concurrent trades reached")
            return false
        }
        
        // Check if we've traded this symbol recently (avoid overtrading)
        if let lastTrade = tradeOpenTime[symbol],
           Date().timeIntervalSince(lastTrade) < 300 { // 5 minutes cooldown per symbol
            print("⚠️ Symbol \(symbol) traded too recently")
            return false
        }
        
        return true
    }
    
    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let riskAmount = parameters.accountBalance * parameters.riskPerTrade
        
        // Calculate position size based on volatility
        let volatility = signal.volume > 0 ? signal.volume / 1000 : 0.001
        let baseUnits = riskAmount / (signal.price * volatility)
        
        // Adjust for market conditions
        let adjustedUnits = baseUnits * getPositionSizeMultiplier(for: signal)
        
        let stopLossDistance = signal.price * 0.001 // 0.1% stop loss
        let takeProfitDistance = stopLossDistance * 2 // 2:1 reward ratio
        
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
        // Reduce position size in volatile markets, increase in clear trends
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
}
