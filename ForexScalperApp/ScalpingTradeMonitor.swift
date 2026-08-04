// ScalpingTradeMonitor.swift - ENHANCED WITH EARLY TRAILING & MULTI-LEVEL TP
import Foundation
import UserNotifications

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var trailingStops: [UUID: Double] = [:]
    private var partialTPLevelsHit: [UUID: Set<Int>] = [:]
    private var breakEvenSet: [UUID: Bool] = [:]
    
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
            // 1. Take Profit
            if await checkTakeProfit(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Take Profit")
                continue
            }
            // 2. Trailing Stop
            if await checkTrailingStop(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Trailing Stop")
                continue
            }
            // 3. Partial TP (multi-level)
            await checkPartialTakeProfit(trade: trade, currentPrice: price)
            // 4. Update trailing stop (tight, early activation)
            await updateTrailingStop(trade: trade, currentPrice: price)
            // 5. Time exit
            if await checkTimeExit(trade: trade) {
                await closeTrade(trade, exitPrice: price, reason: "Time Expiry")
                continue
            }
            // 6. Indicator reversal
            if let indicators = indicators {
                if await shouldExitViaIndicatorReversal(trade: trade, indicators: indicators) {
                    await closeTrade(trade, exitPrice: price, reason: "Indicator Reversal")
                    continue
                }
            }
            // 7. Stop Loss (last resort)
            if await checkStopLoss(trade: trade, currentPrice: price) {
                await closeTrade(trade, exitPrice: price, reason: "Stop Loss")
                continue
            }
        }
    }

    // MARK: - Take Profit (ELITE: Early capture)
    private func checkTakeProfit(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let tp = trade.takeProfit else { return false }
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let currentPips = (trade.type == .buy ? currentPrice - trade.entryPrice : trade.entryPrice - currentPrice) / pipSize
        let tpPips = abs(tp - trade.entryPrice) / pipSize

        if currentPips >= tpPips * 0.7 {
            if let indicators = tradeEntryIndicators[trade.id] {
                let rsiOverextended = trade.type == .buy ? indicators.rsi > 72 : indicators.rsi < 28
                if rsiOverextended || currentPips > tpPips * 0.85 {
                    godLog("💎 ELITE PROFIT CAPTURE: \(trade.symbol) (\(Int(currentPips)) pips)", level: .success)
                    return true
                }
            }
        }
        if trade.type == .buy && currentPrice >= tp { return true }
        if trade.type == .sell && currentPrice <= tp { return true }
        return false
    }

    // MARK: - Stop Loss
    private func checkStopLoss(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let sl = trade.stopLoss else { return false }
        if trailingStops[trade.id] != nil { return false }
        if trade.type == .buy && currentPrice <= sl { return true }
        if trade.type == .sell && currentPrice >= sl { return true }
        return false
    }

    // MARK: - Trailing Stop (activates at 3 pips profit)
    private func checkTrailingStop(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let trailStop = trailingStops[trade.id] else { return false }
        
        let pointSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let slippage = (trade.type == .buy ? trailStop - currentPrice : currentPrice - trailStop) / pointSize

        if trade.type == .buy && currentPrice <= trailStop {
            godLog("🏃‍♂️ TRAIL HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice)) (Slippage: \(String(format: "%.1f", slippage)) pips)", level: .warning)
            return true
        }
        if trade.type == .sell && currentPrice >= trailStop {
            godLog("🏃‍♂️ TRAIL HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice)) (Slippage: \(String(format: "%.1f", slippage)) pips)", level: .warning)
            return true
        }
        return false
    }

    private func updateTrailingStop(trade: TradeRecord, currentPrice: Double) async {
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let profitPips = (trade.type == .buy ? currentPrice - trade.entryPrice : trade.entryPrice - currentPrice) / pipSize
        guard profitPips >= 3.0 else { return }

        let trailDistancePips = 3.0
        let distance = trailDistancePips * pipSize
        let newTrail = trade.type == .buy ? currentPrice - distance : currentPrice + distance
        let currentTrail = trailingStops[trade.id]

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
            _ = try? await MT5Service.shared.modifyPosition(ticket: ticket, sl: newSL, tp: trade.takeProfit ?? 0)
        }
    }

    // MARK: - Partial Take Profit (Multi-Level)
    private func checkPartialTakeProfit(trade: TradeRecord, currentPrice: Double) async {
        guard trade.takeProfit != nil else { return }
        let pipSize = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let currentPips = (trade.type == .buy ? currentPrice - trade.entryPrice : trade.entryPrice - currentPrice) / pipSize

        // We'll use the same levels as defined in the EA (10, 15, 20 pips)
        let levels: [(pips: Int, percent: Double)] = [(10, 0.5), (15, 0.3), (20, 0.2)]
        var levelsHit = partialTPLevelsHit[trade.id] ?? []
        
        for (lvlPips, lvlPercent) in levels {
            if currentPips >= Double(lvlPips) && !levelsHit.contains(lvlPips) {
                levelsHit.insert(lvlPips)
                partialTPLevelsHit[trade.id] = levelsHit
                
                let volume = trade.positionSize ?? 0.01
                let closeVolume = volume * lvlPercent
                
                if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
                    _ = try? await MT5Service.shared.closePosition(ticket: ticket, volume: closeVolume)
                }
                
                godLog("🎯 PARTIAL TP: \(trade.symbol) - Closed \(Int(lvlPercent*100))% at \(lvlPips) pips", level: .success)
                
                // Move SL to breakeven after first level (10 pips)
                if lvlPips == 10 {
                    let buffer = 2.0 * pipSize
                    let breakEven = trade.type == .buy ? trade.entryPrice + buffer : trade.entryPrice - buffer
                    var updatedTrade = trade
                    updatedTrade.stopLoss = breakEven
                    activeTrades[trade.id] = updatedTrade
                    
                    if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
                        _ = try? await MT5Service.shared.modifyPosition(ticket: ticket, sl: breakEven, tp: trade.takeProfit ?? 0)
                    }
                }
            }
        }
    }

    // MARK: - Indicator Reversal
    private func shouldExitViaIndicatorReversal(trade: TradeRecord, indicators: IndicatorSet) async -> Bool {
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
        let maxHoldSeconds = 20.0 * 60 // 20 minutes
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
        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            do {
                successfullyClosed = try await MT5Service.shared.closePosition(ticket: ticket)
                if successfullyClosed {
                    await onPendingReconciliation?(trade)
                } else {
                    godLog("⚠️ MT5: Failed to close #\(ticket). Will retry on next price update.", level: .warning)
                    return // ABORT: Don't mark as completed if broker hasn't closed it
                }
            } catch {
                godLog("❌ MT5: Error closing #\(ticket): \(error.localizedDescription). Retrying...", level: .error)
                return // ABORT: Keep active to retry
            }
        }
        
        var updatedTrade = trade
        updatedTrade.exitPrice = exitPrice
        updatedTrade.exitTime = Date()
        updatedTrade.status = .completed
        updatedTrade.pnl = calculatePnL(trade: trade, exitPrice: exitPrice)

        activeTrades.removeValue(forKey: trade.id)
        tradeEntryIndicators.removeValue(forKey: trade.id)
        trailingStops.removeValue(forKey: trade.id)
        partialTPLevelsHit.removeValue(forKey: trade.id)
        breakEvenSet.removeValue(forKey: trade.id)

        await ScalpingRiskManager.shared.closeTrade(updatedTrade)
        await CorrelationFilter.shared.removeTrade(symbol: trade.symbol)
        await PerformanceAnalyzer.shared.recordTrade(updatedTrade)
        if let onTradeClosed = self.onTradeClosed { await onTradeClosed(updatedTrade) }
        
        // Notify user ONLY after verified closure
        await NotificationManager.shared.sendTradeClosedNotification(updatedTrade)
        
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
        trailingStops.removeValue(forKey: id)
        partialTPLevelsHit.removeValue(forKey: id)
        breakEvenSet.removeValue(forKey: id)
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