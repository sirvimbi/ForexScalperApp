import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var consoleLogger = ConsoleLogger.shared
    @ObservedObject var coordinator: RefactoredAppCoordinator
    @State private var selectedTab = 0
    @State private var showTradeSheet = false
    @State private var selectedSignal: Signal?
    @State private var showNotificationAlert = false
    @State private var notificationMessage = ""
    @State private var selectedTrade: TradeRecord?
    @State private var isNotificationBannerDismissed = false
    let tabs = ["Signals", "Insights", "History", "Performance", "Logs", "Settings"]
    let tabIcons = ["bolt.fill", "brain.head.profile", "clock.fill", "chart.bar.fill", "terminal.fill", "gearshape.fill"]

    init(viewModel: DashboardViewModel, coordinator: RefactoredAppCoordinator) {
        self.viewModel = viewModel
        self.coordinator = coordinator
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                #if os(macOS)
                headerBar
                #endif
                HStack(spacing: 0) {
                    #if os(macOS)
                    customTabBar
                    Divider().background(Color.borderSubtle)
                    #endif
                    tabContent
                }
            }
        }
        .alert("New Signal Received", isPresented: $showNotificationAlert) {
            Button("Accept") { if let signal = selectedSignal { coordinator.acceptSignal(signal) }; selectedSignal = nil }
            Button("Deny", role: .cancel) { if let signal = selectedSignal { coordinator.denySignal(signal) }; selectedSignal = nil }
        } message: { Text(notificationMessage) }
        .sheet(isPresented: $showTradeSheet) {
            if let signal = selectedSignal {
                TradeExecutionView(signal: signal, viewModel: viewModel)
                    .foregroundColor(.white)
                    .colorScheme(.dark)
            } else if let trade = selectedTrade {
                TradeDetailView(trade: trade, viewModel: viewModel)
            }
        }
        .onAppear { setupNotificationObservers() }
        .onReceive(NotificationCenter.default.publisher(for: .dismissSignalOverlay)) { _ in
            selectedSignal = nil
            showTradeSheet = false
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewSignalNotification"), object: nil, queue: .main) { notification in
            guard let signal = notification.object as? Signal else { return }
            selectedSignal = signal
            notificationMessage = "\(signal.symbol) \(signal.type.rawValue.uppercased()) @ \(String(format: "%.5f", signal.price))"
            showNotificationAlert = true
            #if os(macOS)
            NSSound.beep()
            #endif
        }
    }

    #if os(macOS)
    private var headerBar: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "bolt.shield.fill").font(.system(size: 22)).foregroundColor(.accentCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STELLAS V10.3").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.textPrimary)
                    Text("ELITE INSTITUTIONAL").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan)
                }
            }
            Spacer()
            HStack(spacing: 24) {
                headerStat("ACCOUNT", viewModel.mt5Login.isEmpty ? "DEMO" : viewModel.mt5Login, .accentCyan)
                headerStat("EQUITY", String(format: "%@ %.2f", viewModel.accountCurrency, viewModel.accountBalance), .accentGreen)
                let pnl = viewModel.totalDailyPnL
                headerStat("DAILY", String(format: "%@%.2f", pnl >= 0 ? "+" : "", pnl), pnl >= 0 ? .accentGreen : .accentRed)
                HStack(spacing: 8) {
                    PulsingDot(color: viewModel.mt5Connected ? .accentGreen : .accentRed)
                    Text(viewModel.mt5Connected ? "CONNECTED" : coordinator.connectionStatus.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(viewModel.mt5Connected ? .accentGreen : .accentRed)
                }.padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.05)).cornerRadius(6)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16).background(Color.bgSecondary)
    }

    private func headerStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.textMuted)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
    }

    private var customTabBar: some View {
        VStack(spacing: 8) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button { selectedTab = index } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tabIcons[index]).frame(width: 24)
                        Text(tabs[index].uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
                        Spacer()
                        if index == 0 && coordinator.signals.contains(where: { $0.status == .pending }) { Circle().fill(Color.accentRed).frame(width: 6, height: 6) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .foregroundColor(selectedTab == index ? .accentCyan : .textSecondary)
                    .background(selectedTab == index ? Color.accentCyan.opacity(0.1) : .clear)
                }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(.top, 24).frame(width: 200).background(Color.bgSecondary)
    }
    #endif

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case 0:
            LiveSignalsView(viewModel: viewModel, coordinator: coordinator, selectedSignal: $selectedSignal, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet, isNotificationBannerDismissed: $isNotificationBannerDismissed)
                .foregroundColor(.white)
                .colorScheme(.dark)
        case 1: InsightsView(viewModel: viewModel)
        case 2: HistoryView(viewModel: viewModel, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet)
        case 3: PerformanceView(viewModel: viewModel)
        case 4: SystemLogsView(viewModel: viewModel)
        case 5:
            SettingsView(viewModel: viewModel, coordinator: coordinator)
                #if os(macOS)
                .overlay(alignment: .topTrailing) { MT5DisconnectControl(viewModel: viewModel, coordinator: coordinator).padding(.top, 16).padding(.trailing, 24) }
                #endif
        default: EmptyView()
        }
    }
}

struct PerformanceView: View {
    @ObservedObject var viewModel: DashboardViewModel
    private var trades: [TradeRecord] { viewModel.tradeHistory.filter { $0.status == .completed }.sorted { ($0.exitTime ?? $0.entryTime) < ($1.exitTime ?? $1.entryTime) } }
    private var wins: [TradeRecord] { trades.filter { ($0.pnl ?? 0) > 0 } }
    private var losses: [TradeRecord] { trades.filter { ($0.pnl ?? 0) < 0 } }
    private var grossProfit: Double { wins.compactMap { $0.pnl }.reduce(0, +) }
    private var grossLoss: Double { abs(losses.compactMap { $0.pnl }.reduce(0, +)) }
    private var expectancy: Double { trades.isEmpty ? 0 : viewModel.totalPnL / Double(trades.count) }
    private var maxDD: Double {
        var equity = 0.0, peak = 0.0, dd = 0.0
        for trade in trades { equity += trade.pnl ?? 0; peak = max(peak, equity); dd = min(dd, equity - peak) }
        return abs(dd)
    }
    private var avgHold: Double {
        let values = trades.compactMap { trade -> Double? in guard let exit = trade.exitTime else { return nil }; return exit.timeIntervalSince(trade.entryTime) / 60 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    private var streak: String {
        guard let last = trades.last else { return "0" }
        let win = (last.pnl ?? 0) > 0
        var count = 0
        for trade in trades.reversed() { if ((trade.pnl ?? 0) > 0) == win { count += 1 } else { break } }
        return "\(win ? "W" : "L")\(count)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PERFORMANCE INTELLIGENCE").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).tracking(2)
                        Text("Broker history • profitability • risk • execution quality").font(.system(size: 10, design: .monospaced)).foregroundColor(.textMuted)
                    }
                    Spacer()
                    Text("\(trades.count) CLOSED").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textSecondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    metric("NET P&L", viewModel.totalPnL, viewModel.totalPnL >= 0 ? .accentGreen : .accentRed, "chart.line.uptrend.xyaxis")
                    metric("WIN RATE", viewModel.winRate, .accentGreen, "target", suffix: "%")
                    metric("PROFIT FACTOR", viewModel.profitFactor, .accentGold, "arrow.up.right")
                    metric("EXPECTANCY", expectancy, expectancy >= 0 ? .accentGreen : .accentRed, "function")
                    metric("MAX DRAWDOWN", maxDD, .accentRed, "arrow.down.right")
                    metric("RECOVERY FACTOR", maxDD > 0 ? viewModel.totalPnL / maxDD : viewModel.totalPnL, .accentCyan, "gauge.with.dots.needle.67percent")
                    metric("AVG HOLD", avgHold, .accentCyan, "timer", suffix: "m")
                    metric("CURRENT STREAK", 0, .accentGold, "flame.fill", custom: streak)
                }
                HStack(spacing: 16) {
                    infoCard("TRADE QUALITY", "checkmark.seal.fill", .accentGreen, [
                        ("Wins", "\(wins.count)"), ("Losses", "\(losses.count)"),
                        ("Avg Win", String(format: "%.2f", viewModel.avgWin)), ("Avg Loss", String(format: "%.2f", viewModel.avgLoss)),
                        ("Largest Win", String(format: "%.2f", wins.compactMap { $0.pnl }.max() ?? 0)), ("Largest Loss", String(format: "%.2f", losses.compactMap { $0.pnl }.min() ?? 0)),
                        ("Streak", streak)
                    ])
                    infoCard("DIRECTIONAL EDGE", "arrow.left.arrow.right", .accentPurple, [
                        ("LONG Trades", "\(viewModel.totalBuyTrades)"), ("LONG Win Rate", String(format: "%.1f%%", viewModel.totalBuyTrades > 0 ? Double(viewModel.totalBuyWins) / Double(viewModel.totalBuyTrades) * 100 : 0)), ("LONG P&L", String(format: "%.2f", viewModel.totalBuyPnL)),
                        ("SHORT Trades", "\(viewModel.totalSellTrades)"), ("SHORT Win Rate", String(format: "%.1f%%", viewModel.totalSellTrades > 0 ? Double(viewModel.totalSellWins) / Double(viewModel.totalSellTrades) * 100 : 0)), ("SHORT P&L", String(format: "%.2f", viewModel.totalSellPnL))
                    ])
                }
                infoCard("TRADING DIAGNOSTICS", "waveform.path.ecg", .accentCyan, [
                    ("Gross Profit", String(format: "%.2f", grossProfit)), ("Gross Loss", String(format: "%.2f", grossLoss)),
                    ("Daily P&L", String(format: "%@%.2f", viewModel.totalDailyPnL >= 0 ? "+" : "", viewModel.totalDailyPnL)),
                    ("Total Trades", "\(trades.count)"), ("Active Trades", "\(viewModel.activeTrades.count)"), ("Account Equity", String(format: "%.2f", viewModel.accountBalance))
                ])
            }.padding(24)
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.loadTradeHistory() }
    }

    private func metric(_ title: String, _ value: Double, _ color: Color, _ icon: String, suffix: String = "", custom: String? = nil) -> some View {
        GlassCard(borderColor: color.opacity(0.25)) {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundColor(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                    Text(custom ?? String(format: "%.2f%@", value, suffix)).font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
            }.padding(12)
        }
    }

    private func infoCard(_ title: String, _ icon: String, _ color: Color, _ rows: [(String, String)]) -> some View {
        GlassCard(borderColor: color.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: icon).foregroundColor(color); Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary); Spacer() }
                Divider().background(Color.borderSubtle)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack { Text(row.0).font(.system(size: 10)).foregroundColor(.textSecondary); Spacer(); Text(row.1).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary) }
                }
            }.padding(16)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct NotificationBanner: View {
    let isAuthorized: Bool
    @Binding var isDismissed: Bool
    var body: some View {
        if !isAuthorized && !isDismissed {
            HStack {
                Image(systemName: "bell.badge.fill").foregroundColor(.white)
                Text("Notifications Disabled").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button("ENABLE") { NotificationManager.shared.requestAuthorization() }.buttonStyle(.plain).foregroundColor(.white)
                Button { isDismissed = true } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundColor(.white)
            }.padding(12).background(Color.accentRed).cornerRadius(8).padding(.horizontal, 20)
        }
    }
}

struct NoSignalsView: View {
    let connectionStatus: String
    let signalsCount: Int
    let signals: [Signal]
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 30)).foregroundColor(.accentCyan.opacity(0.3))
            Text("SCANNING FOR INSTITUTIONAL FLOW").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
            Text(connectionStatus == "Connected" ? "Active WebSocket stream on Port 8890. Waiting for high-probability confluence." : "Waiting for MT5 bridge connection...").font(.system(size: 11)).foregroundColor(.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 320)
            if signalsCount > 0 { Text("\(signalsCount) historical/expired signals hidden.").font(.system(size: 9, design: .monospaced)).foregroundColor(.textMuted) }
            Spacer()
        }.frame(minHeight: 400)
    }
}