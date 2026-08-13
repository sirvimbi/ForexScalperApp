// ScalpingTradeMonitor.swift - V10.0 Elite (Fixed SL, No Trailing)
import Foundation
import UserNotifications

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var partialTradeMonitors: [UUID: Task<Void, Never>] = [:]

    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    private var onPendingReconciliation: ((TradeRecord) async -> Void)?
    private var onTradeClosed: ((TradeRecord) async -> Void)?
    private var onPartialClose: ((TradeRecord) async -> Void)?

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

    // MARK: - Check if Trade Still Active in MT5
    private func isTradeStillActive(trade: TradeRecord) async -> Bool {
        guard let ticketStr = trade.externalDealId,
              let ticketInt = Int64(ticketStr) else { return false }

        do {
            let (activePositions, _) = try await MT5Service.shared.getPositionsAndOrders()
            // ✅ FIX: Compare Int64 with Int64, not String
            return activePositions.contains { $0.ticket == ticketInt }
        } catch {
            return false
        }
    }

    // MARK: - Calculate New SL After Partial Close
    private func calculateNewSL(trade: TradeRecord, exitPrice: Double) -> Double? {
        guard let currentSL = trade.stopLoss else { return nil }
        // Move SL to breakeven or slightly better
        if trade.type == .buy {
            return max(currentSL, exitPrice - 0.0005)
        } else {
            return min(currentSL, exitPrice + 0.0005)
        }
    }

    // MARK: - Monitor Remaining Partial Trade
    private func monitorPartialTrade(trade: TradeRecord) async {
        guard let dealIdString = trade.externalDealId else { return }

        partialTradeMonitors[trade.id] = Task {
            while !Task.isCancelled {
                // Check every 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                let stillActive = await isTradeStillActive(trade: trade)
                if !stillActive {
                    // Position is now fully closed
                    // ✅ FIX: Pass the String directly
                    if let updatedTrade = await fetchTradeStatus(dealId: dealIdString) {
                        await sendFinalClosureNotification(updatedTrade)
                        partialTradeMonitors.removeValue(forKey: trade.id)
                        break
                    }
                }
            }
        }
    }

    private func fetchTradeStatus(dealId: String) async -> TradeRecord? {
        // Fetch from MT5 history to get final P&L
        do {
            let history = try await MT5Service.shared.getTradeHistory(days: 1)
            if let closedTrade = history.first(where: { "\($0.ticket)" == dealId }) {
                var trade = activeTrades.values.first { $0.externalDealId == dealId }
                trade?.exitPrice = closedTrade.close_price
                trade?.exitTime = parseMT5Time("\(closedTrade.close_time)")
                trade?.pnl = closedTrade.profit + closedTrade.commission + closedTrade.swap
                trade?.status = .completed
                trade?.remainingVolume = 0
                return trade
            }
        } catch {
            print("⚠️ Failed to get trade status: \(error)")
        }
        return nil
    }

    private func sendFinalClosureNotification(_ trade: TradeRecord) async {
        if let onTradeClosed = self.onTradeClosed {
            await onTradeClosed(trade)
        }
    }

    private func parseMT5Time(_ timeStr: String?) -> Date? {
        guard let timeStr = timeStr else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return formatter.date(from: timeStr)
    }

    // MARK: - Close Trade (FIXED: Partial vs Full Detection)
    private func closeTrade(_ trade: TradeRecord, exitPrice: Double, reason: String) async {
        // V10.3: Trade management is now primary handled by the EA's OnTick throttled loop.
        // The app monitor serves as an emergency fallback and event listener.
        godLog("🎯 EXIT FALLBACK: \(trade.symbol) (\(reason)) @ \(String(format: "%.5f", exitPrice))", level: .info)

        // Delegate to MT5Service for actual closure
        if let ticketStr = trade.externalDealId, let ticket = Int64(ticketStr) {
            do {
                let success = try await MT5Service.shared.closePosition(ticket: ticket)
                if success {
                    godLog("✅ MT5: Closure request sent for #\(ticket)", level: .success)
                }
            } catch {
                godLog("❌ MT5: Closure failed for #\(ticket): \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func calculatePnL(trade: TradeRecord, exitPrice: Double) -> Double {
        let positionSize = trade.positionSize ?? 1000
        if trade.type == .buy { return (exitPrice - trade.entryPrice) * positionSize * 100000 }
        else { return (trade.entryPrice - exitPrice) * positionSize * 100000 }
    }

    // MARK: - Public Methods
    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        var newTrade = trade
        newTrade.originalVolume = trade.positionSize
        newTrade.remainingVolume = trade.positionSize
        activeTrades[trade.id] = newTrade
        if let indicators = indicators { tradeEntryIndicators[trade.id] = indicators }
        godLog("📊 Trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)", level: .trade)
    }

    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        tradeEntryIndicators.removeValue(forKey: id)
        partialTradeMonitors[id]?.cancel()
        partialTradeMonitors.removeValue(forKey: id)
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
    func setOnPartialCloseCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onPartialClose = callback
    }
}