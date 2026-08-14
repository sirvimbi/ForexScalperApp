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

    init(viewModel: DashboardViewModel, coordinator: RefactoredAppCoordinator) { self.viewModel = viewModel; self.coordinator = coordinator }

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
            Button("Accept") { if let signal = selectedSignal { handleNotificationAccept(signal) } }
            Button("Deny", role: .cancel) { if let signal = selectedSignal { handleNotificationDeny(signal) } }
        } message: { Text(notificationMessage) }
        .sheet(isPresented: $showTradeSheet) {
            if let signal = selectedSignal { TradeExecutionView(signal: signal, viewModel: viewModel) }
            else if let trade = selectedTrade { TradeDetailView(trade: trade, viewModel: viewModel) }
        }
        .onAppear { setupNotificationObservers() }
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
                    if insight.type == .newsBroadcast { NSSound(named: "Glass")?.play() }
                    #endif
                }
            }
        }
    }

    private func handleNotificationAccept(_ signal: Signal) { coordinator.acceptSignal(signal); selectedSignal = nil; showNotificationAlert = false }
    private func handleNotificationDeny(_ signal: Signal) { coordinator.denySignal(signal); selectedSignal = nil; showNotificationAlert = false }

    var headerBar: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "bolt.shield.fill").font(.system(size: 22)).foregroundColor(.accentCyan).shadow(color: .accentCyan.opacity(0.5), radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STELLAS V10.3").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.textPrimary)
                    Text("ELITE INSTITUTIONAL").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan)
                }
            }
            Spacer()
            HStack(spacing: 24) {
                headerStat(label: "ACCOUNT", value: viewModel.mt5Login.isEmpty ? "DEMO" : viewModel.mt5Login, color: .accentCyan)
                headerStat(label: "EQUITY", value: String(format: "KES %.2f", viewModel.accountBalance), color: .accentGreen)
                let dailyPnL = viewModel.totalDailyPnL
                headerStat(label: "DAILY", value: String(format: "%@%.2f", dailyPnL >= 0 ? "+" : "", dailyPnL), color: dailyPnL >= 0 ? .accentGreen : .accentRed)
                HStack(spacing: 8) {
                    PulsingDot(color: viewModel.mt5Connected ? .accentGreen : .accentRed)
                    Text(viewModel.mt5Connected ? "CONNECTED" : coordinator.connectionStatus.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(viewModel.mt5Connected ? .accentGreen : .accentRed)
                }.padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.05)).cornerRadius(6)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16).background(Color.bgSecondary).overlay(VStack { Spacer(); Divider().background(Color.borderSubtle) })
    }

    private func headerStat(label: String, value: String, color: Color) -> some View { VStack(alignment: .trailing, spacing: 2) { Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.textMuted); Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(color) } }

    var customTabBar: some View {
        VStack(spacing: 8) { ForEach(0..<tabs.count, id: \.self) { index in tabButton(index: index) }; Spacer() }.padding(.top, 24).frame(width: 200).background(Color.bgSecondary)
    }

    func tabButton(index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 12) {
                Image(systemName: tabIcons[index]).font(.system(size: 16)).frame(width: 24)
                Text(tabs[index].uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                if index == 0 && coordinator.signals.filter({ $0.status == .pending }).count > 0 { Circle().fill(Color.accentRed).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 20).padding(.vertical, 14).foregroundColor(selectedTab == index ? .accentCyan : .textSecondary).background(selectedTab == index ? Color.accentCyan.opacity(0.1) : Color.clear)
            .overlay(HStack { if selectedTab == index { Rectangle().fill(Color.accentCyan).frame(width: 3) }; Spacer() })
        }.buttonStyle(.plain)
    }

    @ViewBuilder var tabContent: some View {
        switch selectedTab {
        case 0: LiveSignalsView(viewModel: viewModel, coordinator: coordinator, selectedSignal: $selectedSignal, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet, isNotificationBannerDismissed: $isNotificationBannerDismissed)
        case 1: InsightsView(viewModel: viewModel)
        case 2: HistoryView(viewModel: viewModel, selectedTrade: $selectedTrade, showTradeSheet: $showTradeSheet)
        case 3: AdvancedPerformanceView(viewModel: viewModel)
        case 4: SystemLogsView(viewModel: viewModel)
        case 5:
            ZStack(alignment: .topTrailing) {
                SettingsView(viewModel: viewModel, coordinator: coordinator)
                MT5DisconnectButton(viewModel: viewModel)
                    .padding(.top, 12).padding(.trailing, 24)
            }
        default: Text("Coming Soon").foregroundColor(.textMuted)
        }
    }
}

#if os(macOS)
private struct MT5DisconnectButton: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        Button {
            Task { await viewModel.disconnectFromMT5() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "power")
                Text("DISCONNECT MT5")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.accentRed)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Color.bgSecondary.opacity(0.96))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentRed.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.mt5Connected)
        .help("Disconnect the app-side MT5 event connection")
    }
}
#endif

struct NotificationBanner: View {
    let isAuthorized: Bool
    @Binding var isDismissed: Bool
    var body: some View {
        if !isAuthorized && !isDismissed {
            HStack {
                Image(systemName: "bell.badge.fill").foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) { Text("Notifications Disabled").font(.system(size: 12, weight: .bold)); Text("Enable notifications in system settings to receive live trade alerts.").font(.system(size: 11)) }.foregroundColor(.white)
                Spacer()
                Button(action: { #if os(macOS) if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) } #endif }) { Text("ENABLE").font(.system(size: 10, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 5).background(Color.white.opacity(0.2)).cornerRadius(4) }.buttonStyle(.plain)
                Button(action: { isDismissed = true }) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
            }.padding(12).background(Color.accentRed).cornerRadius(8).padding(.horizontal, 20)
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
            ZStack { Circle().stroke(Color.accentCyan.opacity(0.1), lineWidth: 2).frame(width: 80, height: 80); Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 30)).foregroundColor(.accentCyan.opacity(0.3)) }
            VStack(spacing: 8) {
                Text("SCANNING FOR INSTITUTIONAL FLOW").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                Text(connectionStatus == "Connected" ? "Active WebSocket stream on Port 8890. Waiting for high-probability confluence." : "Waiting for MT5 bridge connection...").font(.system(size: 11)).foregroundColor(.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            }
            if signalsCount > 0 { Text("\(signalsCount) historical/expired signals hidden.").font(.system(size: 9, design: .monospaced)).foregroundColor(.textMuted) }
            Spacer()
        }.frame(minHeight: 400)
    }
}
