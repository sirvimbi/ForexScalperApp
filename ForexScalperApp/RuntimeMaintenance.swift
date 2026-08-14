import Foundation
import SwiftUI

/// Keeps broker-derived UI state fresh while the application remains open.
/// This is deliberately separate from the signal engine so refreshing account/history
/// never blocks signal calculation.
@MainActor
final class AppRuntimeMaintenance: ObservableObject {
    private weak var coordinator: RefactoredAppCoordinator?
    private weak var viewModel: DashboardViewModel?
    private var task: Task<Void, Never>?

    init(coordinator: RefactoredAppCoordinator, viewModel: DashboardViewModel) {
        self.coordinator = coordinator
        self.viewModel = viewModel
        start()
    }

    deinit {
        task?.cancel()
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            var cycle = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                cycle += 1

                if let viewModel = self.viewModel {
                    await viewModel.refreshAccountInfo()
                    viewModel.refreshData()
                }

                // A full history/position reconciliation is more expensive than an
                // account refresh, so run it every three minutes instead of every minute.
                if cycle % 3 == 0, let coordinator = self.coordinator {
                    await coordinator.syncMT5Trades()
                    self.viewModel?.refreshData()
                }
            }
        }
    }
}

/// Re-fetches broker history on demand. This is used by the History tab after a
/// local clear so the user can immediately repopulate it without restarting the app.
enum MT5HistoryRefreshService {
    @MainActor
    static func refresh() async {
        do {
            let history = try await MT5Service.shared.getTradeHistory(days: 90)
            let manager = RefactoredTradeHistoryManager.shared
            let existing = await manager.getAllTrades()
            let existingIDs = Set(existing.compactMap { $0.externalDealId })

            for position in history {
                let ticket = String(position.ticket)
                guard !existingIDs.contains(ticket) else { continue }

                let normalizedSymbol = normalizeSymbol(position.symbol)
                let record = TradeRecord(
                    id: UUID(),
                    signalId: UUID(),
                    symbol: normalizedSymbol,
                    type: position.type.lowercased() == "buy" ? .buy : .sell,
                    entryPrice: position.open_price,
                    entryTime: Date(timeIntervalSince1970: TimeInterval(position.open_time)),
                    exitPrice: position.close_price,
                    exitTime: Date(timeIntervalSince1970: TimeInterval(position.close_time)),
                    confidence: 100.0,
                    positionSize: position.volume,
                    pnl: position.profit + position.commission + position.swap,
                    status: .completed,
                    externalDealId: ticket,
                    swap: position.swap,
                    commission: position.commission
                )
                await manager.addTrade(record)
            }

            NotificationCenter.default.post(name: .tradeHistoryUpdated, object: nil)
            godLog("🔄 History Refresh: fetched \(history.count) broker records", level: .success)
        } catch {
            godLog("⚠️ History Refresh: \(error.localizedDescription)", level: .warning)
        }
    }

    private static func normalizeSymbol(_ symbol: String) -> String {
        var value = symbol.replacingOccurrences(of: "m", with: "")
        if let dot = value.firstIndex(of: ".") {
            value = String(value[..<dot])
        }
        return value
    }
}

/// App-side MT5 disconnect control. The bridge remains running, but the Swift app
/// stops its event stream immediately and marks the UI disconnected. The normal
/// connection/reconciliation flow can reconnect later through the existing Connect button.
struct MT5DisconnectControl: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var coordinator: RefactoredAppCoordinator
    @State private var isDisconnecting = false

    var body: some View {
        Button {
            disconnect()
        } label: {
            HStack(spacing: 6) {
                if isDisconnecting {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Image(systemName: "bolt.slash.fill")
                }
                Text("DISCONNECT MT5")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.accentRed.opacity(0.85))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isDisconnecting || !viewModel.mt5Connected)
        .help("Disconnect the Swift app from the MT5 event stream")
    }

    private func disconnect() {
        isDisconnecting = true
        Task {
            await MT5WebSocketService.shared.disconnect()
            await MainActor.run {
                viewModel.mt5Connected = false
                coordinator.connectionStatus = "Disconnected"
                coordinator.status = "MT5 disconnected by user"
                isDisconnecting = false
                godLog("🔌 MT5: Disconnected by user", level: .info)
            }
        }
    }
}