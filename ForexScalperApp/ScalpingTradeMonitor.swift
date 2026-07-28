// ScalpingTradeMonitor.swift - GOD MODE V7.0 ELITE
import Foundation
import UserNotifications

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var trailingStops: [UUID: Double] = [:]
    private var partialTPExecuted: [UUID: Bool] = [:]
    private var breakEvenSet: [UUID: Bool] = [:]
    
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    
    private var onPendingReconciliation: ((TradeRecord) async -> Void)?
    private var onTradeClosed: ((TradeRecord) async -> Void)?
    
    init(
        marketData: MarketDataProvider,
        tradeHistory: RefactoredTradeHistoryManager,
        signalEngine: ScalpingSignalEngine,
        config: ScalpingConfig
    ) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.signalEngine = signalEngine
    }
    
    // MARK: - PRICE UPDATE (ELITE MONITORING)
    
    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        let trades = activeTrades.values.filter { $0.symbol == symbol }
        
        for trade in trades {
            // PRIORITY 1: TAKE PROFIT (Highest priority)
            if await checkTakeProfit(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Take Profit")
                continue
            }
            
            // PRIORITY 2: TRAILING STOP
            if await checkTrailingStop(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Trailing Stop")
                continue
            }
            
            // PRIORITY 3: PARTIAL TAKE PROFIT
            await checkPartialTakeProfit(trade: trade, currentPrice: price)
            
            // PRIORITY 4: UPDATE TRAILING STOP
            await updateTrailingStop(trade: trade, currentPrice: price)
            
            // PRIORITY 5: TIME EXIT
            if await checkTimeExit(trade: trade) {
                await closeTrade(trade, exitPrice: price, reason: "Time Expiry")
                continue
            }
            
            // PRIORITY 6: INDICATOR REVERSAL
            if let indicators = indicators {
                if await shouldExitViaIndicatorReversal(trade: trade, indicators: indicators) {
                    await closeTrade(trade, exitPrice: price, reason: "Indicator Reversal")
                    continue
                }
            }
            
            // PRIORITY 7: STOP LOSS (Last resort)
            if await checkStopLoss(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Stop Loss")
                continue
            }
        }
    }
    
    // MARK: - TAKE PROFIT (ELITE: Early capture)
    
    private func checkTakeProfit(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let tp = trade.takeProfit else { return false }
        
        // ELITE: Use a tighter TP with partial profit taking
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let currentPips = abs(currentPrice - trade.entryPrice) / pipSize
        let tpPips = abs(tp - trade.entryPrice) / pipSize
        
        // If we're at 70% of TP, start checking for exit
        if currentPips >= tpPips * 0.7 {
            // Check if momentum is slowing (RSI divergence, etc.)
            if let indicators = tradeEntryIndicators[trade.id] {
                // Exit early if overbought/oversold
                if trade.type == .buy && indicators.rsi > 70 {
                    return true
                }
                if trade.type == .sell && indicators.rsi < 30 {
                    return true
                }
            }
        }
        
        // Full TP hit
        if trade.type == .buy && currentPrice >= tp {
            godLog("🎯 TP HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice))", level: .success)
            return true
        } else if trade.type == .sell && currentPrice <= tp {
            godLog("🎯 TP HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice))", level: .success)
            return true
        }
        
        return false
    }
    
    // MARK: - STOP LOSS (ELITE: Wider, but with trailing)
    
    private func checkStopLoss(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let sl = trade.stopLoss else { return false }
        
        // ELITE: Only hit SL if no trailing stop is active
        let hasTrailing = trailingStops[trade.id] != nil
        
        if hasTrailing {
            // If trailing is active, use it instead of SL
            return false
        }
        
        if trade.type == .buy && currentPrice <= sl {
            godLog("🛑 SL HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice))", level: .warning)
            return true
        } else if trade.type == .sell && currentPrice >= sl {
            godLog("🛑 SL HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice))", level: .warning)
            return true
        }
        return false
    }
    
    // MARK: - TRAILING STOP (ELITE: Tight, early activation)
    
    private func checkTrailingStop(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let trailStop = trailingStops[trade.id] else { return false }
        
        if trade.type == .buy && currentPrice <= trailStop {
            return true
        } else if trade.type == .sell && currentPrice >= trailStop {
            return true
        }
        return false
    }
    
    private func updateTrailingStop(trade: TradeRecord, currentPrice: Double) async {
        // ELITE: Activate trailing stop after 3 pips profit
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let profitPips = (trade.type == .buy ? currentPrice - trade.entryPrice : trade.entryPrice - currentPrice) / pipSize
        
        let activationPips = await MainActor.run { ScalpingConfig.shared.trailActivationPips }
        guard profitPips >= activationPips else { return }
        
        // ELITE: Tight trailing distance (2-4 pips)
        let trailDistancePips = await MainActor.run { ScalpingConfig.shared.trailDistance }
        let distance = trailDistancePips * pipSize
        
        let newTrail = trade.type == .buy ? currentPrice - distance : currentPrice + distance
        let currentTrail = trailingStops[trade.id]
        
        // Only update if new trail is better (moves in our favor)
        if trade.type == .buy {
            if currentTrail == nil || newTrail > currentTrail! {
                trailingStops[trade.id] = newTrail
                godLog("🏃‍♂️ TRAIL: \(trade.symbol) @ \(String(format: "%.5f", newTrail)) (Profit: \(Int(profitPips)) pips)", level: .diagnostic)
                await syncTrailingStopToMT5(trade: trade, newSL: newTrail)
            }
        } else {
            if currentTrail == nil || newTrail < currentTrail! {
                trailingStops[trade.id] = newTrail
                godLog("🏃‍♂️ TRAIL: \(trade.symbol) @ \(String(format: "%.5f", newTrail)) (Profit: \(Int(profitPips)) pips)", level: .diagnostic)
                await syncTrailingStopToMT5(trade: trade, newSL: newTrail)
            }
        }
    }
    
    private func syncTrailingStopToMT5(trade: TradeRecord, newSL: Double) async {
        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            _ = try? await MT5Service.shared.modifyPosition(
                ticket: ticket,
                sl: newSL,
                tp: trade.takeProfit ?? 0
            )
        }
    }
    
    // MARK: - PARTIAL TAKE PROFIT (ELITE: 50% at midpoint)
    
    private func checkPartialTakeProfit(trade: TradeRecord, currentPrice: Double) async {
        guard !(partialTPExecuted[trade.id] ?? false) else { return }
        guard let fullTP = trade.takeProfit else { return }
        
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let tpPips = abs(fullTP - trade.entryPrice) / pipSize
        let currentPips = abs(currentPrice - trade.entryPrice) / pipSize
        
        // ELITE: Close 50% at 50% of TP
        let targetPercent = await MainActor.run { ScalpingConfig.shared.partialTPPercent }
        if currentPips >= tpPips * targetPercent {
            godLog("🎯 PARTIAL TP: \(trade.symbol) - Closing \(Int(targetPercent * 100))% at \(Int(currentPips)) pips", level: .success)
            partialTPExecuted[trade.id] = true
            
            // Close partial position
            if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
                let volume = trade.positionSize ?? 0.01
                let closeVolume = volume * targetPercent
                _ = try? await MT5Service.shared.closePosition(ticket: ticket, volume: closeVolume)
            }
            
            // Move SL to breakeven for remaining position
            let buffer = 2.0 * pipSize
            let breakEven = trade.type == .buy ?
                trade.entryPrice + buffer :
                trade.entryPrice - buffer
            
            var updatedTrade = trade
            updatedTrade.stopLoss = breakEven
            activeTrades[trade.id] = updatedTrade
            
            if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
                _ = try? await MT5Service.shared.modifyPosition(
                    ticket: ticket,
                    sl: breakEven,
                    tp: trade.takeProfit ?? 0
                )
            }
        }
    }
    
    // MARK: - INDICATOR REVERSAL
    
    private func shouldExitViaIndicatorReversal(trade: TradeRecord, indicators: IndicatorSet) async -> Bool {
        guard let entryIndicators = tradeEntryIndicators[trade.id] else { return false }
        
        if trade.type == .buy {
            // Exit if RSI overbought and turning down
            if indicators.rsi > 70 && indicators.rsi < entryIndicators.rsi - 3 {
                return true
            }
            // Exit if BB upper band touched
            if indicators.bbPosition > 1.0 && indicators.stochasticK > 80 {
                return true
            }
        } else {
            // Exit if RSI oversold and turning up
            if indicators.rsi < 30 && indicators.rsi > entryIndicators.rsi + 3 {
                return true
            }
            // Exit if BB lower band touched
            if indicators.bbPosition < 0.0 && indicators.stochasticK < 20 {
                return true
            }
        }
        return false
    }
    
    // MARK: - TIME EXIT
    
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
    
    // MARK: - CLOSE TRADE
    
    private func closeTrade(_ trade: TradeRecord, exitPrice: Double, reason: String) async {
        godLog("🎯 EXIT: \(trade.symbol) (\(reason)) @ \(String(format: "%.5f", exitPrice))", level: .info)
        
        // Close on MT5
        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            _ = try? await MT5Service.shared.closePosition(ticket: ticket)
            await onPendingReconciliation?(trade)
        }
        
        // Update trade record
        var updatedTrade = trade
        updatedTrade.exitPrice = exitPrice
        updatedTrade.exitTime = Date()
        updatedTrade.status = .completed
        updatedTrade.pnl = calculatePnL(trade: trade, exitPrice: exitPrice)
        
        // Remove from tracking
        activeTrades.removeValue(forKey: trade.id)
        tradeEntryIndicators.removeValue(forKey: trade.id)
        trailingStops.removeValue(forKey: trade.id)
        partialTPExecuted.removeValue(forKey: trade.id)
        breakEvenSet.removeValue(forKey: trade.id)
        
        // Update performance
        await ScalpingRiskManager.shared.closeTrade(updatedTrade)
        await CorrelationFilter.shared.removeTrade(symbol: trade.symbol)
        await PerformanceAnalyzer.shared.recordTrade(updatedTrade)
        
        // Notify
        if let onTradeClosed = self.onTradeClosed {
            await onTradeClosed(updatedTrade)
        }
        await NotificationManager.shared.sendTradeClosedNotification(updatedTrade)
        
        let isWin = (updatedTrade.pnl ?? 0) > 0
        godLog("📊 Trade closed: \(trade.symbol) - P&L: KES \(String(format: "%.2f", updatedTrade.pnl ?? 0))", level: isWin ? .success : .warning)
    }
    
    private func calculatePnL(trade: TradeRecord, exitPrice: Double) -> Double {
        let positionSize = trade.positionSize ?? 1000
        if trade.type == .buy {
            return (exitPrice - trade.entryPrice) * positionSize * 100000
        } else {
            return (trade.entryPrice - exitPrice) * positionSize * 100000
        }
    }
    
    // MARK: - PUBLIC METHODS
    
    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        activeTrades[trade.id] = trade
        if let indicators = indicators {
            tradeEntryIndicators[trade.id] = indicators
        }
        godLog("📊 Trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)", level: .trade)
    }
    
    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        tradeEntryIndicators.removeValue(forKey: id)
        trailingStops.removeValue(forKey: id)
        partialTPExecuted.removeValue(forKey: id)
        breakEvenSet.removeValue(forKey: id)
    }
    
    func getActiveTrades() -> [TradeRecord] {
        return Array(activeTrades.values)
    }
    
    func getLastTradeTime(symbol: String) -> Date? {
        return activeTrades.values
            .filter { $0.symbol == symbol }
            .map { $0.entryTime }
            .max()
    }
    
    func setPendingReconciliationCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onPendingReconciliation = callback
    }
    
    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onTradeClosed = callback
    }
}
