// ScalpingTradeMonitor.swift - GOD MODE 2.0 (FIXED)
import Foundation

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var priceUpdateTask: Task<Void, Never>?
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    private let config: ScalpingConfig

    // FIXED: Conservative exit values
    private var trailActivationPips: Double = 20.0  // FIXED: 5 -> 20
    private var trailDistance: Double = 10.0        // FIXED: 3 -> 10
    private var maxHoldTime: TimeInterval = 30 * 60 // 30 minutes
    private var enableTrailingStop: Bool = true
    private var enableIndicatorExit: Bool = true
    private var breakEvenPips: Double = 20.0        // FIXED: 15 -> 20 (reduces breakeven exits)

    private var onTradeClosed: ((TradeRecord) async -> Void)?
    private var trailingStops: [UUID: Double] = [:]
    private var latestSymbolIndicators: [String: IndicatorSet] = [:]

    init(marketData: MarketDataProvider, tradeHistory: RefactoredTradeHistoryManager,
         signalEngine: ScalpingSignalEngine, config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.signalEngine = signalEngine
        self.config = config

        Task { [weak self] in
            await self?.loadInitialConfig()
            await self?.startMonitoringLogic()
            await self?.refreshConfigPeriodically()
        }
    }

    private func loadInitialConfig() async {
        let (activation, distance, holdMinutes, trailing, indicator) = await MainActor.run {
            (
                config.trailActivationPips,
                config.trailDistance,
                config.maxHoldMinutes,
                config.enableTrailingStop,
                config.enableIndicatorExit
            )
        }

        self.trailActivationPips = max(activation, 20) // FIXED: Ensure minimum 20
        self.trailDistance = max(distance, 10)         // FIXED: Ensure minimum 10
        self.maxHoldTime = holdMinutes * 60
        self.enableTrailingStop = trailing
        self.enableIndicatorExit = indicator
    }

    private func refreshConfigPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            let (activation, distance, holdMinutes, trailing, indicator) = await MainActor.run {
                (
                    config.trailActivationPips,
                    config.trailDistance,
                    config.maxHoldMinutes,
                    config.enableTrailingStop,
                    config.enableIndicatorExit
                )
            }

            self.trailActivationPips = max(activation, 20)
            self.trailDistance = max(distance, 10)
            self.maxHoldTime = holdMinutes * 60
            self.enableTrailingStop = trailing
            self.enableIndicatorExit = indicator
        }
    }

    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onTradeClosed = callback
    }

    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        if let indicators = indicators {
            latestSymbolIndicators[symbol] = indicators
        }
    }

    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        activeTrades[trade.id] = trade
        if let indicators = indicators {
            tradeEntryIndicators[trade.id] = indicators
        }
        print("📊 Scalping trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)")
    }

    private func startMonitoringLogic() {
        priceUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkActiveTrades()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // FIXED: 0.5s -> 1s (reduce noise)
            }
        }
    }

    private func checkActiveTrades() async {
        for trade in activeTrades.values {
            guard let currentPrice = await marketData.getLatestPrice(symbol: trade.symbol) else {
                continue
            }

            let latestIndicators = await getLatestIndicators(symbol: trade.symbol)

            // FIXED: Break-even after 20 pips (was 15)
            if await shouldApplyBreakEven(trade: trade, currentPrice: currentPrice) {
                await applyBreakEven(trade: trade)
            }

            // Check exit conditions
            if await shouldExitViaStopLoss(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Stop Loss", indicators: latestIndicators)
                continue
            }

            if await shouldExitViaTakeProfit(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Take Profit", indicators: latestIndicators)
                continue
            }

            // FIXED: Only trail after 20 pips profit (was 6)
            if await shouldExitViaTrailingStop(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Trailing Stop", indicators: latestIndicators)
                continue
            }

            if await shouldExitViaIndicatorReversal(trade: trade, currentPrice: currentPrice, indicators: latestIndicators) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Indicator Reversal", indicators: latestIndicators)
                continue
            }

            if await shouldExitViaTimeExpiry(trade: trade) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Time Expiry", indicators: latestIndicators)
                continue
            }

            // Update trailing stop if applicable
            await updateTrailingStop(trade: trade, currentPrice: currentPrice)
        }
    }

    private func shouldExitViaStopLoss(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let stopLoss = trade.stopLoss else { return false }

        if trade.type == .buy && currentPrice <= stopLoss {
            return true
        } else if trade.type == .sell && currentPrice >= stopLoss {
            return true
        }
        return false
    }

    private func shouldExitViaTakeProfit(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard let takeProfit = trade.takeProfit else { return false }

        if trade.type == .buy && currentPrice >= takeProfit {
            return true
        } else if trade.type == .sell && currentPrice <= takeProfit {
            return true
        }
        return false
    }

    private func shouldExitViaTrailingStop(trade: TradeRecord, currentPrice: Double) async -> Bool {
        guard enableTrailingStop else { return false }
        guard let trailingStop = getTrailingStop(for: trade.id) else { return false }

        if trade.type == .buy && currentPrice <= trailingStop {
            return true
        } else if trade.type == .sell && currentPrice >= trailingStop {
            return true
        }
        return false
    }

    private func shouldExitViaIndicatorReversal(trade: TradeRecord, currentPrice: Double, indicators: IndicatorSet?) async -> Bool {
        guard enableIndicatorExit else { return false }
        guard let indicators = indicators,
              let entryIndicators = tradeEntryIndicators[trade.id] else { return false }

        let timeSinceEntry = Date().timeIntervalSince(trade.entryTime)

        // FIXED: Only consider indicator-based exit after 3 minutes (was 2)
        guard timeSinceEntry > 180 else { return false }

        if trade.type == .buy {
            // Exit long if RSI becomes overbought and starts turning down
            if indicators.rsi > 70 && indicators.rsi < entryIndicators.rsi {
                print("📊 Indicator exit: RSI overbought and turning down (\(String(format: "%.1f", indicators.rsi)) vs entry \(String(format: "%.1f", entryIndicators.rsi))")
                return true
            }

            // Exit if price touches upper BB and stochastic is overbought
            if indicators.bbPosition > 0.8 && indicators.stochasticK > 80 {
                print("📊 Indicator exit: Upper BB touch (\(String(format: "%.2f", indicators.bbPosition))) with stochastic overbought (\(String(format: "%.1f", indicators.stochasticK)))")
                return true
            }
        } else {
            // Exit short if RSI becomes oversold and starts turning up
            if indicators.rsi < 30 && indicators.rsi > entryIndicators.rsi {
                print("📊 Indicator exit: RSI oversold and turning up (\(String(format: "%.1f", indicators.rsi)) vs entry \(String(format: "%.1f", entryIndicators.rsi))")
                return true
            }

            // Exit if price touches lower BB and stochastic is oversold
            if indicators.bbPosition < 0.2 && indicators.stochasticK < 20 {
                print("📊 Indicator exit: Lower BB touch (\(String(format: "%.2f", indicators.bbPosition))) with stochastic oversold (\(String(format: "%.1f", indicators.stochasticK)))")
                return true
            }
        }

        return false
    }

    private func shouldExitViaTimeExpiry(trade: TradeRecord) async -> Bool {
        let timeOpen = Date().timeIntervalSince(trade.entryTime)
        if timeOpen > maxHoldTime {
            print("📊 Time exit: Trade open for \(Int(timeOpen/60)) minutes (max: \(Int(maxHoldTime/60)) mins)")
            return true
        }
        return false
    }

    // MARK: - Elite Risk Management Methods

    // FIXED: Break-even only after 20 pips profit (was 15)
    private func shouldApplyBreakEven(trade: TradeRecord, currentPrice: Double) async -> Bool {
        let diff = currentPrice - trade.entryPrice
        let profitPips = (trade.type == .buy ? diff : -diff) / trade.entryPrice * 10000

        if profitPips >= breakEvenPips {
            if let sl = trade.stopLoss {
                if trade.type == .buy && sl >= trade.entryPrice { return false }
                if trade.type == .sell && sl <= trade.entryPrice { return false }
            }
            return true
        }
        return false
    }

    private func applyBreakEven(trade: TradeRecord) async {
        print("🛡 PROTECTION: Moving \(trade.symbol) to Break-Even (+2 pips buffer)")
        var updatedTrade = trade
        let buffer = 2.0 * (trade.entryPrice * 0.0001)
        updatedTrade.stopLoss = trade.type == .buy ? trade.entryPrice + buffer : trade.entryPrice - buffer

        activeTrades[trade.id] = updatedTrade
        await tradeHistory.updateTrade(updatedTrade)

        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            print("📤 MT5: Syncing Break-Even SL to terminal...")
            let success = try? await MT5Service.shared.modifyPosition(ticket: ticket, sl: updatedTrade.stopLoss!, tp: trade.takeProfit ?? 0)
            if success == true {
                print("✅ MT5: Break-Even SL confirmed on terminal")
            } else {
                print("⚠️ MT5: Break-Even SL modification REJECTED (Check Terminal Logs)")
            }
        }
    }

    // FIXED: Trailing stop - only after 20 pips profit, 10 pip trail (was 6/3)
    private func updateTrailingStop(trade: TradeRecord, currentPrice: Double) async {
        guard enableTrailingStop else { return }

        let diff = currentPrice - trade.entryPrice
        let profitPips = (trade.type == .buy ? diff : -diff) / trade.entryPrice * 10000

        if profitPips >= trailActivationPips {
            let currentTrail = getTrailingStop(for: trade.id)
            let distance = (trade.entryPrice * trailDistance / 10000)
            let newTrail = trade.type == .buy ? currentPrice - distance : currentPrice + distance

            if trade.type == .buy {
                if let currentTrail = currentTrail {
                    let minStep = trade.entryPrice * 1.0 / 10000 // 1 pip minimum step
                    if newTrail > currentTrail + minStep {
                        setTrailingStop(newTrail, for: trade.id)
                        await syncTrailingStopToMT5(trade: trade, newSL: newTrail)
                    }
                } else {
                    setTrailingStop(newTrail, for: trade.id)
                    await syncTrailingStopToMT5(trade: trade, newSL: newTrail)
                }
            } else {
                if let currentTrail = currentTrail {
                    let minStep = trade.entryPrice * 1.0 / 10000
                    if newTrail < currentTrail - minStep {
                        setTrailingStop(newTrail, for: trade.id)
                        await syncTrailingStopToMT5(trade: trade, newSL: newTrail)
                    }
                } else {
                    setTrailingStop(newTrail, for: trade.id)
                    await syncTrailingStopToMT5(trade: trade, newSL: newTrail)
                }
            }
        }
    }

    private func syncTrailingStopToMT5(trade: TradeRecord, newSL: Double) async {
        print("🏃‍♂️ TRAIL: Chasing \(trade.symbol) @ \(String(format: "%.5f", newSL))")
        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            let success = try? await MT5Service.shared.modifyPosition(ticket: ticket, sl: newSL, tp: trade.takeProfit ?? 0)
            if success == true {
                print("✅ MT5: Trailing SL confirmed on terminal")
            } else {
                print("⚠️ MT5: Trailing SL modification REJECTED")
            }
        }
    }

    private func getLatestIndicators(symbol: String) async -> IndicatorSet? {
        return latestSymbolIndicators[symbol]
    }

    private func setTrailingStop(_ stop: Double, for tradeId: UUID) {
        trailingStops[tradeId] = stop
    }

    private func getTrailingStop(for tradeId: UUID) -> Double? {
        return trailingStops[tradeId]
    }

    private func closeTrade(_ trade: TradeRecord, exitPrice: Double, reason: String, indicators: IndicatorSet?) async {
        var updatedTrade = trade
        let pnl = calculatePnL(trade: trade, exitPrice: exitPrice)
        let pnlPercent = (pnl / (trade.entryPrice * (trade.positionSize ?? 1000))) * 100

        updatedTrade.exitPrice = exitPrice
        updatedTrade.exitTime = Date()
        updatedTrade.pnl = pnl
        updatedTrade.pnlPercent = pnlPercent
        updatedTrade.status = .completed

        // FIXED: Log exit details
        let pips = abs(exitPrice - trade.entryPrice) / trade.entryPrice * 10000
        let holdTime = Int(Date().timeIntervalSince(trade.entryTime) / 60)
        print("""
              📊 EXIT LOG | \(trade.symbol) | \(reason)
                 Entry: \(trade.entryPrice) | Exit: \(exitPrice)
                 Pips: \(String(format: "%.1f", pips)) | Hold: \(holdTime)m
                 P&L: KES \(String(format: "%.2f", pnl))
              """)

        await tradeHistory.updateTrade(updatedTrade)
        activeTrades.removeValue(forKey: trade.id)
        tradeEntryIndicators.removeValue(forKey: trade.id)
        trailingStops.removeValue(forKey: trade.id)

        await signalEngine.updateSignalQuality(
            symbol: trade.symbol,
            type: trade.type,
            confidence: trade.confidence,
            wasWin: pnl > 0
        )

        await onTradeClosed?(updatedTrade)
        await postTradeClosedNotifications(updatedTrade)
    }

    private func postTradeClosedNotifications(_ trade: TradeRecord) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .tradeUpdated, object: trade)
            NotificationCenter.default.post(name: .tradeHistoryUpdated, object: nil)
            print("📢 Posted scalping trade closed notifications for \(trade.symbol)")
        }
        await NotificationManager.shared.sendTradeClosedNotification(trade)
    }

    private func calculatePnL(trade: TradeRecord, exitPrice: Double) -> Double {
        let positionSize = trade.positionSize ?? 1000
        if trade.type == .buy {
            return (exitPrice - trade.entryPrice) * positionSize
        } else {
            return (trade.entryPrice - exitPrice) * positionSize
        }
    }

    func getActiveTradeCount() -> Int {
        return activeTrades.count
    }

    func getActiveTrades() -> [TradeRecord] {
        return Array(activeTrades.values)
    }

    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        tradeEntryIndicators.removeValue(forKey: id)
        trailingStops.removeValue(forKey: id)
        print("🧹 Monitor: Removed trade \(id) from tracking")
    }

    func getTradeStatus(_ tradeId: UUID) -> (currentPrice: Double?, trailingStop: Double?)? {
        guard activeTrades[tradeId] != nil else { return nil }
        return (currentPrice: nil, trailingStop: trailingStops[tradeId])
    }

    deinit {
        priceUpdateTask?.cancel()
    }
}