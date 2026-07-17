// ScalpingTradeMonitor.swift (Fixed Actor Isolation Issues)
import Foundation

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var priceUpdateTask: Task<Void, Never>?
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    private let config: ScalpingConfig
    
    // Store local copies of config values to avoid MainActor isolation issues
    private var trailActivationPips: Double
    private var trailDistance: Double
    private var maxHoldTime: TimeInterval
    private var enableTrailingStop: Bool
    private var enableIndicatorExit: Bool
    
    private var onTradeClosed: ((TradeRecord) async -> Void)?
    private var trailingStops: [UUID: Double] = [:]
    
    init(marketData: MarketDataProvider, tradeHistory: RefactoredTradeHistoryManager,
         signalEngine: ScalpingSignalEngine, config: ScalpingConfig = .shared) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.signalEngine = signalEngine
        self.config = config
        
        // Initialize with current config values
        self.trailActivationPips = 5.0 
        self.trailDistance = 3.0
        self.maxHoldTime = 30 * 60
        self.enableTrailingStop = true
        self.enableIndicatorExit = true
        
        startMonitoring()
        
        // Start a task to load initial config and refresh periodically
        Task { [weak self] in
            await self?.loadInitialConfig()
            await self?.refreshConfigPeriodically()
        }
    }
    
    private func loadInitialConfig() async {
        // Load config values on the MainActor
        let (activation, distance, holdMinutes, trailing, indicator) = await MainActor.run {
            (
                config.trailActivationPips,
                config.trailDistance,
                config.maxHoldMinutes,
                config.enableTrailingStop,
                config.enableIndicatorExit
            )
        }
        
        // Update actor properties
        self.trailActivationPips = activation
        self.trailDistance = distance
        self.maxHoldTime = holdMinutes * 60
        self.enableTrailingStop = trailing
        self.enableIndicatorExit = indicator
    }
    
    private func refreshConfigPeriodically() async {
        while !Task.isCancelled {
            // Refresh config values every 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            
            // Load fresh values from MainActor
            let (activation, distance, holdMinutes, trailing, indicator) = await MainActor.run {
                (
                    config.trailActivationPips,
                    config.trailDistance,
                    config.maxHoldMinutes,
                    config.enableTrailingStop,
                    config.enableIndicatorExit
                )
            }
            
            // Update actor properties
            self.trailActivationPips = activation
            self.trailDistance = distance
            self.maxHoldTime = holdMinutes * 60
            self.enableTrailingStop = trailing
            self.enableIndicatorExit = indicator
        }
    }
    
    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        self.onTradeClosed = callback
    }
    
    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        // This method is called when price updates - we don't need to do anything here
        // The checkActiveTrades method already handles monitoring
        // Just log for debugging if needed
        print("📊 Price update for \(symbol): \(price)")
    }
    
    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        activeTrades[trade.id] = trade
        if let indicators = indicators {
            tradeEntryIndicators[trade.id] = indicators
        }
        print("📊 Scalping trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)")
    }
    
    private func startMonitoring() {
        priceUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkActiveTrades()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            }
        }
    }
    
    private func checkActiveTrades() async {
        for (id, trade) in activeTrades {
            guard let currentPrice = await marketData.getLatestPrice(symbol: trade.symbol) else {
                continue
            }
            
            // Get latest indicators for dynamic exit decisions
            let latestIndicators = await getLatestIndicators(symbol: trade.symbol)
            
            // Check exit conditions in order of priority
            if await shouldExitViaStopLoss(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Stop Loss", indicators: latestIndicators)
                continue
            }
            
            if await shouldExitViaTakeProfit(trade: trade, currentPrice: currentPrice) {
                await closeTrade(trade, exitPrice: currentPrice, reason: "Take Profit", indicators: latestIndicators)
                continue
            }
            
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
        
        // Only consider indicator-based exit after 2 minutes
        guard timeSinceEntry > 120 else { return false }
        
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
    
    private func updateTrailingStop(trade: TradeRecord, currentPrice: Double) async {
        guard enableTrailingStop else { return }
        
        let pips = abs(currentPrice - trade.entryPrice) / trade.entryPrice * 10000
        
        // Activate trailing stop after minimum profit
        if pips >= trailActivationPips {
            let currentTrail = getTrailingStop(for: trade.id)
            let newTrail: Double
            
            if trade.type == .buy {
                // For long positions, trail stop below current price
                newTrail = currentPrice - (trade.entryPrice * trailDistance / 10000)
                
                // Only move stop up, never down
                if let currentTrail = currentTrail {
                    if newTrail > currentTrail {
                        setTrailingStop(newTrail, for: trade.id)
                        print("📊 Trailing stop updated for \(trade.symbol): \(String(format: "%.5f", newTrail)) (profit: \(String(format: "%.1f", pips)) pips)")
                    }
                } else {
                    setTrailingStop(newTrail, for: trade.id)
                    print("📊 Trailing stop activated for \(trade.symbol): \(String(format: "%.5f", newTrail)) (profit: \(String(format: "%.1f", pips)) pips)")
                }
            } else {
                // For short positions, trail stop above current price
                newTrail = currentPrice + (trade.entryPrice * trailDistance / 10000)
                
                // Only move stop down, never up
                if let currentTrail = currentTrail {
                    if newTrail < currentTrail {
                        setTrailingStop(newTrail, for: trade.id)
                        print("📊 Trailing stop updated for \(trade.symbol): \(String(format: "%.5f", newTrail)) (profit: \(String(format: "%.1f", pips)) pips)")
                    }
                } else {
                    setTrailingStop(newTrail, for: trade.id)
                    print("📊 Trailing stop activated for \(trade.symbol): \(String(format: "%.5f", newTrail)) (profit: \(String(format: "%.1f", pips)) pips)")
                }
            }
        }
    }
    
    private func getLatestIndicators(symbol: String) async -> IndicatorSet? {
        // In a real implementation, you would calculate this from market data
        // For now, return nil - the indicator exit will be skipped
        return nil
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
        
        await tradeHistory.updateTrade(updatedTrade)
        activeTrades.removeValue(forKey: trade.id)
        tradeEntryIndicators.removeValue(forKey: trade.id)
        trailingStops.removeValue(forKey: trade.id)
        
        // Update signal engine with result for adaptive learning
        if let indicators = indicators {
            await signalEngine.updateSignalQuality(
                symbol: trade.symbol,
                type: trade.type,
                confidence: trade.confidence,
                wasWin: pnl > 0
            )
        }
        
        await onTradeClosed?(updatedTrade)
        
        // Post notifications
        await postTradeClosedNotifications(updatedTrade)
        
        print("📊 Scalping trade closed: \(trade.symbol) \(reason) | P&L: $\(String(format: "%.2f", pnl)) (\(String(format: "%.2f", pnlPercent))%)")
    }
    
    // Helper method to post notifications
    private func postTradeClosedNotifications(_ trade: TradeRecord) async {
        await MainActor.run {
            // Post trade updated notification with the trade object
            NotificationCenter.default.post(name: .tradeUpdated, object: trade)
            
            // Also post trade history updated notification for general refresh
            NotificationCenter.default.post(name: .tradeHistoryUpdated, object: nil)
            
            print("📢 Posted scalping trade closed notifications for \(trade.symbol)")
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
    
    func getActiveTradeCount() -> Int {
        return activeTrades.count
    }
    
    func getActiveTrades() -> [TradeRecord] {
        return Array(activeTrades.values)
    }
    
    func getTradeStatus(_ tradeId: UUID) -> (currentPrice: Double?, trailingStop: Double?)? {
        guard let trade = activeTrades[tradeId] else { return nil }
        
        // This is a sync method, so we can't await getLatestPrice
        // In a real implementation, you might want to make this async
        return (currentPrice: nil, trailingStop: trailingStops[tradeId])
    }
    
    deinit {
        priceUpdateTask?.cancel()
    }
}
