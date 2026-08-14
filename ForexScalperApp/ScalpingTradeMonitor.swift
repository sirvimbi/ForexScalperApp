// ScalpingTradeMonitor.swift - V22 Swift observation / unprofitable-exit layer
import Foundation

/// V22 deliberately removes Swift-side partial-close, trailing-SL and runner-TP
/// mutation. The MT5 EA is the single authoritative broker-side manager for
/// magic 888888. Swift remains responsible for strategy context and, when
/// configured, exits that are still unprofitable.
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
        godLog("🛡️ V22 TRADE MANAGER | EA authoritative | partials/trailing/runner delegated to MT5", level: .info)
    }

    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        let trades = activeTrades.values.filter { $0.symbol == symbol }
        for trade in trades {
            let profit = profitPips(trade, price)
            let profitable = profit > 0

            // V22 rule: profitable trades are never time-expired or indicator-exited
            // by Swift. The EA owns their hard SL, partials and trailing runner.
            if profitable { continue }

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
        let pip = trade.symbol.contains("JPY") ? 0.01 : 0.0001
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
        godLog("🎯 V22 SWIFT EXIT | \(trade.symbol) | reason=\(reason) | only because trade remains unprofitable", level: .info)
        do {
            _ = try await MT5Service.shared.closePosition(ticket: ticket)
        } catch {
            godLog("❌ V22 Swift closure failed | \(trade.symbol) | \(error.localizedDescription)", level: .error)
        }
    }

    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        var copy = trade
        copy.originalVolume = trade.positionSize
        copy.remainingVolume = trade.positionSize
        activeTrades[trade.id] = copy
        if let indicators { tradeEntryIndicators[trade.id] = indicators }
        godLog("📊 V22 Trade observed: \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice)) | EA management active", level: .trade)
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
