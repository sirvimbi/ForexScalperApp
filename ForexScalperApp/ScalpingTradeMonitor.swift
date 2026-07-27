import Foundation

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var priceUpdateTask: Task<Void, Never>?
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    private let config: ScalpingConfig

    // Dynamic settings from config
    private var trailActivationPips: Double = 20.0
    private var trailDistance: Double = 10.0
    private var maxHoldTime: TimeInterval = 30 * 60
    private var enableTrailingStop: Bool = true
    private var enableIndicatorExit: Bool = true
    private var breakEvenPips: Double = 20.0
    
    private var partialTPExecuted: [UUID: Bool] = [:]

    private var onTradeClosed: ((TradeRecord) async -> Void)?
    private var trailingStops: [UUID: Double] = [:]
    private var latestSymbolIndicators: [String: IndicatorSet] = [:]

    init(marketData: MarketDataProvider,
         tradeHistory: RefactoredTradeHistoryManager,
         signalEngine: ScalpingSignalEngine,
         config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.signalEngine = signalEngine
        self.config = config

        Task {
            await loadInitialConfig()
            await startMonitoringLogic()
            await refreshConfigPeriodically()
        }
    }

    private func loadInitialConfig() {
        Task { @MainActor in
            let trailAct = config.trailActivationPips
            let trailDist = config.trailDistance
            let maxHold = config.maxHoldMinutes * 60
            let trailEnabled = config.enableTrailingStop
            let exitEnabled = config.enableIndicatorExit
            
            await self.updateInternalConfig(
                trailAct: trailAct,
                trailDist: trailDist,
                maxHold: maxHold,
                trailEnabled: trailEnabled,
                exitEnabled: exitEnabled
            )
        }
    }

    private func updateInternalConfig(trailAct: Double, trailDist: Double, maxHold: TimeInterval, trailEnabled: Bool, exitEnabled: Bool) {
        self.trailActivationPips = trailAct
        self.trailDistance = trailDist
        self.maxHoldTime = maxHold
        self.enableTrailingStop = trailEnabled
        self.enableIndicatorExit = exitEnabled
    }

    private func refreshConfigPeriodically() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.loadInitialConfig()
            }
        }
    }

    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onTradeClosed = callback
    }

    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        if let indicators = indicators {
            latestSymbolIndicators[symbol] = indicators
        }
        await checkActiveTrades(for: symbol, currentPrice: price)
    }

    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        activeTrades[trade.id] = trade
        if let indicators = indicators {
            tradeEntryIndicators[trade.id] = indicators
        }
        godLog("📊 Scalping trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)", level: .trade)
    }

    private func startMonitoringLogic() {
        // Core monitoring is driven by updatePrice calls from the coordinator
    }

    private func checkActiveTrades(for symbol: String, currentPrice: Double) async {
        let relevantTrades = activeTrades.values.filter { $0.symbol == symbol }
        let indicators = latestSymbolIndicators[symbol]

        for trade in relevantTrades {
            // 1. Check Stop Loss
            if await shouldExitViaStopLoss(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Stop Loss", indicators: indicators)
                continue
            }

            // 2. Check Take Profit
            if await shouldExitViaTakeProfit(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Take Profit", indicators: indicators)
                continue
            }

            // 3. Check Trailing Stop
            if await shouldExitViaTrailingStop(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Trailing Stop", indicators: indicators)
                continue
            }

            // 4. Check Partial Take Profit
            await checkPartialTakeProfit(trade: trade, currentPrice: currentPrice)

            // 5. Update Trailing Stop position
            await updateTrailingStop(trade: trade, currentPrice: currentPrice)

            // 6. Check indicator reversal (God Mode Exit)
            if enableIndicatorExit {
                if await shouldExitViaIndicatorReversal(trade: trade, currentPrice: currentPrice, indicators: indicators) {
                    await closeTrade(trade, exitPrice: currentPrice, reason: "Indicator Reversal", indicators: indicators)
                    continue
                }
            }

            // 7. Check Time Expiry
            if await shouldExitViaTimeExpiry(trade: trade) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Time Expiry", indicators: indicators)
                continue
            }
            
            // 8. Check Break-Even
            if await shouldApplyBreakEven(trade: trade, currentPrice: currentPrice) {
                await applyBreakEven(trade: trade)
            }
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
        
        let diff = currentPrice - trade.entryPrice
        let profitPips = (trade.type == .buy ? diff : -diff) / trade.entryPrice * 10000
        
        // 📈 USE ATR-BASED TRAILING
        let atr = await getATRForSymbol(trade.symbol)
        let atrPips = atr / trade.entryPrice * 10000
        
        // 🎯 Dynamic activation: 1.5x ATR for activation
        let activationThreshold = max(atrPips * 1.5, 15)  // Minimum 15 pips
        
        guard profitPips >= activationThreshold else { return false }
        guard let trailingStop = getTrailingStop(for: trade.id) else { return false }
        
        if trade.type == .buy && currentPrice <= trailingStop {
            godLog("🏃‍♂️ TRAIL HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice)) (Profit: \(Int(profitPips)) pips)", level: .info)
            return true
        } else if trade.type == .sell && currentPrice >= trailingStop {
            godLog("🏃‍♂️ TRAIL HIT: \(trade.symbol) @ \(String(format: "%.5f", currentPrice)) (Profit: \(Int(profitPips)) pips)", level: .info)
            return true
        }
        return false
    }

    private func shouldExitViaIndicatorReversal(trade: TradeRecord, currentPrice: Double, indicators: IndicatorSet?) async -> Bool {
        guard let indicators = indicators else { return false }
        guard let entryIndicators = tradeEntryIndicators[trade.id] else { return false }

        if trade.type == .buy {
            // Overbought reversal
            if indicators.rsi > 70 && indicators.rsi < entryIndicators.rsi - 5 {
                godLog("📊 Indicator exit: RSI overbought and turning down (\(String(format: "%.1f", indicators.rsi)) vs entry \(String(format: "%.1f", entryIndicators.rsi))", level: .diagnostic)
                return true
            }
            if indicators.bbPosition > 1.0 && indicators.stochasticK > 80 {
                godLog("📊 Indicator exit: Upper BB touch (\(String(format: "%.2f", indicators.bbPosition))) with stochastic overbought (\(String(format: "%.1f", indicators.stochasticK)))", level: .diagnostic)
                return true
            }
        } else {
            // Oversold reversal
            if indicators.rsi < 30 && indicators.rsi > entryIndicators.rsi + 5 {
                godLog("📊 Indicator exit: RSI oversold and turning up (\(String(format: "%.1f", indicators.rsi)) vs entry \(String(format: "%.1f", entryIndicators.rsi))", level: .diagnostic)
                return true
            }
            if indicators.bbPosition < 0.0 && indicators.stochasticK < 20 {
                godLog("📊 Indicator exit: Lower BB touch (\(String(format: "%.2f", indicators.bbPosition))) with stochastic oversold (\(String(format: "%.1f", indicators.stochasticK)))", level: .diagnostic)
                return true
            }
        }

        return false
    }

    private func shouldExitViaTimeExpiry(trade: TradeRecord) async -> Bool {
        let timeOpen = Date().timeIntervalSince(trade.entryTime)
        if timeOpen > maxHoldTime {
            godLog("📊 Time exit: Trade open for \(Int(timeOpen/60)) minutes (max: \(Int(maxHoldTime/60)) mins)", level: .diagnostic)
            return true
        }
        return false
    }

    // MARK: - Elite Risk Management Methods

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
        godLog("🛡 PROTECTION: Moving \(trade.symbol) to Break-Even (+2 pips buffer)", level: .success)
        var updatedTrade = trade
        let buffer = 2.0 * (trade.entryPrice * 0.0001)
        updatedTrade.stopLoss = trade.type == .buy ? trade.entryPrice + buffer : trade.entryPrice - buffer

        activeTrades[trade.id] = updatedTrade
        await tradeHistory.updateTrade(updatedTrade)

        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            godLog("📤 MT5: Syncing Break-Even SL to terminal...")
            let success = try? await MT5Service.shared.modifyPosition(ticket: ticket, sl: updatedTrade.stopLoss!, tp: trade.takeProfit ?? 0)
            if success == true {
                godLog("✅ MT5: Break-Even SL confirmed on terminal", level: .success)
            } else {
                godLog("⚠️ MT5: Break-Even SL modification REJECTED (Check Terminal Logs)", level: .error)
            }
        }
    }
    
    private func checkPartialTakeProfit(trade: TradeRecord, currentPrice: Double) async {
        guard !(partialTPExecuted[trade.id] ?? false) else { return }
        
        // 🎯 First target: 50% of TP
        guard let fullTP = trade.takeProfit else { return }
        let tpDistance = abs(fullTP - trade.entryPrice)
        let firstTargetDistance = tpDistance * 0.5
        let firstTarget = trade.type == .buy ? 
            trade.entryPrice + firstTargetDistance :
            trade.entryPrice - firstTargetDistance
        
        if (trade.type == .buy && currentPrice >= firstTarget) ||
           (trade.type == .sell && currentPrice <= firstTarget) {
            
            godLog("🎯 PARTIAL TP HIT: \(trade.symbol) - Closing 50% position", level: .success)
            partialTPExecuted[trade.id] = true
            
            // Close 50% of position
            if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
                let volume = trade.positionSize ?? 0.01
                let halfVolume = Double(String(format: "%.2f", volume / 2)) ?? 0.01
                _ = try? await MT5Service.shared.closePosition(ticket: ticket, volume: max(0.01, halfVolume))
            }
            
            // Move SL to breakeven for remaining position
            await applyBreakEven(trade: trade)
        }
    }

    private func updateTrailingStop(trade: TradeRecord, currentPrice: Double) async {
        guard enableTrailingStop else { return }
        
        let diff = currentPrice - trade.entryPrice
        let profitPips = (trade.type == .buy ? diff : -diff) / trade.entryPrice * 10000
        
        let atr = await getATRForSymbol(trade.symbol)
        let atrPips = atr / trade.entryPrice * 10000
        let activationThreshold = max(atrPips * 1.5, 15)
        let trailDistancePips = max(atrPips * 0.5, 8)
        
        guard profitPips >= activationThreshold else { return }
        
        let distance = (trade.entryPrice * trailDistancePips / 10000)
        let newTrail = trade.type == .buy ? currentPrice - distance : currentPrice + distance
        let currentTrail = getTrailingStop(for: trade.id)
        
        // Minimum step: 1 pip
        let minStep = trade.entryPrice * 1.0 / 10000
        
        if trade.type == .buy {
            if let currentTrail = currentTrail {
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

    private func syncTrailingStopToMT5(trade: TradeRecord, newSL: Double) async {
        godLog("🏃‍♂️ TRAIL: Chasing \(trade.symbol) @ \(String(format: "%.5f", newSL))", level: .info)
        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            let success = try? await MT5Service.shared.modifyPosition(ticket: ticket, sl: newSL, tp: trade.takeProfit ?? 0)
            if success == true {
                godLog("✅ MT5: Trailing SL confirmed on terminal", level: .success)
            } else {
                godLog("⚠️ MT5: Trailing SL modification REJECTED", level: .error)
            }
        }
    }

    private func getATRForSymbol(_ symbol: String) async -> Double {
        if let atr = try? await MT5Service.shared.getATR(symbol: symbol, period: 14) {
            return atr
        }
        return symbol.contains("JPY") ? 0.20 : 0.0020
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
        godLog("🎯 EXIT TRIGGER: \(trade.symbol) (\(reason)) @ \(exitPrice). Requesting MT5 closure...", level: .info)

        if let ticketStr = trade.externalDealId, let ticket = Int(ticketStr) {
            _ = try? await MT5Service.shared.closePosition(ticket: ticket)
        }

        activeTrades.removeValue(forKey: trade.id)
        tradeEntryIndicators.removeValue(forKey: trade.id)
        trailingStops.removeValue(forKey: trade.id)
        partialTPExecuted.removeValue(forKey: trade.id)

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
        partialTPExecuted.removeValue(forKey: id)
    }

    func getTradeStatus(_ tradeId: UUID) -> (currentPrice: Double?, trailingStop: Double?)? {
        guard activeTrades[tradeId] != nil else { return nil }
        return (currentPrice: nil, trailingStop: trailingStops[tradeId])
    }

    deinit {
        priceUpdateTask?.cancel()
    }
}
