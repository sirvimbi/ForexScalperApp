import SwiftUI
import UniformTypeIdentifiers

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var newsService = NewsService.shared
    @State private var selectedInsightSection = 0
    @State private var isRefreshingNews = false

    private var completedTrades: [TradeRecord] {
        viewModel.tradeHistory
            .filter { $0.status == .completed || $0.exitTime != nil }
            .sorted { ($0.exitTime ?? $0.entryTime) > ($1.exitTime ?? $1.entryTime) }
    }

    private var pairPerformances: [(symbol: String, trades: Int, wins: Int, pnl: Double, winRate: Double)] {
        Dictionary(grouping: completedTrades, by: { $0.symbol })
            .map { symbol, trades in
                let wins = trades.filter { ($0.pnl ?? 0) > 0 }.count
                let pnl = trades.compactMap { $0.pnl }.reduce(0, +)
                return (symbol, trades.count, wins, pnl, trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100)
            }
            .sorted {
                if $0.pnl == $1.pnl { return $0.trades > $1.trades }
                return $0.pnl > $1.pnl
            }
    }

    private var upcomingNews: [NewsEvent] {
        let now = Date()
        return newsService.upcomingEvents
            .filter { $0.time >= now }
            .sorted { $0.time < $1.time }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                sectionHeader("GOD MODE INSIGHTS", icon: "brain.head.profile", color: .accentCyan)
                Spacer()
                Button(action: { viewModel.allInsights.removeAll() }) {
                    Text("CLEAR ALERTS").font(.system(size: 10, weight: .bold)).foregroundColor(.accentRed)
                }.buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.bgSecondary)
            #endif

            HStack(spacing: 0) {
                insightTab("OVERVIEW", 0, "square.grid.2x2")
                insightTab("NEWS", 1, "calendar.badge.exclamationmark")
                insightTab("PAIR PERFORMANCE", 2, "chart.bar.xaxis")
                insightTab("SIGNAL RECORD", 3, "list.bullet.rectangle")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(Color.bgSecondary)

            ScrollView {
                VStack(spacing: 14) {
                    switch selectedInsightSection {
                    case 0:
                        overviewSection
                    case 1:
                        newsSection
                    case 2:
                        pairPerformanceSection
                    case 3:
                        signalRecordSection
                    default:
                        overviewSection
                    }
                }
                .padding(20)
            }
        }
        .background(Color.bgPrimary)
        .task {
            await newsService.fetchNews()
            viewModel.refreshData()
        }
    }

    private func insightTab(_ title: String, _ index: Int, _ icon: String) -> some View {
        Button {
            selectedInsightSection = index
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(selectedInsightSection == index ? .accentCyan : .textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(selectedInsightSection == index ? Color.accentCyan.opacity(0.10) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private var overviewSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                insightMetric("UPCOMING NEWS", "\(upcomingNews.count)", "calendar", .accentGold)
                insightMetric("PAIRS TRACKED", "\(pairPerformances.count)", "chart.bar.xaxis", .accentCyan)
                insightMetric("EXECUTED SIGNALS", "\(completedTrades.count)", "bolt.fill", .accentGreen)
                insightMetric("WIN RATE", String(format: "%.1f%%", viewModel.winRate), "target", viewModel.winRate >= 50 ? .accentGreen : .accentRed)
            }

            if let next = upcomingNews.first {
                GlassCard(borderColor: next.impact.color.opacity(0.35)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TagBadge(text: "NEXT NEWS • \(next.impact.rawValue.uppercased())", color: next.impact.color)
                            Spacer()
                            Text(formatEventTime(next.time))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.textSecondary)
                        }
                        Text(next.title)
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(.textPrimary)
                        Text("Currency: \(next.currency) • Affects pairs containing \(next.currency.uppercased())")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(16)
                }
            }

            if !pairPerformances.isEmpty {
                GlassCard(borderColor: Color.accentCyan.opacity(0.2)) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("TOP PAIR PERFORMANCE", icon: "chart.line.uptrend.xyaxis", color: .accentCyan)
                        ForEach(Array(pairPerformances.prefix(5).enumerated()), id: \.offset) { _, item in
                            pairRow(item)
                        }
                    }
                    .padding(16)
                }
            }

            if !viewModel.allInsights.isEmpty {
                GlassCard(borderColor: Color.accentGold.opacity(0.2)) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("RECENT GOD MODE ALERTS", icon: "brain.head.profile", color: .accentGold)
                        ForEach(viewModel.allInsights.prefix(8)) { insight in
                            insightRow(insight)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var newsSection: some View {
        VStack(spacing: 12) {
            HStack {
                sectionTitle("UPCOMING ECONOMIC NEWS", icon: "calendar.badge.exclamationmark", color: .accentGold)
                Spacer()
                Button {
                    guard !isRefreshingNews else { return }
                    isRefreshingNews = true
                    Task {
                        await newsService.fetchNews(force: true)
                        await MainActor.run { isRefreshingNews = false }
                    }
                } label: {
                    Label(isRefreshingNews ? "REFRESHING" : "REFRESH", systemImage: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentCyan)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingNews)
            }

            if upcomingNews.isEmpty {
                emptyInsight("No upcoming economic events are currently available.", icon: "calendar.badge.checkmark")
            } else {
                ForEach(upcomingNews) { event in
                    GlassCard(borderColor: event.impact.color.opacity(0.25)) {
                        HStack(spacing: 12) {
                            VStack(spacing: 3) {
                                Text(event.currency.uppercased())
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                Text(formatEventTime(event.time))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.textMuted)
                            }
                            .frame(width: 72)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(event.title)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.textPrimary)
                                    TagBadge(text: event.impact.rawValue.uppercased(), color: event.impact.color)
                                }
                                Text(newsPairs(for: event.currency))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(13)
                    }
                }
            }
        }
    }

    private var pairPerformanceSection: some View {
        VStack(spacing: 12) {
            sectionTitle("PREVIOUS PAIR PERFORMANCE", icon: "chart.bar.xaxis", color: .accentGreen)

            if pairPerformances.isEmpty {
                emptyInsight("No completed trades are available yet. Pair performance will populate automatically as trades close.", icon: "chart.bar.xaxis")
            } else {
                ForEach(Array(pairPerformances.enumerated()), id: \.offset) { _, item in
                    GlassCard(borderColor: (item.pnl >= 0 ? Color.accentGreen : Color.accentRed).opacity(0.22)) {
                        VStack(spacing: 10) {
                            HStack {
                                Text(formatPair(item.symbol))
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text(String(format: "%@%.2f KES", item.pnl >= 0 ? "+" : "", item.pnl))
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(item.pnl >= 0 ? .accentGreen : .accentRed)
                            }
                            HStack(spacing: 18) {
                                miniStat("TRADES", "\(item.trades)")
                                miniStat("WINS", "\(item.wins)")
                                miniStat("WIN RATE", String(format: "%.1f%%", item.winRate))
                                miniStat("LOSS", "\(max(0, item.trades - item.wins))")
                                Spacer()
                            }
                        }
                        .padding(15)
                    }
                }
            }
        }
    }

    private var signalRecordSection: some View {
        VStack(spacing: 12) {
            HStack {
                sectionTitle("PREVIOUS SIGNALS • RECORD & TRACKING", icon: "list.bullet.rectangle", color: .accentPurple)
                Spacer()
                Text("\(completedTrades.count) RECORDS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.textMuted)
            }

            if completedTrades.isEmpty {
                emptyInsight("No executed signal records are available yet.", icon: "tray")
            } else {
                ForEach(completedTrades) { trade in
                    GlassCard(borderColor: Color.accentPurple.opacity(0.18)) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                HStack(spacing: 7) {
                                    Image(systemName: trade.type == .buy ? "arrow.up.right" : "arrow.down.right")
                                        .foregroundColor(trade.type == .buy ? .accentGreen : .accentRed)
                                    Text(formatPair(trade.symbol))
                                        .font(.system(size: 13, weight: .black, design: .monospaced))
                                        .foregroundColor(.textPrimary)
                                    TagBadge(text: trade.type.displayName, color: trade.type == .buy ? .accentGreen : .accentRed)
                                }
                                Spacer()
                                Text(String(format: "CONF %.1f%%", trade.confidence))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.accentCyan)
                            }

                            HStack(spacing: 18) {
                                miniStat("SIGNAL", formatEventTime(trade.signalTime ?? trade.entryTime))
                                miniStat("ENTRY", formatPrice(trade.entryPrice, symbol: trade.symbol))
                                miniStat("EXIT", trade.exitPrice.map { formatPrice($0, symbol: trade.symbol) } ?? "OPEN")
                                miniStat("P&L", String(format: "%@%.2f", (trade.pnl ?? 0) >= 0 ? "+" : "", trade.pnl ?? 0))
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Text("Signal ID: \(trade.signalId.uuidString.prefix(8))")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.textMuted)
                                if let deal = trade.externalDealId, !deal.isEmpty {
                                    Text("MT5: \(deal)")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.textMuted)
                                }
                                if trade.isPartialClosed {
                                    TagBadge(text: "PARTIALS", color: .accentGold)
                                }
                                Spacer()
                                Text(trade.status.rawValue.uppercased())
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(trade.isWin == true ? .accentGreen : (trade.isWin == false ? .accentRed : .textSecondary))
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .tracking(1)
        }
    }

    private func sectionTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundColor(color)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .tracking(0.8)
        }
    }

    private func insightMetric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        GlassCard(borderColor: color.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundColor(color)
                Text(title).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                Text(value).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
        }
    }

    private func pairRow(_ item: (symbol: String, trades: Int, wins: Int, pnl: Double, winRate: Double)) -> some View {
        HStack {
            Text(formatPair(item.symbol)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
            Spacer()
            Text("\(item.trades)T").font(.system(size: 9, design: .monospaced)).foregroundColor(.textMuted)
            Text(String(format: "%.1f%%", item.winRate)).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(item.winRate >= 50 ? .accentGreen : .accentRed)
            Text(String(format: "%@%.2f", item.pnl >= 0 ? "+" : "", item.pnl)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(item.pnl >= 0 ? .accentGreen : .accentRed)
        }
    }

    private func insightRow(_ insight: GodModeInsight) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TagBadge(text: insight.type.rawValue, color: insight.type == .newsBroadcast ? .accentGold : .accentCyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                Text(insight.message).font(.system(size: 9)).foregroundColor(.textSecondary).lineLimit(2)
            }
            Spacer()
            Text(formatLogTime(insight.timestamp)).font(.system(size: 8, design: .monospaced)).foregroundColor(.textMuted)
        }
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
            Text(value).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textSecondary)
        }
    }

    private func emptyInsight(_ message: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundColor(.textMuted)
            Text(message).font(.system(size: 10)).foregroundColor(.textMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(45)
        .background(Color.white.opacity(0.02))
        .cornerRadius(8)
    }

    private func formatPair(_ symbol: String) -> String {
        guard symbol.count >= 6 else { return symbol }
        return "\(symbol.prefix(3))/\(symbol.suffix(3))"
    }

    private func formatPrice(_ price: Double, symbol: String) -> String {
        symbol.uppercased().contains("JPY") ? String(format: "%.3f", price) : String(format: "%.5f", price)
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter.string(from: date)
    }

    private func formatLogTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func newsPairs(for currency: String) -> String {
        let curr = currency.uppercased()
        let pairs = TradingPair.allCases.map { $0.rawValue }.filter { $0.contains(curr) }.prefix(8)
        return pairs.isEmpty ? "Relevant currency: \(curr)" : pairs.map(formatPair).joined(separator: " • ")
    }
}

struct SystemLogsView: View {
    @ObservedObject var consoleLogger = ConsoleLogger.shared
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isExportingLogs = false
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("SYSTEM LOGS & DIAGNOSTICS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                Spacer()
                
                Button(action: {
                    ConsoleLogger.shared.clearLogs()
                }) {
                    Label("CLEAR", systemImage: "trash.fill")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentRed)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.accentRed.opacity(0.1))
                .cornerRadius(4)
                
                Button(action: {
                    exportLogs()
                }) {
                    Label("EXPORT (.TXT)", systemImage: "square.and.arrow.down.fill")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.bgPrimary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.accentCyan)
                .cornerRadius(4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider().background(Color.borderSubtle)
            #endif
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(consoleLogger.logs.reversed()) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(formatLogTime(entry.timestamp))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.textMuted)
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(entry.level.icon)
                                    .font(.system(size: 11))
                                
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.level.color)
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 14)
                }
                .onChange(of: consoleLogger.logs.count) { old, newValue in
                    if let first = ConsoleLogger.shared.logs.last {
                        withAnimation {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Color.bgSecondary.opacity(0.5))
        
        #if !os(macOS)
        .fileExporter(
            isPresented: $isExportingLogs,
            document: LogDocument(text: ConsoleLogger.shared.exportLogs()),
            contentType: .plainText,
            defaultFilename: "GodMode_Logs_\(Int(Date().timeIntervalSince1970)).txt"
        ) { result in
            if case .success(let url) = result {
                print("✅ Logs exported to: \(url.path)")
            }
        }
        #endif
    }
    
    private func exportLogs() {
        let logsText = ConsoleLogger.shared.exportLogs()
        let filename = "GodMode_Logs_\(Int(Date().timeIntervalSince1970)).txt"
        
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = filename
        savePanel.message = "Choose where to save your System Logs"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try logsText.write(to: url, atomically: true, encoding: .utf8)
                godLog("📂 Logs Exported: \(url.path)", level: .success)
                viewModel.showNotification(title: "Export Successful", message: "Logs saved successfully.")
            } catch {
                godLog("❌ Export Failed: \(error.localizedDescription)", level: .error)
                viewModel.showNotification(title: "Export Failed", message: error.localizedDescription)
            }
        }
        #else
        isExportingLogs = true
        #endif
    }
    
    private func formatLogTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
