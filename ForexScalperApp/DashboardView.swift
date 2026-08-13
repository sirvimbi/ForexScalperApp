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

    // MARK: - Notification Observers
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
                viewModel.allInsights.insert(insight, at: 0)
                #if os(macOS)
                if insight.type == .newsBroadcast {
                    let sound = NSSound(named: "Glass")
                    sound?.play()
                }
                #endif
            }
        }
    }

    private func handleNotificationAccept(_ signal: Signal) {
        Task {
            await coordinator.acceptSignal(signal)
            await MainActor.run {
                self.selectedSignal = nil
                self.showNotificationAlert = false
            }
        }
    }

    private func handleNotificationDeny(_ signal: Signal) {
        self.selectedSignal = nil
        self.showNotificationAlert = false
    }

    // MARK: - Header (macOS)
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
                headerStat(label: "EQUITY", value: String(format: "KES %.2f", viewModel.accountBalance), color: .accentGreen)
                
                let dailyPnL = viewModel.totalDailyPnL
                headerStat(label: "DAILY", value: String(format: "%@%.2f", dailyPnL >= 0 ? "+" : "", dailyPnL), color: dailyPnL >= 0 ? .accentGreen : .accentRed)
                
                HStack(spacing: 8) {
                    PulsingDot(color: coordinator.connectionStatus == "Connected" ? .accentGreen : .accentRed)
                    Text(coordinator.connectionStatus.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(coordinator.connectionStatus == "Connected" ? .accentGreen : .accentRed)
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
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(index: index)
            }
            Spacer()
        }
        .padding(.top, 24)
        .frame(width: 200)
        .background(Color.bgSecondary)
    }

    func tabButton(index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 12) {
                Image(systemName: tabIcons[index])
                    .font(.system(size: 16))
                    .frame(width: 24)
                
                Text(tabs[index].uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                
                Spacer()
                
                if index == 0 && coordinator.signals.filter({ $0.status == .pending }).count > 0 {
                    Circle()
                        .fill(Color.accentRed)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .foregroundColor(selectedTab == index ? .accentCyan : .textSecondary)
            .background(selectedTab == index ? Color.accentCyan.opacity(0.1) : Color.clear)
            .overlay(
                HStack {
                    if selectedTab == index {
                        Rectangle().fill(Color.accentCyan).frame(width: 3)
                    }
                    Spacer()
                }
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 0: LiveSignalsView(viewModel: viewModel, coordinator: coordinator, selectedSignal: $selectedSignal, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet, isNotificationBannerDismissed: $isNotificationBannerDismissed)
        case 1: InsightsView(viewModel: viewModel)
        case 2: HistoryView(viewModel: viewModel, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet)
        case 3: PerformanceView(viewModel: viewModel)
        case 4: SystemLogsView(viewModel: viewModel)
        case 5: SettingsView(viewModel: viewModel, coordinator: coordinator)
        default: Text("Coming Soon").foregroundColor(.textMuted)
        }
    }
}

// MARK: - Performance View
struct PerformanceView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("PERFORMANCE METRICS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentCyan)
                        .tracking(2)
                    Spacer()
                }
                
                HStack(spacing: 16) {
                    VStack(spacing: 16) {
                        let dailyPnL = viewModel.totalDailyPnL
                        StatBox(title: "Total P&L", value: String(format: "KES %.2f", dailyPnL), accentColor: dailyPnL >= 0 ? .accentGreen : .accentRed, icon: "dollarsign.circle.fill")
                        StatBox(title: "Win Rate", value: String(format: "%.1f%%", viewModel.winRate), accentColor: .accentGreen, icon: "target")
                    }
                    
                    VStack(spacing: 16) {
                        StatBox(title: "Profit Factor", value: String(format: "%.2f", viewModel.profitFactor), accentColor: .accentGold, icon: "chart.line.uptrend.xyaxis")
                        StatBox(title: "Avg Trade", value: String(format: "KES %.2f", viewModel.totalPnL / Double(max(1, viewModel.totalTrades))), accentColor: .accentCyan, icon: "clock.fill")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader("TRADE DISTRIBUTION", icon: "chart.pie.fill", color: .accentPurple)
                        Divider().background(Color.borderSubtle)
                        
                        HStack(spacing: 30) {
                            directionBlock(label: "LONG", trades: viewModel.totalBuyTrades, wins: viewModel.totalBuyWins, pnl: viewModel.totalBuyPnL, color: .accentGreen)
                            Divider().frame(height: 80).background(Color.borderSubtle)
                            directionBlock(label: "SHORT", trades: viewModel.totalSellTrades, wins: viewModel.totalSellWins, pnl: viewModel.totalSellPnL, color: .accentRed)
                        }
                    }
                    .padding(20)
                }
            }
            .padding(24)
        }
        .background(Color.bgPrimary)
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
    
    private func directionBlock(label: String, trades: Int, wins: Int, pnl: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 10, weight: .black)).foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                perfRow(label: "Trades", value: "\(trades)", color: .textPrimary)
                perfRow(label: "Win Rate", value: String(format: "%.0f%%", trades > 0 ? (Double(wins)/Double(trades)*100) : 0), color: .accentGreen)
                perfRow(label: "P&L", value: String(format: "KES %.2f", pnl), color: pnl >= 0 ? .accentGreen : .accentRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func perfRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundColor(.textSecondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
    }
}

// MARK: - Supporting Views
struct NotificationBanner: View {
    let isAuthorized: Bool
    @Binding var isDismissed: Bool
    
    var body: some View {
        if !isAuthorized && !isDismissed {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Disabled")
                        .font(.system(size: 12, weight: .bold))
                    Text("Enable notifications in system settings to receive live trade alerts.")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white)
                Spacer()
                Button(action: {
                    #if os(macOS)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                    #endif
                }) {
                    Text("ENABLE")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Button(action: { isDismissed = true }) {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.accentRed)
            .cornerRadius(8)
            .padding(.horizontal, 20)
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
                Circle()
                    .stroke(Color.accentCyan.opacity(0.1), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 30))
                    .foregroundColor(.accentCyan.opacity(0.3))
            }
            
            VStack(spacing: 8) {
                Text("SCANNING FOR INSTITUTIONAL FLOW")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                
                Text(connectionStatus == "Connected" 
                     ? "Active WebSocket stream on Port 8890. Waiting for high-probability confluence."
                     : "Waiting for MT5 bridge connection...")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            if signalsCount > 0 {
                Text("\(signalsCount) historical/expired signals hidden.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
            
            Spacer()
        }
        .frame(minHeight: 400)
    }
}
