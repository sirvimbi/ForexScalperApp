// ScalpingTradeMonitor.swift - V10.6 coordinated EA/app trade management
import Foundation

// NOTE: Notification.Name.tradePartiallyClosed is declared in TradeNotificationExtensions.swift

actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var partialStages: [UUID: Int] = [:]

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
            let profit = profitPips(trade, price)
            let profitable = profit > 0

            await managePartialsAndRunner(trade: trade, price: price, profitPips: profit)

            // Profitable runners are never time-expired or indicator-exited.
            if profitable { continue }

            if await checkTimeExit(trade: trade) {
                await closeTrade(trade, reason: "Time Expiry (unprofitable)")
                continue
            }

            if let indicators,
               await shouldExitViaIndicatorReversal(trade: trade, indicators: indicators) {
                await closeTrade(trade, reason: "Indicator Reversal (unprofitable)")
                continue
            }

            if await emergency(trade: trade, price: price) {
                await closeTrade(trade, reason: "Emergency Fallback")
            }
        }
    }

    private func managePartialsAndRunner(trade: TradeRecord, price: Double, profitPips: Double) async {
        guard let dealID = trade.externalDealId,
              let ticket = Int64(dealID),
              let originalVolume = trade.originalVolume ?? trade.positionSize,
              originalVolume > 0 else { return }

        let config = await MainActor.run {
            (
                ScalpingConfig.shared.partialTP1_Pips,
                ScalpingConfig.shared.partialTP1_Percent,
                ScalpingConfig.shared.partialTP2_Pips,
                ScalpingConfig.shared.partialTP2_Percent,
                ScalpingConfig.shared.partialTP3_Pips
            )
        }

        var stage = partialStages[trade.id] ?? 0

        // 50% at TP1.
        if stage < 1 && profitPips >= config.0 {
            if await closePartial(ticket: ticket, volume: originalVolume * config.1, stage: 1, symbol: trade.symbol) {
                stage = 1
                partialStages[trade.id] = stage
                await protectAfterPartial(trade: trade, ticket: ticket)
            }
        }

        // Another 30% at TP2. The remaining 20% is the runner.
        if stage < 2 && profitPips >= config.2 {
            if await closePartial(ticket: ticket, volume: originalVolume * config.3, stage: 2, symbol: trade.symbol) {
                stage = 2
                partialStages[trade.id] = stage
                await protectAfterPartial(trade: trade, ticket: ticket)
            }
        }

        // Trailing starts after 5 pips and dynamically widens with profit.
        if profitPips >= 5 {
            let distancePips: Double
            if profitPips >= 30 { distancePips = 10 }
            else if profitPips >= 20 { distancePips = 8 }
            else if profitPips >= 10 { distancePips = 6 }
            else { distancePips = 4 }

            let pip = trade.symbol.contains("JPY") ? 0.01 : 0.0001
            let candidateSL = trade.type == .buy
                ? price - distancePips * pip
                : price + distancePips * pip

            let currentSL = trade.stopLoss ?? (trade.type == .buy ? 0 : Double.greatestFiniteMagnitude)
            let improves = trade.type == .buy ? candidateSL > currentSL : candidateSL < currentSL
            if improves {
                do {
                    if try await MT5Service.shared.modifyPosition(ticket: ticket, sl: candidateSL, tp: trade.takeProfit ?? 0) {
                        godLog("🛡️ TRAILING SL | \(trade.symbol) | profit=\(String(format: "%.1f", profitPips))p | distance=\(String(format: "%.1f", distancePips))p | SL=\(String(format: "%.5f", candidateSL))", level: .info)
                    }
                } catch {
                    godLog("⚠️ Trailing SL update failed | \(trade.symbol) | \(error.localizedDescription)", level: .warning)
                }
            }
        }

        // TP3 activates the runner; it does not close it. The fixed TP is removed so
        // the final 20% can run indefinitely under the hard/trailing SL.
        if stage >= 2 && profitPips >= config.4 {
            let currentSL = trade.stopLoss ?? (trade.type == .buy ? 0 : Double.greatestFiniteMagnitude)
            do {
                _ = try await MT5Service.shared.modifyPosition(ticket: ticket, sl: currentSL, tp: 0)
                godLog("🏃 RUNNER ACTIVE | \(trade.symbol) | profit=\(String(format: "%.1f", profitPips))p | fixed TP removed | trailing SL only", level: .success)
            } catch {
                godLog("⚠️ Runner TP removal failed | \(trade.symbol) | \(error.localizedDescription)", level: .warning)
            }
        }
    }

    private func closePartial(ticket: Int64, volume: Double, stage: Int, symbol: String) async -> Bool {
        let roundedVolume = max(0.01, (volume * 100).rounded() / 100)
        do {
            if try await MT5Service.shared.closePosition(ticket: ticket, volume: roundedVolume) {
                godLog("💰 PARTIAL TP\(stage) | \(symbol) | closed=\(String(format: "%.2f", roundedVolume)) lots", level: .success)
                // Post notification using the static constant - now accessible via nonisolated
                NotificationCenter.default.post(name: .tradePartiallyClosed, object: symbol)
                return true
            }
        } catch {
            godLog("⚠️ PARTIAL TP\(stage) failed | \(symbol) | \(error.localizedDescription)", level: .warning)
        }
        return false
    }

    private func protectAfterPartial(trade: TradeRecord, ticket: Int64) async {
        let pip = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        let lockPrice = trade.type == .buy ? trade.entryPrice + pip : trade.entryPrice - pip
        let currentSL = trade.stopLoss ?? (trade.type == .buy ? 0 : Double.greatestFiniteMagnitude)
        let improves = trade.type == .buy ? lockPrice > currentSL : lockPrice < currentSL
        guard improves else { return }
        do {
            _ = try await MT5Service.shared.modifyPosition(ticket: ticket, sl: lockPrice, tp: trade.takeProfit ?? 0)
            godLog("🛡️ PARTIAL PROTECTION | \(trade.symbol) | SL locked near breakeven", level: .info)
        } catch {
            godLog("⚠️ Partial protection failed | \(trade.symbol) | \(error.localizedDescription)", level: .warning)
        }
    }

    private func profitPips(_ trade: TradeRecord, _ price: Double) -> Double {
        let pip = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        return trade.type == .buy ? (price - trade.entryPrice) / pip : (trade.entryPrice - price) / pip
    }

    private func emergency(trade: TradeRecord, price: Double) async -> Bool {
        guard let sl = trade.stopLoss else { return false }
        let pip = trade.symbol.contains("JPY") ? 0.01 : 0.0001
        return trade.type == .buy ? price <= sl - 5 * pip : price >= sl + 5 * pip
    }

    private func shouldExitViaIndicatorReversal(trade: TradeRecord, indicators: IndicatorSet) async -> Bool {
        let enableExit = await MainActor.run { ScalpingConfig.shared.enableIndicatorExit }
        guard enableExit else { return false }

        guard let entry = tradeEntryIndicators[trade.id] else { return false }

        if trade.type == .buy {
            return (indicators.rsi > 70 && indicators.rsi < entry.rsi - 3) ||
                (indicators.bbPosition > 1 && indicators.stochasticK > 80)
        }
        return (indicators.rsi < 30 && indicators.rsi > entry.rsi + 3) ||
            (indicators.bbPosition < 0 && indicators.stochasticK < 20)
    }

    private func checkTimeExit(trade: TradeRecord) async -> Bool {
        let maxMinutes = await MainActor.run { ScalpingConfig.shared.maxHoldMinutes }
        return Date().timeIntervalSince(trade.entryTime) > maxMinutes * 60
    }

    private func closeTrade(_ trade: TradeRecord, reason: String) async {
        guard let dealID = trade.externalDealId, let ticket = Int64(dealID) else { return }
        godLog("🎯 EXIT FALLBACK | \(trade.symbol) | reason=\(reason)", level: .info)
        do {
            _ = try await MT5Service.shared.closePosition(ticket: ticket)
        } catch {
            godLog("❌ MT5 closure failed | \(trade.symbol) | \(error.localizedDescription)", level: .error)
        }
    }

    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        var copy = trade
        copy.originalVolume = trade.positionSize
        copy.remainingVolume = trade.positionSize
        activeTrades[trade.id] = copy
        partialStages[trade.id] = 0
        if let indicators { tradeEntryIndicators[trade.id] = indicators }
        godLog("📊 Trade opened: \(trade.symbol) \(trade.type) @ \(trade.entryPrice)", level: .trade)
    }

    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        tradeEntryIndicators.removeValue(forKey: id)
        partialStages.removeValue(forKey: id)
    }

    func getActiveTrades() -> [TradeRecord] { Array(activeTrades.values) }
    func getLastTradeTime(symbol: String) -> Date? {
        activeTrades.values.filter { $0.symbol == symbol }.map { $0.entryTime }.max()
    }
    func setPendingReconciliationCallback(_ callback: @escaping (TradeRecord) async -> Void) { onPendingReconciliation = callback }
    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) { onTradeClosed = callback }
    func setOnPartialCloseCallback(_ callback: @escaping (TradeRecord) async -> Void) { onPartialClose = callback }
}