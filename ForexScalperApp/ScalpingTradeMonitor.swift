// ScalpingTradeMonitor.swift - V10.0 Elite (Fixed SL, No Trailing)
import Foundation
import UserNotifications

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    private var onPendingReconciliation: ((TradeRecord) async -> Void)?
    private var onTradeClosed: ((TradeRecord) async -> Void)?
    
    init(marketData: MarketDataProvider,
         tradeHistory: RefactoredTradeHistoryManager,
         signalEngine: ScalpingSignalEngine,
         config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.signalEngine = signalEngine
    }

    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        let trades = activeTrades.values.filter { $0.symbol == symbol }
        for trade in trades {
            // ELITE V10.0: Fixed 30-pip SL. Soft Exits (Indicators, Time) are still monitored.

            // 1. Time exit (Institutional Hold Limit)
            if await checkTimeExit(trade: trade) {
                await closeTrade(trade, exitPrice: price, reason: "Time Expiry")
                continue
            }
            
            // 2. Indicator reversal (Logical Exit)
            if let indicators = indicators {
                if await shouldExitViaIndicatorReversal(trade: trade, indicators: indicators) {
                    await closeTrade(trade, exitPrice: price, reason: "Indicator Reversal")
                    continue
                }
            }

            // 3. EMERGENCY FALLBACK
            if await checkEmergencyFallback(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Emergency Fallback")
                continue
            }
        }
    }

    private func checkEmergencyFallback(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let sl = trade.stopLoss else { return false }
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let buffer = 5.0 * pipSize
        
        if trade.type == .buy && currentPrice <= (sl - buffer) { return true }
        if trade.type == .sell && currentPrice >= (sl + buffer) { return true }
        
        return false
    }

    // MARK: - Indicator Reversal
    private func shouldExitViaIndicatorReversal(trade: TradeRecord, indicators: IndicatorSet) async -> Bool {
        let enableExit = await MainActor.run { ScalpingConfig.shared.enableIndicatorExit }
        guard enableExit else { return false }
        
        guard let entryIndicators = tradeEntryIndicators[trade.id] else { return false }
        if trade.type == .buy {
            if indicators.rsi > 70 && indicators.rsi < entryIndicators.rsi - 3 { return true }
            if indicators.bbPosition > 1.0 && indicators.stochasticK > 80 { return true }
        } else {
            if indicators.rsi < 30 && indicators.rsi > entryIndicators.rsi + 3 { return true }
            if indicators.bbPosition < 0.0 && indicators.stochasticK < 20 { return true }
        }
        return false
    }

    // MARK: - Time Exit
    private func checkTimeExit(trade: TradeRecord) async -> Bool {
        let timeOpen = Date().timeIntervalSince(trade.entryTime)
        let maxHoldMinutes = await MainActor.run { ScalpingConfig.shared.maxHoldMinutes }
        let maxHoldSeconds = maxHoldMinutes * 60
        if timeOpen > maxHoldSeconds {
            godLog("⏰ Time exit: \(trade.symbol) - \(Int(timeOpen/60)) minutes", level: .diagnostic)
            return true
        }
        return false
    }

    // MARK: - Close Trade
    private func closeTrade(_ trade: TradeRecord, exitPrice: Double, reason: String) async {
        godLog("🎯 EXIT: \(trade.symbol) (\(reason)) @ \(String(format: "%.5f", exitPrice))", level: .info)
        
        var successfullyClosed = false
        if let ticketStr = trade.externalDealId, let ticket = Int64(ticketStr) {
            do {
                successfullyClosed = try await MT5Service.shared.closePosition(ticket: ticket)
                if successfullyClosed {
                    await onPendingReconciliation?(trade)
                } else {
                    let (activePositions, _) = try await MT5Service.shared.getPositionsAndOrders()
                    let stillExists = activePositions.contains { $0.ticket == ticket }
                    
                    if !stillExists {
                        godLog("ℹ️ MT5: Position #\(ticket) no longer exists. Marking as completed.", level: .success)
                        successfullyClosed = true 
                    } else {
                        godLog("⚠️ MT5: Failed to close #\(ticket).", level: .warning)
                        return 
                    }
                }
            } catch {
                godLog("❌ MT5: Error closing #\(ticket): \(error.localizedDescription).", level: .error)
                return 
            }
        }
        
        var updatedTrade = trade
        updatedTrade.exitPrice = exitPrice
        updatedTrade.exitTime = Date()
        updatedTrade.status = .completed
        updatedTrade.pnl = calculatePnL(trade: trade, exitPrice: exitPrice)

        activeTrades.removeValue(forKey: trade.id)
        tradeEntryIndicators.removeValue(forKey: trade.id)

        await ScalpingRiskManager.shared.closeTrade(updatedTrade)
        await CorrelationFilter.shared.removeTrade(symbol: trade.symbol)
        await PerformanceAnalyzer.shared.recordTrade(updatedTrade)
        if let onTradeClosed = self.onTradeClosed { await onTradeClosed(updatedTrade) }
        
        let isWin = (updatedTrade.pnl ?? 0) > 0
        godLog("📊 Verified Close: \(trade.symbol) - P&L: KES \(String(format: "%.2f", updatedTrade.pnl ?? 0))", level: isWin ? .success : .warning)
    }

    private func calculatePnL(trade: TradeRecord, exitPrice: Double) -> Double {
        let positionSize = trade.positionSize ?? 1000
        if trade.type == .buy { return (exitPrice - trade.entryPrice) * positionSize * 100000 }
        else { return (trade.entryPrice - exitPrice) * positionSize * 100000 }
    }

    // MARK: - Public Methods
    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        activeTrades[trade.id] = trade
        if let indicators = indicators { tradeEntryIndicators[trade.id] = indicators }
        godLog("📊 Trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)", level: .trade)
    }

    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        tradeEntryIndicators.removeValue(forKey: id)
    }

    func getActiveTrades() -> [TradeRecord] { return Array(activeTrades.values) }
    func getLastTradeTime(symbol: String) -> Date? {
        return activeTrades.values.filter { $0.symbol == symbol }.map { $0.entryTime }.max()
    }
    func setPendingReconciliationCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onPendingReconciliation = callback
    }
    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onTradeClosed = callback
    }
}
