// MARK: - Enhanced Trade Monitor with Callbacks
import Foundation

actor TradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var priceUpdateTask: Task<Void, Never>?
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private var onTradeClosed: ((TradeRecord) async -> Void)?
    
    init(marketData: MarketDataProvider, tradeHistory: RefactoredTradeHistoryManager) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        
        Task { [weak self] in
            await self?.startMonitoringLogic()
        }
    }
    
    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onTradeClosed = callback
    }
    
    func addTrade(_ trade: TradeRecord) {
        activeTrades[trade.id] = trade
        print("📊 Trade monitor: Added active trade for \(trade.symbol) (ID: \(trade.id.uuidString.prefix(8)))")
    }
    
    func getActiveTradeCount() -> Int {
        return activeTrades.count
    }

    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        print("🧹 Monitor: Removed trade \(id) from tracking")
    }
    
    private func startMonitoringLogic() {
        priceUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkActiveTrades()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    private func checkActiveTrades() async {
        for trade in activeTrades.values {
            guard let currentPrice = await marketData.getLatestPrice(symbol: trade.symbol) else {
                continue
            }
            
            // Check stop loss
            if let stopLoss = trade.stopLoss {
                if (trade.type == .buy && currentPrice <= stopLoss) ||
                   (trade.type == .sell && currentPrice >= stopLoss) {
                    await closeTrade(trade, exitPrice: currentPrice, reason: "Stop Loss")
                    continue
                }
            }
            
            // Check take profit
            if let takeProfit = trade.takeProfit {
                if (trade.type == .buy && currentPrice >= takeProfit) ||
                   (trade.type == .sell && currentPrice <= takeProfit) {
                    await closeTrade(trade, exitPrice: currentPrice, reason: "Take Profit")
                    continue
                }
            }
            
            // Check if trade has been open too long (max 1 hour)
            let maxDuration: TimeInterval = 3600
            if Date().timeIntervalSince(trade.entryTime) > maxDuration {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Time Expiry")
            }
        }
    }
    
    private func closeTrade(_ trade: TradeRecord, exitPrice: Double, reason: String) async {
        godLog("🎯 EXIT TRIGGER: \(trade.symbol) (\(reason)) @ \(exitPrice). Requesting MT5 closure...", level: .info)

        // ELITE CLEANUP: Unregister from risk filters immediately to allow new signals
        await CorrelationFilter.shared.removeTrade(symbol: trade.symbol)
        await RefactoredRiskManager.shared.closeTrade(trade)

        // 1. Send closure command to MT5
        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            _ = try? await MT5Service.shared.closePosition(ticket: ticket)
        }

        // 2. Stop local monitoring immediately
        activeTrades.removeValue(forKey: trade.id)

        // GOD MODE FIX: Let the coordinator handle the final verified sync
        godLog("🧹 Monitor: Stopped tracking \(trade.symbol). Waiting for broker verification.", level: .diagnostic)
    }
    
    private func calculatePnL(trade: TradeRecord, exitPrice: Double) -> Double {
        let positionSize = trade.positionSize ?? 1000
        if trade.type == .buy {
            return (exitPrice - trade.entryPrice) * positionSize
        } else {
            return (trade.entryPrice - exitPrice) * positionSize
        }
    }
    
    deinit {
        priceUpdateTask?.cancel()
    }
}
