import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var consoleLogger = ConsoleLogger.shared
    @ObservedObject var coordinator: RefactoredAppCoordinator
    @State private var selectedTab: Int = 0
    @State private var showTradeSheet: Bool = false
    @State private var selectedSignal: Signal?
    @State private var showNotificationAlert: Bool = false
    @State private var notificationMessage: String = ""
    @State private var selectedTrade: TradeRecord?
    
    private let notificationManager = NotificationManager.shared
    @State private var isNotificationBannerDismissed: Bool = false
    
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
            Button("Accept") {
                if let signal = selectedSignal { handleNotificationAccept(signal) }
            }
            Button("Deny", role: .cancel) {
                if let signal = selectedSignal { handleNotificationDeny(signal) }
            }
        } message: {
            Text(notificationMessage)
        }
        .sheet(isPresented: $showTradeSheet) {
            if let signal = selectedSignal {
                TradeExecutionView(signal: signal, viewModel: viewModel)
            } else if let trade = selectedTrade {
                TradeDetailView(trade: trade, viewModel: viewModel)
            }
        }
        .onAppear {
            setupNotificationObservers()
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewSignalNotification"), object: nil, queue: .main) { notification in
            if let signal = notification.object as? Signal {
                self.selectedSignal = signal
                self.notificationMessage = "\(signal.symbol) \(signal.type.rawValue.uppercased()) @ \(String(format: "%.5f", signal.price))"
                self.showNotificationAlert = true
                #if os(macOS)
                NSSound.beep()
                #endif
            }
        }
        
        NotificationCenter.default.addObserver(forName: .newGodModeInsight, object: nil, queue: .main) { notification in
            if let insight = notification.object as? GodModeInsight {
                Task { @MainActor in
                    #if os(macOS)
                    if insight.type == .newsBroadcast {
                        NSSound(named: "Glass")?.play()
                    }
                    #endif
                }
            }
        }
    }

    private func handleNotificationAccept(_ signal: Signal) {
        coordinator.acceptSignal(signal)
        selectedSignal = nil
        showNotificationAlert = false
    }

    private func handleNotificationDeny(_ signal: Signal) {
        coordinator.denySignal(signal)
        selectedSignal = nil
        showNotificationAlert = false
    }

    // MARK: - Header
    var headerBar: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentCyan)
                    .shadow(color: .accentCyan.opacity(0.5), radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STELLAS V10.3")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Text("ELITE INSTITUTIONAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentCyan)
                }
            }
            Spacer()
            HStack(spacing: 24) {
                headerStat(label: "ACCOUNT", value: viewModel.mt5Login.isEmpty ? "DEMO" : viewModel.mt5Login, color: .accentCyan)
                headerStat(label: "EQUITY", value: String(format: "%@ %.2f", viewModel.accountCurrency, viewModel.accountBalance), color: .accentGreen)
                let dailyPnL = viewModel.totalDailyPnL
                headerStat(label: "DAILY", value: String(format: "%@%.2f", dailyPnL >= 0 ? "+" : "", dailyPnL), color: dailyPnL >= 0 ? .accentGreen : .accentRed)
                HStack(spacing: 8) {
                    PulsingDot(color: viewModel.mt5Connected ? .accentGreen : .accentRed)
                    Text(viewModel.mt5Connected ? "CONNECTED" : coordinator.connectionStatus.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(viewModel.mt5Connected ? .accentGreen : .accentRed)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.bgSecondary)
        .overlay(VStack { Spacer(); Divider().background(Color.borderSubtle) })
    }

    private func headerStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.textMuted)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
    }

    var customTabBar: some View {
        VStack(spacing: 8) {
            ForEach(0..<tabs.count, id: \.self) { index in tabButton(index: index) }
            Spacer()
        }
        .padding(.top, 24)
        .frame(width: 200)
        .background(Color.bgSecondary)
    }

    func tabButton(index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 12) {
                Image(systemName: tabIcons[index]).font(.system(size: 16)).frame(width: 24)
                Text(tabs[index].uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                if index == 0 && coordinator.signals.filter({ $0.status == .pending }).count > 0 {
                    Circle().fill(Color.accentRed).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .foregroundColor(selectedTab == index ? .accentCyan : .textSecondary)
            .background(selectedTab == index ? Color.accentCyan.opacity(0.1) : Color.clear)
            .overlay(HStack { if selectedTab == index { Rectangle().fill(Color.accentCyan).frame(width: 3) }; Spacer() })
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 0:
            LiveSignalsView(viewModel: viewModel, coordinator: coordinator, selectedSignal: $selectedSignal, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet, isNotificationBannerDismissed: $isNotificationBannerDismissed)
        case 1:
            InsightsView(viewModel: viewModel)
        case 2:
            HistoryView(viewModel: viewModel, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet)
        case 3:
            PerformanceView(viewModel: viewModel)
        case 4:
            SystemLogsView(viewModel: viewModel)
        case 5:
            SettingsView(viewModel: viewModel, coordinator: coordinator)
                #if os(macOS)
                .overlay(alignment: .topTrailing) {
                    MT5DisconnectControl(viewModel: viewModel, coordinator: coordinator)
                        .padding(.top, 16)
                        .padding(.trailing, 24)
                }
                #endif
        default:
            Text("Coming Soon").foregroundColor(.textMuted)
        }
    }
}

// MARK: - Advanced Performance View
struct PerformanceView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    private var completedTrades: [TradeRecord] {
        viewModel.tradeHistory.filter { $0.status == .completed }.sorted { ($0.exitTime ?? $0.entryTime) < ($1.exitTime ?? $1.entryTime) }
    }
    private var winningTrades: [TradeRecord] { completedTrades.filter { ($0.pnl ?? 0) > 0 } }
    private var losingTrades: [TradeRecord] { completedTrades.filter { ($0.pnl ?? 0) < 0 } }
    private var grossProfit: Double { winningTrades.compactMap { $0.pnl }.reduce(0, +) }
    private var grossLoss: Double { abs(losingTrades.compactMap { $0.pnl }.reduce(0, +)) }
    private var expectancy: Double { completedTrades.isEmpty ? 0 : completedTrades.compactMap { $0.pnl }.reduce(0, +) / Double(completedTrades.count) }
    private var payoffRatio: Double { grossLoss > 0 && !losingTrades.isEmpty ? (grossProfit / Double(max(1, winningTrades.count))) / (grossLoss / Double(losingTrades.count)) : grossProfit }
    private var averageDurationMinutes: Double {
        let durations = completedTrades.compactMap { trade -> Double? in
            guard let exit = trade.exitTime else { return nil }
            return exit.timeIntervalSince(trade.entryTime) / 60
        }
        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
    }
    private var largestWin: Double { winningTrades.compactMap { $0.pnl }.max() ?? 0 }
    private var largestLoss: Double { losingTrades.compactMap { $0.pnl }.min() ?? 0 }
    private var currentStreak: String {
        guard let last = completedTrades.last else { return "0" }
        let isWin = (last.pnl ?? 0) > 0
        var count = 0
        for trade in completedTrades.reversed() {
            if ((trade.pnl ?? 0) > 0) == isWin { count += 1 } else { break }
        }
        return "\(isWin ? "W" : "L")\(count)"
    }
    private var maxDrawdownFromHistory: Double {
        var equity = 0.0
        var peak = 0.0
        var drawdown = 0.0
        for trade in completedTrades {
            equity += trade.pnl ?? 0
            peak = max(peak, equity)
            drawdown = min(drawdown, equity - peak)
        }
        return abs(drawdown)
    }
    private var recoveryFactor: Double {
        let dd = maxDrawdownFromHistory
        return dd > 0 ? viewModel.totalPnL / dd : viewModel.totalPnL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PERFORMANCE INTELLIGENCE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentCyan).tracking(2)
                        Text("Live broker history • execution quality • risk-adjusted diagnostics")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.textMuted)
                    }
                    Spacer()
                    Text("\(completedTrades.count) CLOSED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.white.opacity(0.05)).cornerRadius(5)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard("NET P&L", String(format: "%@%.2f", viewModel.totalPnL >= 0 ? "+" : "", viewModel.totalPnL), viewModel.totalPnL >= 0 ? .accentGreen : .accentRed, "chart.line.uptrend.xyaxis")
                    metricCard("WIN RATE", String(format: "%.1f%%", viewModel.winRate), .accentGreen, "target")
                    metricCard("PROFIT FACTOR", String(format: "%.2f", viewModel.profitFactor), .accentGold, "arrow.up.right")
                    metricCard("EXPECTANCY", String(format: "%@%.2f", expectancy >= 0 ? "+" : "", expectancy), expectancy >= 0 ? .accentGreen : .accentRed, "function")
                    metricCard("MAX DRAWDOWN", String(format: "%.2f", maxDrawdownFromHistory), .accentRed, "arrow.down.right")
                    metricCard("RECOVERY FACTOR", String(format: "%.2f", recoveryFactor), recoveryFactor >= 0 ? .accentCyan : .accentRed, "gauge.with.dots.needle.67percent")
                    metricCard("PAYOFF RATIO", String(format: "%.2f", payoffRatio), .accentPurple, "scale.3d")
                    metricCard("AVG HOLD", String(format: "%.1fm", averageDurationMinutes), .accentCyan, "timer")
                }

                HStack(spacing: 16) {
                    performanceCard(title: "TRADE QUALITY", icon: "checkmark.seal.fill", color: .accentGreen) {
                        perfRow("Wins", "\(winningTrades.count)", .accentGreen)
                        perfRow("Losses", "\(losingTrades.count)", .accentRed)
                        perfRow("Avg Win", String(format: "%.2f", viewModel.avgWin), .accentGreen)
                        perfRow("Avg Loss", String(format: "%.2f", viewModel.avgLoss), .accentRed)
                        perfRow("Largest Win", String(format: "%.2f", largestWin), .accentGreen)
                        perfRow("Largest Loss", String(format: "%.2f", largestLoss), .accentRed)
                        perfRow("Current Streak", currentStreak, .accentGold)
                    }
                    performanceCard(title: "DIRECTIONAL EDGE", icon: "arrow.left.arrow.right", color: .accentPurple) {
                        directionRow("LONG", viewModel.totalBuyTrades, viewModel.totalBuyWins, viewModel.totalBuyPnL, .accentGreen)
                        directionRow("SHORT", viewModel.totalSellTrades, viewModel.totalSellWins, viewModel.totalSellPnL, .accentRed)
                    }
                }

                performanceCard(title: "TRADING DIAGNOSTICS", icon: "waveform.path.ecg", color: .accentCyan) {
                    HStack(spacing: 24) {
                        diagnostic("Gross Profit", String(format: "%.2f", grossProfit), .accentGreen)
                        diagnostic("Gross Loss", String(format: "%.2f", grossLoss), .accentRed)
                        diagnostic("Total Trades", "\(completedTrades.count)", .accentCyan)
                        diagnostic("Daily P&L", String(format: "%@%.2f", viewModel.totalDailyPnL >= 0 ? "+" : "", viewModel.totalDailyPnL), viewModel.totalDailyPnL >= 0 ? .accentGreen : .accentRed)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.loadTradeHistory() }
    }

    private func metricCard(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        GlassCard(borderColor: color.opacity(0.25)) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                    Text(value).font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
            }.padding(12)
        }
    }

    private func performanceCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(borderColor: color.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary).tracking(1)
                    Spacer()
                }
                Divider().background(Color.borderSubtle)
                content()
            }.padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func perfRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundColor(.textSecondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
    }

    private func directionRow(_ label: String, _ trades: Int, _ wins: Int, _ pnl: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(color)
                Spacer()
                Text(String(format: "%@%.2f", pnl >= 0 ? "+" : "", pnl)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(pnl >= 0 ? .accentGreen : .accentRed)
            }
            perfRow("Trades", "\(trades)", .textPrimary)
            perfRow("Win Rate", String(format: "%.1f%%", trades > 0 ? Double(wins) / Double(trades) * 100 : 0), .accentGreen)
        }
    }

    private func diagnostic(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
    }
}

struct NotificationBanner: View {
    let isAuthorized: Bool
    @Binding var isDismissed: Bool
    var body: some View {
        if !isAuthorized && !isDismissed {
            HStack {
                Image(systemName: "bell.badge.fill").foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Disabled").font(.system(size: 12, weight: .bold))
                    Text("Enable notifications in system settings to receive live trade alerts.").font(.system(size: 11))
                }.foregroundColor(.white)
                Spacer()
                Button(action: {
                    #if os(macOS)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
                    #endif
                }) {
                    Text("ENABLE").font(.system(size: 10, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 5).background(Color.white.opacity(0.2)).cornerRadius(4)
                }.buttonStyle(.plain)
                Button(action: { isDismissed = true }) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
            }
            .padding(12).background(Color.accentRed).cornerRadius(8).padding(.horizontal, 20)
        }
    }
}

struct NoSignalsView: View {
    let connectionStatus: String
    let signalsCount: Int
    let signals: [Signal]
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().stroke(Color.accentCyan.opacity(0.1), lineWidth: 2).frame(width: 80, height: 80)
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 30)).foregroundColor(.accentCyan.opacity(0.3))
            }
            VStack(spacing: 8) {
                Text("SCANNING FOR INSTITUTIONAL FLOW").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                Text(connectionStatus == "Connected" ? "Active WebSocket stream on Port 8890. Waiting for high-probability confluence." : "Waiting for MT5 bridge connection...")
                    .font(.system(size: 11)).foregroundColor(.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            }
            if signalsCount > 0 { Text("\(signalsCount) historical/expired signals hidden.").font(.system(size: 9, design: .monospaced)).foregroundColor(.textMuted) }
            Spacer()
        }.frame(minHeight: 400)
    }
}