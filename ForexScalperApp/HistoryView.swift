import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedTrade: TradeRecord?
    @Binding var showTradeSheet: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("TRADE HISTORY")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                Spacer()
                Button(action: { viewModel.tradeHistory.removeAll() }) {
                    Text("CLEAR ALL").font(.system(size: 10, weight: .bold)).foregroundColor(.accentRed)
                }.buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.bgSecondary)
            
            Divider().background(Color.borderSubtle)
            #endif
            
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.tradeHistory.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 40))
                                .foregroundColor(.textMuted)
                            Text("No past trades to display.")
                                .foregroundColor(.textMuted)
                                .font(.subheadline)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(viewModel.tradeHistory) { trade in
                            Button(action: {
                                selectedTrade = trade
                                showTradeSheet = true
                            }) {
                                historyRow(trade)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color.bgPrimary)
    }
    
    @ViewBuilder
    func historyRow(_ trade: TradeRecord) -> some View {
        let pnl = trade.pnl ?? 0
        let isWin = pnl >= 0
        let color = isWin ? Color.accentGreen : Color.accentRed
        
        GlassCard(borderColor: color.opacity(0.2)) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(trade.symbol)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                            TagBadge(text: trade.type.rawValue.uppercased(), color: trade.type == .buy ? .accentGreen : .accentRed)
                        }
                        Text(formatDate(trade.entryTime))
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%@%.2f", pnl >= 0 ? "+" : "", pnl))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(color)
                        
                        Text(trade.status.rawValue.capitalized)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                }
                
                Divider().background(Color.white.opacity(0.05))
                
                HStack(spacing: 15) {
                    StatLabel(title: "SIZE", value: String(format: "%.2f", trade.positionSize ?? 0))
                    StatLabel(title: "ENTRY", value: String(format: "%.5f", trade.entryPrice))
                    StatLabel(title: "EXIT", value: String(format: "%.5f", trade.exitPrice ?? 0))
                    Spacer()
                    if let entry = Optional(trade.entryTime), let exit = trade.exitTime {
                        StatLabel(title: "DUR", value: formatDuration(exit.timeIntervalSince(entry)))
                    }
                }
            }
            .padding(14)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds/60))m"
    }
}

struct StatLabel: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
    }
}
