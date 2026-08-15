import Foundation
import Combine

/// Connects the authoritative completed-trade history stream to the V23 Bayesian learner.
/// It also hydrates the hot-path Bayesian snapshot from the persisted trade history at startup.
@MainActor
final class TradeOutcomeBayesianBridge {
    static let shared = TradeOutcomeBayesianBridge()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: Notification.Name.tradeUpdated)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? TradeRecord }
            .filter { $0.status == .completed }
            .sink { trade in Self.processCompletedTrade(trade) }
            .store(in: &cancellables)

        Task { await self.hydrateFromAuthoritativeHistory() }
        godLog("🧠 BAYESIAN BRIDGE | authoritative trade-history outcome listener active", level: .info)
    }

    private func hydrateFromAuthoritativeHistory() async {
        let settings = SignalAccuracyConfiguration.load()
        let trades = await RefactoredTradeHistoryManager.shared.getAllTrades()
        var hydrated = 0
        for trade in trades where trade.status == .completed {
            guard let pnl = trade.pnl else { continue }
            guard let direction = Self.direction(for: trade) else { continue }
            SignalAccuracyBayesianRuntime.shared.update(
                key: "\(trade.symbol.uppercased()):\(direction)",
                profitable: pnl > 0,
                priorWins: settings.bayesianPriorWins,
                priorLosses: settings.bayesianPriorLosses
            )
            await SignalAccuracyEngine.recordOutcome(
                outcomeID: trade.id.uuidString,
                symbol: trade.symbol,
                direction: direction,
                profitable: pnl > 0
            )
            hydrated += 1
        }
        godLog("🧠 BAYESIAN BRIDGE | hydrated completed outcomes=\(hydrated)", level: .info)
    }

    private static func processCompletedTrade(_ trade: TradeRecord) {
        guard let pnl = trade.pnl, let direction = direction(for: trade) else { return }
        let settings = SignalAccuracyConfiguration.load()
        SignalAccuracyBayesianRuntime.shared.update(
            key: "\(trade.symbol.uppercased()):\(direction)",
            profitable: pnl > 0,
            priorWins: settings.bayesianPriorWins,
            priorLosses: settings.bayesianPriorLosses
        )
        Task {
            await SignalAccuracyEngine.recordOutcome(
                outcomeID: trade.id.uuidString,
                symbol: trade.symbol,
                direction: direction,
                profitable: pnl > 0
            )
        }
    }

    private static func direction(for trade: TradeRecord) -> SignalType? {
        switch trade.type.rawValue.lowercased() {
        case "buy": return .buy
        case "sell": return .sell
        default:
            godLog("⚠️ BAYESIAN BRIDGE | unsupported completed trade direction=\(trade.type.rawValue) | symbol=\(trade.symbol)", level: .warning)
            return nil
        }
    }
}
