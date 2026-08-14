import SwiftUI

/// Decision-grade performance dashboard based on realized trades only.
struct AdvancedPerformanceView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedWindow: PerformanceWindow = .all

    enum PerformanceWindow: String, CaseIterable, Identifiable {
        case today = "Today", week = "7D", month = "30D", all = "All"
        var id: String { rawValue }
        var filter: DashboardTimeFilter {
            switch self { case .today: return .today; case .week: return .last7Days; case .month: return .thisMonth; case .all: return .allTime }
        }
    }

    private var trades: [TradeRecord] {
        switch selectedWindow {
        case .all: return viewModel.tradeHistory
        case .today: return viewModel.tradeHistory.filter { Calendar.current.isDateInToday($0.exitTime ?? $0.entryTime) }
        case .week: return viewModel.tradeHistory.filter { ($0.exitTime ?? $0.entryTime) >= Date().addingTimeInterval(-7 * 86400) }
        case .month: return viewModel.tradeHistory.filter { ($0.exitTime ?? $0.entryTime) >= Date().addingTimeInterval(-30 * 86400) }
        }
    }
    private var wins: [TradeRecord] { trades.filter { ($0.pnl ?? 0) > 0 } }
    private var losses: [TradeRecord] { trades.filter { ($0.pnl ?? 0) < 0 } }
    private var pnl: Double { trades.compactMap(\.pnl).reduce(0, +) }
    private var grossProfit: Double { wins.compactMap(\.pnl).reduce(0, +) }
    private var grossLoss: Double { abs(losses.compactMap(\.pnl).reduce(0, +)) }
    private var winRate: Double { trades.isEmpty ? 0 : Double(wins.count) / Double(trades.count) * 100 }
    private var profitFactor: Double { grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? .infinity : 0) }
    private var avgWin: Double { wins.isEmpty ? 0 : grossProfit / Double(wins.count) }
    private var avgLoss: Double { losses.isEmpty ? 0 : grossLoss / Double(losses.count) }
    private var expectancy: Double { trades.isEmpty ? 0 : (Double(wins.count) / Double(trades.count) * avgWin) - (Double(losses.count) / Double(trades.count) * avgLoss) }
    private var best: Double { wins.map { $0.pnl ?? 0 }.max() ?? 0 }
    private var worst: Double { losses.map { $0.pnl ?? 0 }.min() ?? 0 }

    private var maxDrawdown: Double {
        var equity = 0.0, peak = 0.0, dd = 0.0
        for t in sortedTrades { equity += t.pnl ?? 0; peak = max(peak, equity); dd = min(dd, equity - peak) }
        return abs(dd)
    }
    private var sortedTrades: [TradeRecord] { trades.sorted { ($0.exitTime ?? $0.entryTime) < ($1.exitTime ?? $1.entryTime) } }
    private var equityPoints: [(Date, Double)] {
        var total = 0.0
        return sortedTrades.map { t in total += t.pnl ?? 0; return (t.exitTime ?? t.entryTime, total) }
    }
    private var pairStats: [(symbol: String, count: Int, pnl: Double, winRate: Double)] {
        Dictionary(grouping: trades, by: { $0.symbol }).map { symbol, rows in
            let p = rows.compactMap(\.pnl).reduce(0, +)
            let wr = rows.isEmpty ? 0 : Double(rows.filter { ($0.pnl ?? 0) > 0 }.count) / Double(rows.count) * 100
            return (symbol, rows.count, p, wr)
        }.sorted { $0.pnl > $1.pnl }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PERFORMANCE INTELLIGENCE").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.accentCyan).tracking(2)
                        Text("REALIZED EDGE • RISK • CONSISTENCY • EXECUTION QUALITY").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                    }
                    Spacer()
                    Button { viewModel.refreshData() } label: { Label("REFRESH", systemImage: "arrow.clockwise").font(.system(size: 10, weight: .bold, design: .monospaced)) }.buttonStyle(.plain).foregroundColor(.accentCyan)
                }
                HStack(spacing: 6) {
                    ForEach(PerformanceWindow.allCases) { w in
                        Button(w.rawValue) { selectedWindow = w }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(selectedWindow == w ? .bgPrimary : .textSecondary).padding(.horizontal, 12).padding(.vertical, 7).background(selectedWindow == w ? Color.accentCyan : Color.bgCardHover).cornerRadius(6).buttonStyle(.plain)
                    }
                    Spacer()
                    Text("\(trades.count) CLOSED TRADES").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    metric("NET P/L", String(format: "KES %@%.2f", pnl >= 0 ? "+" : "", pnl), pnl >= 0 ? .accentGreen : .accentRed, "chart.line.uptrend.xyaxis")
                    metric("WIN RATE", String(format: "%.1f%%", winRate), winRate >= 50 ? .accentGreen : .accentRed, "target")
                    metric("PROFIT FACTOR", profitFactor.isFinite ? String(format: "%.2f", profitFactor) : "∞", profitFactor >= 1 ? .accentGold : .accentRed, "scalemass.fill")
                    metric("EXPECTANCY", String(format: "KES %@%.2f", expectancy >= 0 ? "+" : "", expectancy), expectancy >= 0 ? .accentCyan : .accentRed, "function")
                    metric("AVG WIN", String(format: "KES %.2f", avgWin), .accentGreen, "arrow.up.right")
                    metric("AVG LOSS", String(format: "KES %.2f", avgLoss), .accentRed, "arrow.down.right")
                    metric("MAX DRAWDOWN", String(format: "KES %.2f", maxDrawdown), .accentRed, "arrow.down.right.circle")
                    metric("BEST / WORST", String(format: "+%.0f / %.0f", best, worst), .accentPurple, "medal.fill")
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RISK & CONSISTENCY").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentGold)
                        Divider().background(Color.borderSubtle)
                        HStack(spacing: 28) {
                            stat("WINS", "\(wins.count)", .accentGreen); stat("LOSSES", "\(losses.count)", .accentRed); stat("BE", "\(trades.filter { ($0.pnl ?? 0) == 0 }.count)", .textSecondary)
                            stat("W/L AVG", avgLoss > 0 ? String(format: "%.2fx", avgWin / avgLoss) : "—", .accentCyan); stat("ACTIVE", "\(viewModel.activeTrades.count)", .accentCyan); Spacer()
                        }
                    }.padding(16)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("REALIZED EQUITY CURVE").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan)
                        Divider().background(Color.borderSubtle)
                        if equityPoints.isEmpty { Text("Not enough closed trades for an equity curve.").foregroundColor(.textMuted).font(.caption) }
                        else {
                            GeometryReader { geo in
                                let minV = equityPoints.map(\.1).min() ?? 0, maxV = equityPoints.map(\.1).max() ?? 1, span = max(maxV - minV, 0.01)
                                Path { path in
                                    for (i, p) in equityPoints.enumerated() {
                                        let x = equityPoints.count == 1 ? geo.size.width / 2 : geo.size.width * CGFloat(i) / CGFloat(equityPoints.count - 1)
                                        let y = geo.size.height - CGFloat((p.1 - minV) / span) * geo.size.height
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                }.stroke(Color.accentCyan, lineWidth: 2)
                            }.frame(height: 150)
                            HStack { Text("START 0.00").foregroundColor(.textMuted); Spacer(); Text(String(format: "CURRENT %@%.2f", pnl >= 0 ? "+" : "", pnl)).foregroundColor(pnl >= 0 ? .accentGreen : .accentRed) }.font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                    }.padding(16)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PAIR EDGE MATRIX").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentPurple)
                        Divider().background(Color.borderSubtle)
                        if pairStats.isEmpty { Text("No realized pair statistics yet.").foregroundColor(.textMuted).font(.caption) }
                        else { ForEach(pairStats.prefix(12), id: \.symbol) { row in HStack { Text(row.symbol).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.textPrimary).frame(width: 80, alignment: .leading); Text("\(row.count) trades").font(.caption2).foregroundColor(.textMuted).frame(width: 65, alignment: .leading); Text(String(format: "%.1f%% WR", row.winRate)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(row.winRate >= 50 ? .accentGreen : .accentRed); Spacer(); Text(String(format: "KES %@%.2f", row.pnl >= 0 ? "+" : "", row.pnl)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(row.pnl >= 0 ? .accentGreen : .accentRed) } } }
                    }.padding(16)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TRADING QUALITY SCORECARD").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentGreen)
                        Divider().background(Color.borderSubtle)
                        Text("Positive expectancy + profit factor above 1 + controlled drawdown + stable pair results is the target. A high win rate by itself is not enough if average losses overwhelm average wins.").font(.system(size: 9, design: .monospaced)).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 20) { score("EXPECTANCY", expectancy > 0); score("PF > 1", profitFactor > 1); score("WIN > 50%", winRate > 50); score("LOW DD", maxDrawdown <= max(1, grossProfit * 0.5)); Spacer() }
                    }.padding(16)
                }
            }.padding(24)
        }
        .background(Color.bgPrimary)
        .onChange(of: selectedWindow) { _, window in viewModel.updateTimeFilter(window.filter) }
    }

    private func metric(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        GlassCard(borderColor: color.opacity(0.22)) { HStack(spacing: 10) { Image(systemName: icon).foregroundColor(color); VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted); Text(value).font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7) }; Spacer() }.padding(12) }
    }
    private func stat(_ title: String, _ value: String, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted); Text(value).font(.system(size: 12, weight: .black, design: .monospaced)).foregroundColor(color) } }
    private func score(_ title: String, _ passed: Bool) -> some View { HStack(spacing: 5) { Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundColor(passed ? .accentGreen : .accentRed); Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(passed ? .accentGreen : .textMuted) } }
}
