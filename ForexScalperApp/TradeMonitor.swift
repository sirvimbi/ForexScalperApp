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
        startMonitoring()
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
    
    private func startMonitoring() {
        priceUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkActiveTrades()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    private func checkActiveTrades() async {
        for (id, trade) in activeTrades {
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
        var updatedTrade = trade
        let pnl = calculatePnL(trade: trade, exitPrice: exitPrice)
        let pnlPercent = (pnl / (trade.entryPrice * (trade.positionSize ?? 1000))) * 100
        
        updatedTrade.exitPrice = exitPrice
        updatedTrade.exitTime = Date()
        updatedTrade.pnl = pnl
        updatedTrade.pnlPercent = pnlPercent
        updatedTrade.status = .completed
        
        // Update in history
        await tradeHistory.updateTrade(updatedTrade)
        
        // Remove from active trades
        activeTrades.removeValue(forKey: trade.id)
        
        // Notify callback
        await onTradeClosed?(updatedTrade)
        
        // Send notifications for UI to update immediately
        await postTradeClosedNotifications(updatedTrade)
        
        print("📊 Trade closed: \(trade.symbol) \(reason) | P&L: $\(String(format: "%.2f", pnl)) (\(String(format: "%.2f", pnlPercent))%)")
    }
    
    // Helper method to post notifications
    private func postTradeClosedNotifications(_ trade: TradeRecord) async {
        await MainActor.run {
            // Post trade updated notification with the trade object
            NotificationCenter.default.post(name: .tradeUpdated, object: trade)
            
            // Also post trade history updated notification for general refresh
            NotificationCenter.default.post(name: .tradeHistoryUpdated, object: nil)
            
            print("📢 Posted trade closed notifications for \(trade.symbol)")
        }
        
        // Send push notification
        NotificationManager.shared.sendTradeClosedNotification(trade)
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
