import Foundation
import Combine

/// Connects the authoritative completed-trade history stream to the V23 Bayesian learner.
/// The bridge listens to the same `tradeUpdated` notification emitted by
/// RefactoredTradeHistoryManager, so it learns from actual closed trades rather than signal intent.
@MainActor
final class TradeOutcomeBayesianBridge {
    static let shared = TradeOutcomeBayesianBridge()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: Notification.Name.tradeUpdated)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? TradeRecord }
            .filter { $0.status == .completed }
            .sink { trade in
                Self.processCompletedTrade(trade)
            }
            .store(in: &cancellables)

        godLog("🧠 BAYESIAN BRIDGE | authoritative trade-history outcome listener active", level: .info)
    }

    private static func processCompletedTrade(_ trade: TradeRecord) {
        guard let pnl = trade.pnl else { return }
        let rawDirection = trade.type.rawValue.lowercased()
        let direction: SignalType
        switch rawDirection {
        case "buy": direction = .buy
        case "sell": direction = .sell
        default:
            godLog("⚠️ BAYESIAN BRIDGE | unsupported completed trade direction=\(trade.type.rawValue) | symbol=\(trade.symbol)", level: .warning)
            return
        }

        Task {
            await SignalAccuracyEngine.recordOutcome(
                outcomeID: trade.id.uuidString,
                symbol: trade.symbol,
                direction: direction,
                profitable: pnl > 0
            )
        }
    }
}
