import SwiftUI

/// A decision-grade performance dashboard built entirely from the app's executed trade history.
/// It intentionally uses realized trades only; open positions are kept separate so the metrics do not mix
/// floating P/L with closed-trade statistics.
struct AdvancedPerformanceView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedWindow: PerformanceWindow = .all

    enum PerformanceWindow: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7D"
        case month = "30D"
        case all = "All"
        var id: String { rawValue }
        var filter: DashboardTimeFilter {
            switch self {
            case .today: return .today
            case .week: return .last7Days
            case .month: return .thisMonth
            case .all: return .allTime
            }
        }
    }

    private var trades: [TradeRecord] {
        switch selectedWindow {
        case .all: return viewModel.tradeHistory
        case .today:
            return viewModel.tradeHistory.filter { Calendar.current.isDateInToday($0.exitTime ?? $0.entryTime) }
        case .week:
            let cutoff = Date().addingTimeInterval(-7 * 86400)
            return viewModel.tradeHistory.filter { ($0.exitTime ?? $0.entryTime) >= cutoff }
        case .month:
            let cutoff = Date().addingTimeInterval(-30 * 86400)
            return viewModel.tradeHistory.filter { ($0.exitTime ?? $0.entryTime) >= cutoff }
        }
    }

    private var realizedPnL: Double { trades.compactMap(\.pnl).reduce(0, +) }
    private var wins: [TradeRecord] { trades.filter { ($0.pnl ?? 0) > 0 } }
    private var losses: [TradeRecord] { trades.filter { ($0.pnl ?? 0) < 0 } }
    private var breakevens: Int { trades.filter { ($0.pnl ?? 0) == 0 }.count }
    private var winRate: Double { trades.isEmpty ? 0 : Double(wins.count) / Double(trades.count) * 100 }
    private var grossProfit: Double { wins.compactMap(\.pnl).reduce(0, +) }
    private var grossLoss: Double { abs(losses.compactMap(\.pnl).reduce(0, +)) }
    private var profitFactor: Double { grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? .infinity : 0) }
    private var avgWin: Double { wins.isEmpty ? 0 : grossProfit / Double(wins.count) }
    private var avgLoss: Double { losses.isEmpty ? 0 : grossLoss / Double(losses.count) }
    private var expectancy: Double {
        guard !trades.isEmpty else { return 0 }
        return (Double(wins.count) / Double(trades.count) * avgWin) - (Double(losses.count) / Double(trades.count) * avgLoss)
    }
    private var bestTrade: Double { wins.map { $0.pnl ?? 0 }.max() ?? 0 }
    private var worstTrade: Double { losses.map { $0.pnl ?? 0 }.min() ?? 0 }

    private var maxDrawdown: Double {
        var equity = 0.0
        var peak = 0.0
        var drawdown = 0.0
        for trade in trades.sorted(by: { $0.exitTime ?? $0.entryTime < $1.exitTime ?? $1.entryTime }) {
            equity += trade.pnl ?? 0
            peak = max(peak, equity)
            drawdown = min(drawdown, equity - peak)
        }
        return abs(drawdown)
    }

    private var maxWinStreak: Int {
        var current = 0, best = 0
        for trade in trades.sorted(by: { $0.exitTime ?? $0.entryTime < $1.exitTime ?? $1.entryTime }) {
            if (trade.pnl ?? 0) > 0 { current += 1; best = max(best, current) } else { current = 0 }
        }
        return best
    }

    private var maxLossStreak: Int {
        var current = 0, worst = 0
        for trade in trades.sorted(by: { $0.exitTime ?? $0.entryTime < $1.exitTime ?? $1.entryTime }) {
            if (trade.pnl ?? 0) < 0 { current += 1; worst = max(worst, current) } else { current = 0 }
        }
        return worst
    }

    private var pairStats: [(String, Int, Double, Double)] {
        Dictionary(grouping: trades, by: { $0.symbol })
            .map { symbol, rows in
                let pnl = rows.compactMap(\.pnl).reduce(0, +)
                let wr = rows.isEmpty ? 0 : Double(rows.filter { ($0.pnl ?? 0) > 0 }.count) / Double(rows.count) * 100
                return (symbol, rows.count, pnl, wr)
            }
            .sorted { $0.2 > $1.2 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                windowPicker
                kpiGrid
                riskSection
                equitySection
                pairSection
                executionQualitySection
            }
            .padding(24)
        }
        .background(Color.bgPrimary)
        .onChange(of: selectedWindow) { _, window in
            viewModel.updateTimeFilter(window.filter)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PERFORMANCE INTELLIGENCE")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                Text("REALIZED TRADE QUALITY • RISK • CONSISTENCY • EDGE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
            Spacer()
            Button {
                viewModel.refreshData()
            } label: {
                Label("REFRESH", systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentCyan)
        }
    }

    private var windowPicker: some View {
        HStack(spacing: 6) {
            ForEach(PerformanceWindow.allCases) { window in
                Button(window.rawValue) { selectedWindow = window }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(selectedWindow == window ? .bgPrimary : .textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selectedWindow == window ? Color.accentCyan : Color.bgCardHover)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
            }
            Spacer()
            Text("\(trades.count) CLOSED TRADES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.textMuted)
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("NET P/L", String(format: "KES %@%.2f", realizedPnL >= 0 ? "+" : "", realizedPnL), realizedPnL >= 0 ? .accentGreen : .accentRed, "chart.line.uptrend.xyaxis")
            metric("WIN RATE", String(format: "%.1f%%", winRate), winRate >= 50 ? .accentGreen : .accentRed, "target")
            metric("PROFIT FACTOR", profitFactor.isFinite ? String(format: "%.2f", profitFactor) : "∞", profitFactor >= 1 ? .accentGold : .accentRed, "scalemass.fill")
            metric("EXPECTANCY", String(format: "KES %@%.2f", expectancy >= 0 ? "+" : "", expectancy), expectancy >= 0 ? .accentCyan : .accentRed, "function")
            metric("AVG WIN", String(format: "KES %.2f", avgWin), .accentGreen, "arrow.up.right")
            metric("AVG LOSS", String(format: "KES %.2f", avgLoss), .accentRed, "arrow.down.right")
            metric("MAX DD", String(format: "KES %.2f", maxDrawdown), .accentRed, "arrow.down.right.circle")
            metric("BEST / WORST", String(format: "+%.0f / %.0f", bestTrade, worstTrade), .accentPurple, "medal.fill")
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        GlassCard(borderColor: color.opacity(0.22)) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundColor(color).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                    Text(value).font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private var riskSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("RISK & CONSISTENCY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentGold)
                Divider().background(Color.borderSubtle)
                HStack(spacing: 24) {
                    stat("WINS", "\(wins.count)", .accentGreen)
                    stat("LOSSES", "\(losses.count)", .accentRed)
                    stat("BREAKEVEN", "\(breakevens)", .textSecondary)
                    stat("WIN STREAK", "\(maxWinStreak)", .accentGreen)
                    stat("LOSS STREAK", "\(maxLossStreak)", .accentRed)
                    stat("RISK/REWARD AVG", avgLoss > 0 ? String(format: "%.2fx", avgWin / avgLoss) : "—", .accentCyan)
                    Spacer()
                }
            }
            .padding(16)
        }
    }

    private var equitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("REALIZED EQUITY CURVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                Divider().background(Color.borderSubtle)
                let points = cumulativePoints
                if points.isEmpty {
                    Text("Not enough closed trades for an equity curve.").foregroundColor(.textMuted).font(.caption)
                } else {
                    GeometryReader { geo in
                        let minValue = points.map(\.1).min() ?? 0
                        let maxValue = points.map(\.1).max() ?? 1
                        let span = max(maxValue - minValue, 0.01)
                        Path { path in
                            for (index, point) in points.enumerated() {
                                let x = points.count == 1 ? geo.size.width / 2 : geo.size.width * CGFloat(index) / CGFloat(points.count - 1)
                                let y = geo.size.height - ((point.1 - minValue) / span) * geo.size.height
                                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.accentCyan, lineWidth: 2)
                    }
                    .frame(height: 150)
                    HStack {
                        Text("START 0.00").foregroundColor(.textMuted)
                        Spacer()
                        Text(String(format: "CURRENT %@%.2f", realizedPnL >= 0 ? "+" : "", realizedPnL)).foregroundColor(realizedPnL >= 0 ? .accentGreen : .accentRed)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            }
            .padding(16)
        }
    }

    private var cumulativePoints: [(Date, Double)] {
        var total = 0.0
        return trades.sorted { ($0.exitTime ?? $0.entryTime) < ($1.exitTime ?? $1.entryTime) }.map {
            total += $0.pnl ?? 0
            return ($0.exitTime ?? $0.entryTime, total)
        }
    }

    private var pairSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("PAIR EDGE MATRIX")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentPurple)
                Divider().background(Color.borderSubtle)
                if pairStats.isEmpty {
                    Text("No realized pair statistics yet.").foregroundColor(.textMuted).font(.caption)
                } else {
                    ForEach(pairStats.prefix(12), id: \.0) { row in
                        HStack(spacing: 12) {
                            Text(row.0).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.textPrimary).frame(width: 80, alignment: .leading)
                            Text("\(row.1) trades").font(.caption2).foregroundColor(.textMuted).frame(width: 65, alignment: .leading)
                            Text(String(format: "%.1f%% WR", row.3)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(row.3 >= 50 ? .accentGreen : .accentRed).frame(width: 75, alignment: .leading)
                            Spacer()
                            Text(String(format: "KES %@%.2f", row.2 >= 0 ? "+" : "", row.2)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(row.2 >= 0 ? .accentGreen : .accentRed)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var executionQualitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("EXECUTION QUALITY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentGreen)
                Divider().background(Color.borderSubtle)
                HStack(spacing: 24) {
                    stat("LONG", "\(trades.filter { $0.type == .buy }.count)", .accentGreen)
                    stat("SHORT", "\(trades.filter { $0.type == .sell }.count)", .accentRed)
                    stat("ACTIVE", "\(viewModel.activeTrades.count)", .accentCyan)
                    stat("TRADES / WINDOW", "\(trades.count)", .textPrimary)
                    Spacer()
                }
                Text("Use this page to tune the strategy from realized evidence: prioritize positive expectancy, profit factor > 1, controlled drawdown and stable pair/session behavior rather than win rate alone.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
            Text(value).font(.system(size: 12, weight: .black, design: .monospaced)).foregroundColor(color)
        }
    }
}
