// ScalpingTradeMonitor.swift - Swift-authoritative position management
import Foundation

/// Swift is the trading/position-management authority. MT5 is responsible only for
/// executing CLOSE/MODIFY requests and returning broker retcodes/state.
actor ScalpingTradeMonitor {
    private struct ManagementState: Codable, Sendable {
        var tp1Done = false
        var tp2Done = false
        var tp3Done = false
        var breakevenDone = false
        var lastSL: Double?
    }

    private var activeTrades: [UUID: TradeRecord] = [:]
    private var tradeEntryIndicators: [UUID: IndicatorSet] = [:]
    private var managementState: [Int64: ManagementState] = [:]
    private var inFlightTickets: Set<Int64> = []

    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let signalEngine: ScalpingSignalEngine
    private var onPendingReconciliation: ((TradeRecord) async -> Void)?
    private var onTradeClosed: ((TradeRecord) async -> Void)?
    private var onPartialClose: ((TradeRecord) async -> Void)?

    private let statePrefix = "positionManagement.state."

    init(marketData: MarketDataProvider,
         tradeHistory: RefactoredTradeHistoryManager,
         signalEngine: ScalpingSignalEngine,
         config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.signalEngine = signalEngine
        godLog("🛡️ POSITION MANAGER | Swift authoritative | TP/BE/trailing via MT5 execution bridge", level: .info)
    }

    func updatePrice(symbol: String, price: Double, indicators: IndicatorSet?) async {
        let trades = activeTrades.values.filter { $0.symbol == symbol && $0.isActive }
        for trade in trades {
            let profit = profitPips(trade, price)
            if profit > 0 {
                await manageProfitableTrade(trade, price: price, profitPips: profit)
                continue
            }

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

    private func manageProfitableTrade(_ trade: TradeRecord, price: Double, profitPips: Double) async {
        guard let ticket = positionTicket(for: trade), !inFlightTickets.contains(ticket) else { return }
        var state = loadState(for: ticket)
        let settings = PositionManagementSettings.load().validated()
        let config = await MainActor.run { ScalpingConfig.shared }
        let originalVolume = trade.originalVolume ?? trade.positionSize ?? 0
        let remainingVolume = trade.remainingVolume ?? originalVolume
        guard originalVolume > 0, remainingVolume > 0 else { return }

        let pip = pipSize(for: trade.symbol)
        let tp1Pips = max(0, config.partialTP1_Pips)
        let tp2Pips = max(tp1Pips, config.partialTP2_Pips)
        let tp3Pips = max(tp2Pips, config.partialTP3_Pips)

        if !state.tp1Done && profitPips >= tp1Pips && tp1Pips > 0 {
            if await executePartialClose(trade, ticket: ticket, targetFraction: config.partialTP1_Percent, stage: "TP1", remainingVolume: remainingVolume) {
                state.tp1Done = true
                state.lastSL = state.lastSL ?? trade.stopLoss
                saveState(state, for: ticket)
                await notifyPartialClose(trade)
                return
            }
        }

        if !state.tp2Done && profitPips >= tp2Pips && tp2Pips > 0 {
            let currentRemaining = activeTrades[trade.id]?.remainingVolume ?? remainingVolume
            if await executePartialClose(trade, ticket: ticket, targetFraction: config.partialTP2_Percent, stage: "TP2", remainingVolume: currentRemaining) {
                state.tp2Done = true
                saveState(state, for: ticket)
                await notifyPartialClose(trade)
                return
            }
        }

        if !state.tp3Done && profitPips >= tp3Pips && tp3Pips > 0 {
            let currentRemaining = activeTrades[trade.id]?.remainingVolume ?? remainingVolume
            if await executeFinalClose(trade, ticket: ticket, remainingVolume: currentRemaining) {
                state.tp3Done = true
                saveState(state, for: ticket)
                return
            }
        }

        if settings.breakevenEnabled && !state.breakevenDone && profitPips >= settings.breakevenTriggerPips {
            let offset = settings.breakevenOffsetPips * pip
            let candidate = trade.type == .buy ? trade.entryPrice + offset : trade.entryPrice - offset
            if await improveStop(ticket: ticket, trade: trade, candidateSL: candidate, state: &state, reason: "BREAKEVEN") {
                state.breakevenDone = true
                saveState(state, for: ticket)
            }
        }

        if profitPips >= settings.trailingActivationPips {
            let distance = settings.trailingDistancePips * pip
            let candidate = trade.type == .buy ? price - distance : price + distance
            if await improveStop(ticket: ticket, trade: trade, candidateSL: candidate, state: &state, reason: "TRAIL") {
                saveState(state, for: ticket)
            }
        }
    }

    private func executePartialClose(_ trade: TradeRecord,
                                     ticket: Int64,
                                     targetFraction: Double,
                                     stage: String,
                                     remainingVolume: Double) async -> Bool {
        let fraction = max(0, min(1, targetFraction))
        guard fraction > 0, remainingVolume > 0 else { return false }
        let originalVolume = max(trade.originalVolume ?? trade.positionSize ?? remainingVolume, remainingVolume)
        let requested = min(remainingVolume, originalVolume * fraction)
        let volume = await normalizedCloseVolume(symbol: trade.symbol, requested: requested, remaining: remainingVolume)
        guard let volume, volume > 0 else {
            godLog("⚠️ POSITION MGMT | \(trade.symbol) | \(stage) skipped: requested volume cannot satisfy broker step/minimum", level: .warning)
            return false
        }

        inFlightTickets.insert(ticket)
        defer { inFlightTickets.remove(ticket) }
        godLog("🎯 POSITION MGMT | \(trade.symbol) | \(stage) trigger | profit=\(String(format: "%.2f", profitPips(trade, trade.entryPrice)))pips | close=\(String(format: "%.4f", volume))", level: .info)
        do {
            let success = try await MT5Service.shared.closePosition(ticket: ticket, volume: volume)
            guard success else {
                godLog("❌ POSITION MGMT | \(trade.symbol) | \(stage) broker close rejected", level: .warning)
                return false
            }
            if var tracked = activeTrades[trade.id] {
                tracked.remainingVolume = max(0, (tracked.remainingVolume ?? remainingVolume) - volume)
                tracked.isPartialClosed = tracked.remainingVolume ?? 0 > 0
                activeTrades[trade.id] = tracked
            }
            godLog("✅ POSITION MGMT | \(trade.symbol) | \(stage) partial close accepted | volume=\(String(format: "%.4f", volume))", level: .success)
            return true
        } catch {
            godLog("❌ POSITION MGMT | \(trade.symbol) | \(stage) close failed: \(error.localizedDescription)", level: .error)
            return false
        }
    }

    private func executeFinalClose(_ trade: TradeRecord, ticket: Int64, remainingVolume: Double) async -> Bool {
        guard remainingVolume > 0 else { return false }
        inFlightTickets.insert(ticket)
        defer { inFlightTickets.remove(ticket) }
        godLog("🎯 POSITION MGMT | \(trade.symbol) | TP3 trigger | closing runner remainder=\(String(format: "%.4f", remainingVolume))", level: .info)
        do {
            let success = try await MT5Service.shared.closePosition(ticket: ticket, volume: remainingVolume)
            if success {
                if var tracked = activeTrades[trade.id] { tracked.remainingVolume = 0; tracked.status = .completed; activeTrades[trade.id] = tracked }
                godLog("✅ POSITION MGMT | \(trade.symbol) | TP3 runner closed", level: .success)
                await onTradeClosed?(activeTrades[trade.id] ?? trade)
                return true
            }
        } catch { godLog("❌ POSITION MGMT | \(trade.symbol) | TP3 close failed: \(error.localizedDescription)", level: .error) }
        return false
    }

    private func improveStop(ticket: Int64,
                             trade: TradeRecord,
                             candidateSL: Double,
                             state: inout ManagementState,
                             reason: String) async -> Bool {
        guard candidateSL.isFinite, candidateSL > 0 else { return false }
        let currentSL = state.lastSL ?? trade.stopLoss ?? 0
        let improves: Bool
        switch trade.type {
        case .buy: improves = currentSL <= 0 || candidateSL > currentSL
        case .sell: improves = currentSL <= 0 || candidateSL < currentSL
        default: return false
        }
        guard improves else { return false }

        let settings = PositionManagementSettings.load().validated()
        let step = settings.trailingStepPips * pipSize(for: trade.symbol)
        if currentSL > 0 && abs(candidateSL - currentSL) < step { return false }

        inFlightTickets.insert(ticket)
        defer { inFlightTickets.remove(ticket) }
        do {
            let success = try await MT5Service.shared.modifyPosition(ticket: ticket, sl: candidateSL, tp: trade.takeProfit ?? 0)
            if success {
                state.lastSL = candidateSL
                godLog("🛡️ POSITION MGMT | \(trade.symbol) | \(reason) | SL advanced → \(String(format: "%.5f", candidateSL))", level: .success)
                return true
            }
        } catch { godLog("⚠️ POSITION MGMT | \(trade.symbol) | \(reason) modify failed: \(error.localizedDescription)", level: .warning) }
        return false
    }

    private func normalizedCloseVolume(symbol: String, requested: Double, remaining: Double) async -> Double? {
        let limits = await MT5Service.shared.getVolumeLimits(for: symbol)
        let step = limits.step > 0 ? limits.step : limits.min
        guard step > 0 else { return nil }
        let rounded = floor((requested / step) + 1e-9) * step
        let candidate = min(remaining, rounded)
        if candidate <= 0 { return nil }
        if candidate >= remaining - step / 2 { return remaining }
        guard candidate >= limits.min else { return nil }
        return candidate
    }

    private func positionTicket(for trade: TradeRecord) -> Int64? {
        guard let id = trade.externalDealId, let ticket = Int64(id), ticket > 0 else { return nil }
        return ticket
    }

    private func pipSize(for symbol: String) -> Double {
        let clean = symbol.uppercased().replacingOccurrences(of: ".", with: "")
        if clean.contains("JPY") { return 0.01 }
        if clean.contains("XAU") || clean.contains("XAG") { return 0.01 }
        if clean.contains("US30") || clean.contains("US100") || clean.contains("NAS100") || clean.contains("US500") || clean.contains("GER30") { return 1.0 }
        return 0.0001
    }

    private func profitPips(_ trade: TradeRecord, _ price: Double) -> Double {
        let pip = pipSize(for: trade.symbol)
        return trade.type == .buy ? (price - trade.entryPrice) / pip : (trade.entryPrice - price) / pip
    }

    private func checkTimeExit(_ trade: TradeRecord) async -> Bool {
        let maxMinutes = await MainActor.run { ScalpingConfig.shared.maxHoldMinutes }
        guard maxMinutes > 0 else { return false }
        return Date().timeIntervalSince(trade.entryTime) > maxMinutes * 60
    }

    private func shouldExitViaIndicatorReversal(_ trade: TradeRecord, indicators: IndicatorSet) async -> Bool {
        let enabled = await MainActor.run { ScalpingConfig.shared.enableIndicatorExit }
        guard enabled, let entry = tradeEntryIndicators[trade.id] else { return false }
        if trade.type == .buy { return (indicators.rsi > 70 && indicators.rsi < entry.rsi - 3) || (indicators.bbPosition > 1 && indicators.stochasticK > 80) }
        return (indicators.rsi < 30 && indicators.rsi > entry.rsi + 3) || (indicators.bbPosition < 0 && indicators.stochasticK < 20)
    }

    private func closeTrade(_ trade: TradeRecord, reason: String) async {
        guard let ticket = positionTicket(for: trade), !inFlightTickets.contains(ticket) else { return }
        inFlightTickets.insert(ticket)
        defer { inFlightTickets.remove(ticket) }
        godLog("🎯 SWIFT EXIT | \(trade.symbol) | reason=\(reason) | trade remains unprofitable", level: .info)
        do {
            if try await MT5Service.shared.closePosition(ticket: ticket) { await onTradeClosed?(trade) }
        } catch { godLog("❌ Swift closure failed | \(trade.symbol) | \(error.localizedDescription)", level: .error) }
    }

    func addTrade(_ trade: TradeRecord, indicators: IndicatorSet?) {
        var copy = trade
        let original = trade.originalVolume ?? trade.positionSize ?? 0
        copy.originalVolume = original
        if copy.remainingVolume == nil { copy.remainingVolume = original }
        activeTrades[trade.id] = copy
        if let indicators { tradeEntryIndicators[trade.id] = indicators }
        if let ticket = positionTicket(for: trade) {
            let persisted = loadState(for: ticket)
            managementState[ticket] = persisted
        }
        godLog("📊 POSITION OBSERVED | \(trade.symbol) \(trade.type) @ \(String(format: "%.5f", trade.entryPrice)) | Swift management active", level: .trade)
    }

    func removeTrade(id: UUID) {
        if let trade = activeTrades.removeValue(forKey: id), let ticket = positionTicket(for: trade) {
            managementState.removeValue(forKey: ticket)
        }
        tradeEntryIndicators.removeValue(forKey: id)
    }

    func getActiveTrades() -> [TradeRecord] { Array(activeTrades.values) }
    func getLastTradeTime(symbol: String) -> Date? { activeTrades.values.filter { $0.symbol == symbol }.map { $0.entryTime }.max() }
    func setPendingReconciliationCallback(_ callback: @escaping (TradeRecord) async -> Void) { onPendingReconciliation = callback }
    func setOnTradeClosedCallback(_ callback: @escaping (TradeRecord) async -> Void) { onTradeClosed = callback }
    func setOnPartialCloseCallback(_ callback: @escaping (TradeRecord) async -> Void) { onPartialClose = callback }

    private func notifyPartialClose(_ trade: TradeRecord) async { await onPartialClose?(activeTrades[trade.id] ?? trade) }

    private func loadState(for ticket: Int64) -> ManagementState {
        if let cached = managementState[ticket] { return cached }
        let key = statePrefix + String(ticket)
        guard let data = UserDefaults.standard.data(forKey: key), let state = try? JSONDecoder().decode(ManagementState.self, from: data) else {
            let state = ManagementState()
            managementState[ticket] = state
            return state
        }
        managementState[ticket] = state
        return state
    }

    private func saveState(_ state: ManagementState, for ticket: Int64) {
        managementState[ticket] = state
        let key = statePrefix + String(ticket)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key) }
    }
}
