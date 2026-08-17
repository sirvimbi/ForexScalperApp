// ScalpingTradeMonitor.swift - V23 observation / unprofitable-exit layer
import Foundation

/// The MT5 EA is the single broker-side authority for profitable-position
/// management: TP1/TP2/TP3, breakeven and trailing SL. Swift observes the
/// lifecycle, reconciles broker state, and may close trades that remain
/// unprofitable when the existing strategy settings require it.
actor ScalpingTradeMonitor {
    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]

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
        godLog("🛡️ V23 TRADE MANAGER | EA authoritative | TP1/TP2/TP3/BE/trailing delegated to MT5", level: .info)
    }

    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        let trades = activeTrades.values.filter { $0.symbol == symbol && $0.isActive }
        for trade in trades {
            let profit = profitPips(trade, price)
            if profit > 0 { continue }
            if await checkTimeExit(trade) {
                await closeTrade(trade, reason: "Time Expiry (unprofitable)")
                continue
            }
            if let indicators,
               await shouldExitViaIndicatorReversal(trade, indicators: indicators) {
                await closeTrade(trade, reason: "Indicator Reversal (unprofitable)")
            }
        }
    }

    private func profitPips(_ trade: TradeRecord, _ price: Double) -> Double {
        let symbol = trade.symbol.uppercased()
        let pip: Double
        if symbol.contains("JPY") { pip = 0.01 }
        else if symbol.contains("XAU") || symbol.contains("XAG") { pip = 0.01 }
        else { pip = 0.0001 }
        return trade.type == .buy
            ? (price - trade.entryPrice) / pip
            : (trade.entryPrice - price) / pip
    }

    private func checkTimeExit(_ trade: TradeRecord) async -> Bool {
        let maxMinutes = await MainActor.run { ScalpingConfig.shared.maxHoldMinutes }
        guard maxMinutes > 0 else { return false }
        return Date().timeIntervalSince(trade.entryTime) > maxMinutes * 60
    }

    private func shouldExitViaIndicatorReversal(_ trade: TradeRecord, indicators: IndicatorSet) async -> Bool {
        let enabled = await MainActor.run { ScalpingConfig.shared.enableIndicatorExit }
        guard enabled, let entry = tradeEntryIndicators[trade.id] else { return false }
        if trade.type == .buy {
            return (indicators.rsi > 70 && indicators.rsi < entry.rsi - 3) ||
                   (indicators.bbPosition > 1 && indicators.stochasticK > 80)
        }
        return (indicators.rsi < 30 && indicators.rsi > entry.rsi + 3) ||
               (indicators.bbPosition < 0 && indicators.stochasticK < 20)
    }

    private func closeTrade(_ trade: TradeRecord, reason: String) async {
        guard let dealID = trade.externalDealId, let ticket = Int64(dealID) else { return }
        godLog("🎯 V23 SWIFT EXIT | \(trade.symbol) | reason=\(reason) | only because trade remains unprofitable", level: .info)
        do {
            if try await MT5Service.shared.closePosition(ticket: ticket) {
                await onTradeClosed?(trade)
            }
        } catch {
            godLog("❌ V23 Swift closure failed | \(trade.symbol) | \(error.localizedDescription)", level: .error)
        }
    }

    func reconcileBrokerState(_ trade: TradeRecord) async {
        await onPendingReconciliation?(trade)
    }

    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        var copy = trade
        copy.originalVolume = trade.originalVolume ?? trade.positionSize
        copy.remainingVolume = trade.remainingVolume ?? trade.positionSize
        activeTrades[trade.id] = copy
        if let indicators { tradeEntryIndicators[trade.id] = indicators }
        godLog("📊 V23 TRADE OBSERVED | \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice)) | EA management active", level: .trade)
    }

    func removeTrade(id: UUID) {
        activeTrades.removeValue(forKey: id)
        tradeEntryIndicators.removeValue(forKey: id)
    }

    func getActiveTrades() -> [TradeRecord] { Array(activeTrades.values) }

    func getLastTradeTime(symbol: String) -> Date? {
        activeTrades.values.filter { $0.symbol == symbol }.map { $0.entryTime }.max()
    }

    func setPendingReconciliationCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        onPendingReconciliation = callback
    }

    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        onTradeClosed = callback
    }

    func setOnPartialCloseCallback(_ callback: @escaping (TradeRecord) async -> Void) {
        onPartialClose = callback
    }
}
