// DashboardView.swift - Settings Section (Updated)
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Design System (keep existing)
extension Color {
    static let bgPrimary    = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let bgSecondary  = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let bgCard       = Color(red: 0.10, green: 0.13, blue: 0.18)
    static let bgCardHover  = Color(red: 0.13, green: 0.16, blue: 0.22)
    static let accentCyan   = Color(red: 0.00, green: 0.85, blue: 0.95)
    static let accentGold   = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let accentGreen  = Color(red: 0.18, green: 0.95, blue: 0.58)
    static let accentRed    = Color(red: 1.00, green: 0.28, blue: 0.38)
    static let accentPurple = Color(red: 0.60, green: 0.35, blue: 1.00)
    static let borderSubtle = Color.white.opacity(0.07)
    static let borderActive = Color(red: 0.00, green: 0.85, blue: 0.95).opacity(0.4)
    
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textMuted     = Color.white.opacity(0.30)
}

// MARK: - View Modifiers (keep existing)
struct TableHeaderModifier: ViewModifier {
    let width: CGFloat
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.textMuted)
            .frame(width: width, alignment: .leading)
    }
}

extension View {
    func tableHeader(width: CGFloat) -> some View {
        modifier(TableHeaderModifier(width: width))
    }
}

// MARK: - Reusable Components (keep existing)
struct GlowText: View {
    let text: String
    let color: Color
    let font: Font
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .shadow(color: color.opacity(0.8), radius: 6, x: 0, y: 0)
            .shadow(color: color.opacity(0.4), radius: 14, x: 0, y: 0)
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    var borderColor: Color = Color.borderSubtle
    
    init(borderColor: Color = Color.borderSubtle, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.borderColor = borderColor
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
    }
}

struct PulsingDot: View {
    @State private var pulse = false
    var color: Color = .accentGreen
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.6 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear { pulse = true }
    }
}

struct TagBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(4)
    }
}

struct BarIndicator: View {
    let value: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let title: String
    let value: String
    var accentColor: Color = .accentCyan
    var icon: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.7))
                }
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .tracking(1.2)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .shadow(color: accentColor.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 100)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Main Dashboard
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var coordinator: RefactoredAppCoordinator
    @State private var selectedTab = 0
    @State private var showTradeSheet = false
    @State private var selectedSignal: Signal?
    @State private var showNotificationAlert = false
    @State private var notificationMessage = ""
    @State private var selectedTrade: TradeRecord?
    
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var isNotificationBannerDismissed = false
    
    private let tabs     = ["Signals", "History", "Performance", "Settings"]
    private let tabIcons = ["bolt.fill", "clock.fill", "chart.bar.fill", "gearshape.fill"]
    
    init() {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(coordinator: nil))
    }
    
    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            RadialGradient(
                colors: [Color.accentCyan.opacity(0.04), .clear],
                center: .topLeading, startRadius: 0, endRadius: 600
            ).ignoresSafeArea()
            
            #if os(iOS)
            TabView(selection: $selectedTab) {
                liveSignalsView
                    .tabItem { Label("Signals", systemImage: "bolt.fill") }
                    .tag(0)
                historyView
                    .tabItem { Label("History", systemImage: "clock.fill") }
                    .tag(1)
                settingsView
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(3)
            }
            .accentColor(.accentCyan)
            #else
            VStack(spacing: 0) {
                headerBar
                customTabBar
                tabContent
            }
            .frame(minWidth: 900, minHeight: 650)
            #endif
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.updateCoordinator(coordinator)
            viewModel.loadSettings() // Load saved settings on appear
            setupNotificationObservers()
        }
        .sheet(isPresented: $showTradeSheet) {
            if let signal = selectedSignal {
                TradeExecutionView(signal: signal, viewModel: viewModel)
            } else if let trade = selectedTrade {
                TradeDetailView(trade: trade, viewModel: viewModel)
            }
        }
        .alert("Notification", isPresented: $showNotificationAlert) {
            Button("OK", role: .cancel) { }
            Button("View Signals") { selectedTab = 0 }
        } message: {
            Text(notificationMessage)
        }
    }
    
    // MARK: - Notification Observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name.acceptSignal,
            object: nil,
            queue: .main
        ) { notification in
            if let signal = notification.object as? Signal {
                handleNotificationAccept(signal)
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.denySignal,
            object: nil,
            queue: .main
        ) { notification in
            if let signal = notification.object as? Signal {
                handleNotificationDeny(signal)
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.showSignalDashboard,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = 0
        }
    }
    
    private func handleNotificationAccept(_ signal: Signal) {
        notificationMessage = "Accepting signal for \(signal.symbol)..."
        showNotificationAlert = true
        selectedSignal = signal
        
        // Use a longer delay to ensure the alert layout is settled before presenting the sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showTradeSheet = true
        }
    }
    
    private func handleNotificationDeny(_ signal: Signal) {
        notificationMessage = "Signal for \(signal.symbol) denied"
        showNotificationAlert = true
        viewModel.denySignal(signal)
    }
    
    // MARK: - Header (macOS)
    #if os(macOS)
    var headerBar: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentCyan.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.accentCyan)
                        .font(.system(size: 16, weight: .bold))
                        .shadow(color: .accentCyan.opacity(0.8), radius: 6)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("YAJOOT SCALPER")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .tracking(2)
                    Text("GodMode Ver. v6.0")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.textMuted)
                        .tracking(3)
                }
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                PulsingDot(color: .accentGreen)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentGreen)
                    .tracking(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentGreen.opacity(0.08))
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.accentGreen.opacity(0.3), lineWidth: 1))
            
            VStack(spacing: 2) {
                Text("WIN RATE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .tracking(1.5)
                GlowText(
                    text: String(format: "%.1f%%", viewModel.winRate),
                    color: viewModel.winRate >= 80 ? .accentGreen : .accentGold,
                    font: .system(size: 22, weight: .black, design: .rounded)
                )
            }
            
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(width: 1, height: 36)
            
            VStack(spacing: 2) {
                Text("TODAY'S P&L")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .tracking(1.5)
                GlowText(
                    text: viewModel.todayPnLString,
                    color: viewModel.todayPnLColor,
                    font: .system(size: 22, weight: .black, design: .rounded)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color.bgSecondary
                .overlay(Rectangle().fill(Color.borderSubtle).frame(height: 1), alignment: .bottom)
        )
    }
    
    var customTabBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<tabs.count, id: \.self) { i in
                tabButton(index: i)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(Color.bgSecondary)
    }
    
    func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: { selectedTab = index }) {
            HStack(spacing: 6) {
                Image(systemName: tabIcons[index])
                    .font(.system(size: 11, weight: .semibold))
                Text(tabs[index].uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.0)
            }
            .foregroundColor(isSelected ? .accentCyan : .textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                VStack {
                    Spacer()
                    if isSelected {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.accentCyan, Color.accentPurple],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(height: 2)
                            .shadow(color: .accentCyan.opacity(0.8), radius: 4)
                    } else {
                        Rectangle().fill(Color.clear).frame(height: 2)
                    }
                }
                .background(isSelected ? Color.accentCyan.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    var tabContent: some View {
        ZStack {
            Color.bgPrimary
            Group {
                switch selectedTab {
                case 0: liveSignalsView
                case 1: historyView
                case 2: performanceView
                case 3: settingsView
                default: EmptyView()
                }
            }
        }
    }
    #endif
    
    // MARK: - Live Signals
    var liveSignalsView: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("LIVE SIGNALS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.accentGreen)
                        .frame(width: 6, height: 6)
                    Text("LIVE 0.5s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentGreen.opacity(0.1))
                .cornerRadius(4)
                
                HStack(spacing: 8) {
                    Text("SOURCE:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.textMuted)
                        .tracking(1)
                    
                    ForEach(SignalSource.allCases.filter { $0 != .both }, id: \.self) { source in
                        Button(action: {
                            coordinator.switchSignalSource(source)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: source.icon)
                                    .font(.system(size: 10))
                                Text(source.displayName)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                coordinator.selectedSignalSource == source ?
                                (source == .binance ? Color.yellow.opacity(0.3) :
                                    source == .ig ? Color.purple.opacity(0.3) :
                                    Color.accentCyan.opacity(0.3)) :
                                    Color.bgCardHover
                            )
                            .foregroundColor(
                                coordinator.selectedSignalSource == source ?
                                (source == .binance ? .yellow :
                                    source == .ig ? .purple :
                                    .accentCyan) :
                                    .textSecondary
                            )
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        coordinator.selectedSignalSource == source ?
                                        (source == .binance ? Color.yellow.opacity(0.5) :
                                            source == .ig ? Color.purple.opacity(0.5) :
                                            Color.accentCyan.opacity(0.5)) :
                                            Color.borderSubtle,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .help(source == .auto ? "Auto-switch between sources based on reliability" :
                                source == .binance ? "Use Binance signals only" :
                                "Use IG signals only")
                    }
                }
                
                Button(action: { viewModel.refreshData() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                            .animation(
                                viewModel.isRefreshing
                                    ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: viewModel.isRefreshing
                            )
                        Text("REFRESH")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(.accentCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentCyan.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentCyan.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRefreshing)
                
                Divider()
                    .background(Color.borderSubtle)
                    .frame(height: 20)
                    .padding(.horizontal, 4)
                
                // AUTO-TRADE TOGGLE & SLIDER
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Toggle(isOn: $viewModel.isAutoTradeEnabled) {
                            Image(systemName: viewModel.isAutoTradeEnabled ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 10))
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentGreen))
                        .scaleEffect(0.7)
                        .frame(width: 45)
                    }
                    
                    if viewModel.isAutoTradeEnabled {
                        HStack(spacing: 8) {
                            Text("\(Int(viewModel.minAutoTradeConfidence))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentGold)
                                .frame(width: 30)
                            
                            Slider(value: $viewModel.minAutoTradeConfidence, in: 50...98, step: 1)
                                .frame(width: 80)
                                .accentColor(.accentGold)
                            
                            Image(systemName: "target")
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(viewModel.isAutoTradeEnabled ? Color.accentGreen.opacity(0.05) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(viewModel.isAutoTradeEnabled ? Color.accentGreen.opacity(0.2) : Color.clear, lineWidth: 1)
                )
                .animation(.spring(), value: viewModel.isAutoTradeEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider().background(Color.borderSubtle)
            #endif
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !notificationManager.isAuthorized && !isNotificationBannerDismissed {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.accentGold)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications are disabled")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Enable them to receive real-time signals.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)
                            }
                            
                            Spacer()
                            
                            Button("Settings") {
                                #if os(macOS)
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                                #else
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                                #endif
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentCyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentCyan.opacity(0.1))
                            .cornerRadius(4)
                            
                            Button(action: { isNotificationBannerDismissed = true }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.bgCard)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1))
                        .padding(.bottom, 8)
                    }

                    #if os(iOS)
                    HStack {
                        Text("Live Signals")
                            .font(.largeTitle).bold()
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    #endif
                    
                    // ELITE SIGNAL RECONCILIATION
                    let allSignals = coordinator.signals
                    let pendingSignals = allSignals.filter { $0.status == .pending }
                    
                    if pendingSignals.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.textMuted)
                            Text("No Active Signals")
                                .font(.headline)
                                .foregroundColor(.textSecondary)
                            Text("Waiting for market signals...")
                                .font(.subheadline)
                                .foregroundColor(.textMuted)
                            
                            #if DEBUG
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DEBUG INFO").font(.caption).bold()
                                Text("Connection: \(coordinator.connectionStatus)")
                                Text("Total signals in memory: \(coordinator.signals.count)")
                                
                                if !coordinator.signals.isEmpty {
                                    Text("Latest signals:")
                                        .font(.caption).bold()
                                        .padding(.top, 4)
                                    ForEach(coordinator.signals.prefix(3)) { signal in
                                        HStack {
                                            Circle()
                                                .fill(signal.type == .buy ? Color.green : Color.red)
                                                .frame(width: 8, height: 8)
                                            Text("\(signal.symbol) \(signal.type == .buy ? "BUY" : "SELL")")
                                                .font(.caption)
                                            Text("Status: \(String(describing: signal.status))")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                } else {
                                    Text("No signals in coordinator yet")
                                        .font(.caption)
                                }
                            }
                            .font(.caption)
                            .padding()
                            .background(Color.bgCardHover)
                            .cornerRadius(8)
                            #endif
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .padding(.top, 40)
                    } else {
                        ForEach(pendingSignals.sorted(by: { $0.timestamp > $1.timestamp })) { signal in
                            signalCard(signal)
                                .transition(.opacity.combined(with: .slide))
                                .id(signal.id)
                        }
                    }
                }
                .padding(20)
                .animation(.easeInOut, value: coordinator.signals.filter { $0.status == .pending }.count)
            }
            .refreshable {
                viewModel.refreshData()
            }
            .onAppear {
                viewModel.startAutoRefresh(interval: 0.5)
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
        }
        #if os(iOS)
        .navigationTitle("Forex Scalper")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    @ViewBuilder
    func signalCard(_ signal: Signal) -> some View {
        let isBuy = signal.type == .buy
        let color: Color = isBuy ? .accentGreen : .accentRed
        let minutes = Int(signal.timeRemaining) / 60
        let seconds = Int(signal.timeRemaining) % 60
        
        Button(action: {
            if let tradeId = signal.tradeId {
                if let trade = viewModel.activeTrades.first(where: { $0.id == tradeId }) ??
                                viewModel.tradeHistory.first(where: { $0.id == tradeId }) {
                    selectedTrade = trade
                    showTradeSheet = true
                }
            } else if signal.status == .pending {
                selectedSignal = signal
                showTradeSheet = true
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: isBuy ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 20))
                        Text(signal.type.displayName)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(color)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(signal.source == .binance ? Color.yellow : Color.purple)
                            .frame(width: 6, height: 6)
                        Text(signal.source.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(signal.source == .binance ? Color.yellow.opacity(0.2) : Color.purple.opacity(0.2))
                    .cornerRadius(6)
                    
                    TagBadge(text: signal.timeframe.uppercased(), color: .accentPurple)
                    
                    if signal.status != .pending {
                        TagBadge(
                            text: signal.status.rawValue.uppercased(),
                            color: signal.status == .accepted ? .accentCyan :
                                   signal.status == .completed
                                        ? (signal.pnl ?? 0 >= 0 ? .accentGreen : .accentRed)
                                        : .accentGold
                        )
                    }
                    
                    if signal.status == .pending {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "timer").font(.system(size: 12))
                                Text(String(format: "%02d:%02d", minutes, seconds))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(signal.isExpiringSoon ? .accentRed : .accentGold)
                                    .monospacedDigit()
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 2)
                                    Rectangle()
                                        .fill(signal.isExpiringSoon ? Color.accentRed : Color.accentGold)
                                        .frame(width: geo.size.width * signal.progressPercentage, height: 2)
                                }
                            }
                            .frame(width: 60, height: 2)
                        }
                    }
                }
                
                HStack {
                    Text(signal.symbol)
                        .font(.system(size: 24, weight: .bold))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: "KES %.5f", signal.price))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        HStack {
                            if signal.volume > 0 {
                                Text("Vol: \(Int(signal.volume))")
                                    .font(.caption).foregroundColor(.textSecondary)
                            }
                            Text("Confidence: \(Int(signal.confidence))%")
                                .font(.caption).foregroundColor(.textSecondary)
                        }
                    }
                }
                
                BarIndicator(
                    value: signal.confidence / 100,
                    color: signal.confidence < 70 ? .accentRed :
                           signal.confidence < 80 ? .orange :
                           signal.confidence < 90 ? .accentGold : .accentGreen
                )
                .frame(height: 4)
                
                if signal.status == .accepted || signal.status == .completed {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: signal.status == .accepted ? "clock.fill" : "checkmark.circle.fill")
                                .foregroundColor(signal.status == .accepted ? .accentCyan :
                                               (signal.pnl ?? 0 >= 0 ? .accentGreen : .accentRed))
                            Text(signal.status == .accepted ? "Trade Active" : "Trade Closed")
                                .foregroundColor(signal.status == .accepted ? .accentCyan :
                                               (signal.pnl ?? 0 >= 0 ? .accentGreen : .accentRed))
                                .font(.headline)
                            Spacer()
                            if let pnl = signal.pnl {
                                Text(String(format: "P&L: %@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl))
                                    .font(.caption.bold())
                                    .foregroundColor(pnl >= 0 ? .accentGreen : .accentRed)
                            }
                        }
                        
                        if let acceptedPrice = signal.acceptedPrice {
                            HStack {
                                Text("Entry: ").font(.caption).foregroundColor(.textSecondary)
                                Text(String(format: "%@%.5f", viewModel.currencySymbol, acceptedPrice))
                                    .font(.caption.monospacedDigit()).foregroundColor(.textPrimary)
                                Spacer()
                                if let exitPrice = signal.closedPrice {
                                    Text("Exit: ").font(.caption).foregroundColor(.textSecondary)
                                    Text(String(format: "%@%.5f", viewModel.currencySymbol, exitPrice))
                                        .font(.caption.monospacedDigit()).foregroundColor(.textPrimary)
                                }
                            }
                        }
                        
                        if let stopLoss = signal.stopLoss, let takeProfit = signal.takeProfit {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Stop Loss").font(.caption2).foregroundColor(.textMuted)
                                    Text(String(format: "%@%.5f", viewModel.currencySymbol, stopLoss))
                                        .font(.caption2.monospacedDigit()).foregroundColor(.accentRed)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Take Profit").font(.caption2).foregroundColor(.textMuted)
                                    Text(String(format: "%@%.5f", viewModel.currencySymbol, takeProfit))
                                        .font(.caption2.monospacedDigit()).foregroundColor(.accentGreen)
                                }
                            }
                        }
                        
                        if let positionSize = signal.positionSize {
                            HStack {
                                Text("Position Size: ").font(.caption).foregroundColor(.textSecondary)
                                Text(String(format: "%.2f Lots", positionSize))
                                    .font(.caption.monospacedDigit()).foregroundColor(.accentCyan)
                                Spacer()
                                Text("Click to view details")
                                    .font(.caption2).foregroundColor(.accentCyan).italic()
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                
                if signal.status == .pending {
                    HStack(spacing: 12) {
                        Button(action: {
                            selectedSignal = signal
                            showTradeSheet = true
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Review Trade")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentGreen)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { viewModel.denySignal(signal) }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Deny")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentRed)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.2), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    var historyView: some View {
        #if os(iOS)
        NavigationView { historyContent }
        #else
        historyContent
        #endif
    }
    
    var historyContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    #if os(macOS)
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DashboardTimeFilter.allCases, id: \.self) { filter in
                                    filterButton(filter)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button(action: { viewModel.refreshData() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                                    Text("SYNC MT5")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .tracking(1.0)
                                }
                                .foregroundColor(.accentCyan)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentCyan.opacity(0.1))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentCyan.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button(action: { viewModel.clearHistory() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash").font(.system(size: 11))
                                    Text("CLEAR")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .tracking(1.0)
                                }
                                .foregroundColor(.accentRed)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentRed.opacity(0.1))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentRed.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.clearAllHistory() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash.fill").font(.system(size: 11))
                                    Text("CLEAR ALL")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .tracking(1.0)
                                }
                                .foregroundColor(.accentRed)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentRed.opacity(0.15))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentRed.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 20)
                    }
                    #endif
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            StatBox(title: "Total Trades", value: "\(viewModel.totalTrades)", accentColor: .accentCyan, icon: "chart.bar.fill")
                            StatBox(title: "Win Rate", value: String(format: "%.1f%%", viewModel.winRate), accentColor: .accentGreen, icon: "checkmark.circle.fill")
                            StatBox(title: "Profit Factor", value: String(format: "%.2f", viewModel.profitFactor), accentColor: .accentGold, icon: "multiply.circle.fill")
                            StatBox(title: "Avg Win", value: String(format: "%@%.2f", viewModel.currencySymbol, viewModel.avgWin), accentColor: .accentGreen, icon: "arrow.up.right")
                            StatBox(title: "Avg Loss", value: String(format: "%@%.2f", viewModel.currencySymbol, viewModel.avgLoss), accentColor: .accentRed, icon: "arrow.down.right")
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    if !viewModel.activeTrades.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACTIVE TRADES")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentCyan)
                                .padding(.horizontal, 20)
                            ForEach(viewModel.activeTrades) { trade in
                                tradeRow(trade, isActive: true)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    #if os(iOS)
                    HStack {
                        Text("History")
                            .font(.largeTitle).bold()
                        Spacer()
                        
                        if let url = viewModel.exportURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.accentCyan)
                            }
                        } else {
                            Button(action: { Task { await viewModel.prepareCSVExport() } }) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.accentCyan)
                            }
                        }

                        Button(action: { viewModel.refreshData() }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.accentCyan)
                        }
                    }
                    .padding(.horizontal)

                    List {
                        ForEach(viewModel.tradeHistory) { trade in
                            tradeRow(trade, isActive: false)
                        }
                    }
                    .listStyle(PlainListStyle())
                    #else
                    HStack {
                        Text("MASTER TRADE HISTORY")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentCyan)
                            .tracking(2)
                        Spacer()
                        
                        if let url = viewModel.exportURL {
                            ShareLink("EXPORT CSV", item: url)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.accentCyan.opacity(0.1))
                                .foregroundColor(.accentCyan)
                                .cornerRadius(5)
                        } else {
                            Button(action: {
                                Task {
                                    await viewModel.prepareCSVExport()
                                }
                            }) {
                                Label("PREPARE CSV", systemImage: "doc.text.fill")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.accentCyan.opacity(0.1))
                                    .foregroundColor(.accentCyan)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    GlassCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("SYMBOL").tableHeader(width: 90)
                                Text("TYPE").tableHeader(width: 60)
                                Text("ENTRY").tableHeader(width: 110)
                                Text("EXIT").tableHeader(width: 110)
                                Text("P&L").tableHeader(width: 110)
                                Text("RESULT").tableHeader(width: 70)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            
                            Divider().background(Color.borderSubtle)
                            
                            if viewModel.tradeHistory.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 30)).foregroundColor(.textMuted)
                                        Text("No trade history")
                                            .font(.subheadline).foregroundColor(.textMuted)
                                    }
                                    .padding(.vertical, 40)
                                    Spacer()
                                }
                            } else {
                                ForEach(viewModel.tradeHistory) { trade in
                                    tradeRow(trade, isActive: false)
                                        .padding(.horizontal, 16)
                                    Divider().background(Color.borderSubtle)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    #endif
                }
                .padding(.vertical, 20)
                .frame(minHeight: geometry.size.height)
            }
        }
        #if os(iOS)
        .navigationTitle("History")
        #endif
    }
    
    func filterButton(_ filter: DashboardTimeFilter) -> some View {
        Button(action: { viewModel.updateTimeFilter(filter) }) {
            Text(filter.rawValue)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(viewModel.selectedTimeFilter == filter ? Color.accentCyan : Color.bgCardHover)
                .foregroundColor(viewModel.selectedTimeFilter == filter ? .bgPrimary : .textPrimary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    func tradeRow(_ trade: TradeRecord, isActive: Bool) -> some View {
        let isBuy = trade.type == .buy
        let pnlColor: Color = (trade.pnl ?? 0) >= 0 ? .accentGreen : .accentRed
        
        return Button(action: {
            selectedTrade = trade
            showTradeSheet = true
        }) {
            #if os(iOS)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(trade.symbol).font(.headline)
                    Spacer()
                    Text(trade.type.displayName)
                        .foregroundColor(isBuy ? .green : .red)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isBuy ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .cornerRadius(4)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Entry").font(.caption).foregroundColor(.gray)
                        Text(String(format: "%@%.5f", viewModel.currencySymbol, trade.entryPrice)).font(.subheadline).monospacedDigit()
                    }
                    Spacer()
                    if let exitPrice = trade.exitPrice {
                        VStack(alignment: .trailing) {
                            Text("Exit").font(.caption).foregroundColor(.gray)
                            Text(String(format: "%@%.5f", viewModel.currencySymbol, exitPrice)).font(.subheadline).monospacedDigit()
                        }
                    } else {
                        TagBadge(text: trade.status.rawValue.uppercased(), color: trade.status == .active ? .accentCyan : .accentGold)
                    }
                    if let pnl = trade.pnl {
                        VStack(alignment: .trailing) {
                            Text("P&L").font(.caption).foregroundColor(.gray)
                            Text(String(format: "%@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl))
                                .foregroundColor(pnl >= 0 ? .green : .red)
                                .bold().monospacedDigit()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            #else
            HStack {
                Text(trade.symbol)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .frame(width: 90, alignment: .leading)
                
                TagBadge(text: trade.type.displayName, color: isBuy ? .accentGreen : .accentRed)
                    .frame(width: 60, alignment: .leading)
                
                Text(String(format: "%@%.5f", viewModel.currencySymbol, trade.entryPrice))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .frame(width: 110, alignment: .leading)
                
                Group {
                    if let exit = trade.exitPrice {
                        Text(String(format: "%@%.5f", viewModel.currencySymbol, exit))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    } else {
                        TagBadge(text: trade.status.rawValue.uppercased(), color: trade.status == .active ? .accentCyan : .accentGold)
                    }
                }
                .frame(width: 110, alignment: .leading)
                
                Group {
                    if let pnl = trade.pnl {
                        Text(String(format: "%@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(pnlColor)
                    } else {
                        Text("—").foregroundColor(.textMuted)
                    }
                }
                .frame(width: 110, alignment: .leading)
                
                Group {
                    if let pnl = trade.pnl {
                        if pnl > 0 { TagBadge(text: "WIN", color: .accentGreen) }
                        else if pnl < 0 { TagBadge(text: "LOSS", color: .accentRed) }
                        else { TagBadge(text: "BREAK", color: .textMuted) }
                    } else {
                        Text("—").foregroundColor(.textMuted)
                    }
                }
                .frame(width: 70, alignment: .leading)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            #endif
        }
        .buttonStyle(.plain)
    }
    
    var performanceView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("PERFORMANCE ANALYTICS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentCyan)
                            .tracking(2)
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(DashboardTimeFilter.allCases, id: \.self) { f in
                                Button(action: { viewModel.updateTimeFilter(f) }) {
                                    Text(f.rawValue)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(viewModel.selectedTimeFilter == f
                                                    ? Color.accentCyan : Color.bgCardHover)
                                        .foregroundColor(viewModel.selectedTimeFilter == f
                                                          ? .bgPrimary : .textSecondary)
                                        .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            StatBox(title: "Total Trades", value: "\(viewModel.totalTrades)", accentColor: .accentCyan, icon: "chart.bar.fill")
                            StatBox(title: "Return on Equity", value: String(format: "%.1f%%", viewModel.winRate), accentColor: viewModel.winRate >= 0 ? .accentGreen : .accentRed, icon: "checkmark.circle.fill")
                            StatBox(title: "Profit Factor", value: String(format: "%.2f", viewModel.profitFactor), accentColor: .accentGold, icon: "multiply.circle.fill")
                            StatBox(title: "Net P&L", value: viewModel.totalPnLString, accentColor: viewModel.totalPnLColor, icon: "chart.line.uptrend.xyaxis")
                            StatBox(title: "Today's P&L", value: viewModel.todayPnLString, accentColor: viewModel.todayPnLColor, icon: "calendar.badge.clock")
                            StatBox(title: "Avg Win", value: String(format: "%@%.2f", viewModel.currencySymbol, viewModel.avgWin), accentColor: .accentGreen, icon: "arrow.up.right")
                            StatBox(title: "Avg Loss", value: String(format: "%@%.2f", viewModel.currencySymbol, viewModel.avgLoss), accentColor: .accentRed, icon: "arrow.down.right")
                            StatBox(title: "Max Drawdown", value: String(format: "%@%.2f", viewModel.currencySymbol, viewModel.maxDrawdown), accentColor: .accentRed, icon: "arrow.down.to.line")
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    HStack(alignment: .top, spacing: 14) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                sectionHeader("WIN / LOSS BREAKDOWN", icon: "chart.pie.fill", color: .accentCyan)
                                
                                let wins = viewModel.tradeHistory.filter { ($0.pnl ?? 0) > 0 }.count
                                let losses = viewModel.tradeHistory.filter { ($0.pnl ?? 0) < 0 }.count
                                let total = max(wins + losses, 1)
                                
                                GeometryReader { g in
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.accentGreen)
                                            .frame(width: g.size.width * CGFloat(wins) / CGFloat(total))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.accentRed)
                                    }
                                }
                                .frame(height: 10)
                                
                                HStack {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.accentGreen).frame(width: 8, height: 8)
                                        Text("Wins: \(wins)")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.accentGreen)
                                    }
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.accentRed).frame(width: 8, height: 8)
                                        Text("Losses: \(losses)")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.accentRed)
                                    }
                                }
                                
                                Divider().background(Color.borderSubtle)
                                
                                perfRow(label: "Best Trade", value: String(format: "+%@%.2f", viewModel.currencySymbol, viewModel.bestTrade), color: .accentGreen)
                                perfRow(label: "Worst Trade", value: String(format: "-%@%.2f", viewModel.currencySymbol, abs(viewModel.worstTrade)), color: .accentRed)
                                perfRow(label: "Avg Duration", value: viewModel.avgTradeDuration)
                                perfRow(label: "Profit Factor", value: String(format: "%.2f", viewModel.profitFactor), color: .accentGold)
                            }
                            .padding(16)
                        }
                        
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                sectionHeader("BY DIRECTION", icon: "arrow.up.arrow.down.circle.fill", color: .accentPurple)
                                
                                let buyTrades = viewModel.tradeHistory.filter { $0.type == .buy }
                                let sellTrades = viewModel.tradeHistory.filter { $0.type == .sell }
                                let buyWins = buyTrades.filter { ($0.pnl ?? 0) > 0 }.count
                                let sellWins = sellTrades.filter { ($0.pnl ?? 0) > 0 }.count
                                let buyPnL = buyTrades.compactMap(\.pnl).reduce(0, +)
                                let sellPnL = sellTrades.compactMap(\.pnl).reduce(0, +)
                                
                                directionBlock(label: "LONG (BUY)", trades: buyTrades.count, wins: buyWins, pnl: buyPnL, color: .accentGreen)
                                
                                Divider().background(Color.borderSubtle)
                                
                                directionBlock(label: "SHORT (SELL)", trades: sellTrades.count, wins: sellWins, pnl: sellPnL, color: .accentRed)
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("PERFORMANCE BY SYMBOL", icon: "list.bullet.rectangle.fill", color: .accentGold)
                            
                            if viewModel.tradeHistory.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No completed trades yet")
                                        .foregroundColor(.textMuted)
                                        .font(.subheadline)
                                        .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                HStack {
                                    Text("SYMBOL").tableHeader(width: 90)
                                    Text("TRADES").tableHeader(width: 60)
                                    Text("WINS").tableHeader(width: 60)
                                    Text("WIN %").tableHeader(width: 70)
                                    Text("NET P&L").tableHeader(width: 100)
                                    Spacer()
                                }
                                .padding(.bottom, 4)
                                
                                Divider().background(Color.borderSubtle)
                                
                                let grouped = Dictionary(grouping: viewModel.tradeHistory, by: \.symbol)
                                let sorted = grouped.sorted { a, b in
                                    let pnlA = a.value.compactMap(\.pnl).reduce(0, +)
                                    let pnlB = b.value.compactMap(\.pnl).reduce(0, +)
                                    return pnlA > pnlB
                                }
                                
                                ForEach(sorted, id: \.key) { symbol, trades in
                                    let wins = trades.filter { ($0.pnl ?? 0) > 0 }.count
                                    let pnl = trades.compactMap(\.pnl).reduce(0, +)
                                    let winPct = trades.isEmpty ? 0.0 : Double(wins) / Double(trades.count) * 100
                                    
                                    HStack {
                                        Text(symbol)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.textPrimary)
                                            .frame(width: 90, alignment: .leading)
                                        Text("\(trades.count)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.textSecondary)
                                            .frame(width: 60, alignment: .leading)
                                        Text("\(wins)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.accentGreen)
                                            .frame(width: 60, alignment: .leading)
                                        Text(String(format: "%.0f%%", winPct))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(winPct >= 50 ? .accentGreen : .accentRed)
                                            .frame(width: 70, alignment: .leading)
                                        Text(String(format: "%@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(pnl >= 0 ? .accentGreen : .accentRed)
                                            .frame(width: 100, alignment: .leading)
                                        
                                        GeometryReader { geo in
                                            let allPnLs = sorted.map { $0.value.compactMap(\.pnl).reduce(0, +) }
                                            let maxAbs = allPnLs.map(abs).max() ?? 1
                                            let ratio = CGFloat(abs(pnl) / maxAbs)
                                            HStack(spacing: 0) {
                                                if pnl >= 0 {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.accentGreen.opacity(0.6))
                                                        .frame(width: geo.size.width * ratio)
                                                } else {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.accentRed.opacity(0.6))
                                                        .frame(width: geo.size.width * ratio)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .frame(height: 6)
                                    }
                                    .padding(.vertical, 6)
                                    
                                    Divider().background(Color.borderSubtle)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                    
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("CUMULATIVE P&L", icon: "waveform.path.ecg", color: .accentCyan)
                            
                            if viewModel.tradeHistory.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No trade data yet")
                                        .foregroundColor(.textMuted)
                                        .font(.subheadline)
                                        .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                let sortedTrades = viewModel.tradeHistory.sorted { $0.entryTime < $1.entryTime }
                                let cumulative: [Double] = sortedTrades.reduce(into: []) { acc, t in
                                    let previous = acc.last ?? 0
                                    acc.append(previous + (t.pnl ?? 0))
                                }
                                let minVal = cumulative.min() ?? 0
                                let maxVal = cumulative.max() ?? 1
                                let range = max(maxVal - minVal, 1)
                                
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    let h = geo.size.height
                                    let step = w / CGFloat(max(cumulative.count - 1, 1))
                                    
                                    ZStack {
                                        ForEach(0..<5) { i in
                                            let y = h * CGFloat(i) / 4
                                            Path { p in
                                                p.move(to: CGPoint(x: 0, y: y))
                                                p.addLine(to: CGPoint(x: w, y: y))
                                            }
                                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                                        }
                                        
                                        let zeroY = h - h * CGFloat((0 - minVal) / range)
                                        Path { p in
                                            p.move(to: CGPoint(x: 0, y: zeroY))
                                            p.addLine(to: CGPoint(x: w, y: zeroY))
                                        }
                                        .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        
                                        if cumulative.count > 1 {
                                            Path { p in
                                                for (i, val) in cumulative.enumerated() {
                                                    let x = CGFloat(i) * step
                                                    let y = h - h * CGFloat((val - minVal) / range)
                                                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                                                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                                                }
                                            }
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.accentCyan, Color.accentPurple],
                                                    startPoint: .leading, endPoint: .trailing
                                                ),
                                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                            )
                                            .shadow(color: .accentCyan.opacity(0.4), radius: 4)
                                        }
                                    }
                                }
                                .frame(height: 140)
                                .padding(.vertical, 4)
                                
                                HStack {
                                    Text("Trade #1")
                                        .font(.caption2).foregroundColor(.textMuted)
                                    Spacer()
                                    Text("Trade #\(cumulative.count)")
                                        .font(.caption2).foregroundColor(.textMuted)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
    }
    
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.textMuted)
                .tracking(1.5)
        }
    }
    
    private func perfRow(label: String, value: String, color: Color = .textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func directionBlock(label: String, trades: Int, wins: Int, pnl: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TagBadge(text: label, color: color)
                Spacer()
                Text("\(trades) trades")
                    .font(.caption).foregroundColor(.textMuted)
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wins").font(.caption2).foregroundColor(.textMuted)
                    Text("\(wins)").font(.system(size: 16, weight: .bold)).foregroundColor(.accentGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win %").font(.caption2).foregroundColor(.textMuted)
                    let pct = trades > 0 ? Double(wins) / Double(trades) * 100 : 0
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(pct >= 50 ? .accentGreen : .accentRed)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net P&L").font(.caption2).foregroundColor(.textMuted)
                    Text(String(format: "%@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(pnl >= 0 ? .accentGreen : .accentRed)
                }
            }
        }
    }
    
    // MARK: - Live Signals
    var settingsView: some View {
        #if os(iOS)
        NavigationView {
            Form {
                riskSection
                scalpingConfigSection
                tradingPairsSection
                mt5APISection
                igAPISection
                notificationsSection
                saveButtonSection
            }
            .navigationTitle("Settings")
        }
        #else
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("SETTINGS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentCyan)
                            .tracking(2)
                        Spacer()
                        Button(action: { viewModel.saveSettings() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                Text("SAVE ALL")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(.bgPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.accentCyan)
                            .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    
                    Divider().background(Color.borderSubtle)
                    
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            // RISK MANAGEMENT CARD
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    sectionHeader("RISK MANAGEMENT", icon: "shield.fill", color: .accentRed)
                                    Divider().background(Color.borderSubtle)
                                    
                                    settingsRow("Account Balance") {
                                        HStack(spacing: 4) {
                                            Text(viewModel.currencySymbol).foregroundColor(.textMuted).font(.subheadline)
                                            HStack {
                                                Text(String(format: "KES %.2f", viewModel.accountBalance))
                                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentCyan)
                                                Spacer()
                                                Button(action: {
                                                    Task { await viewModel.refreshAccountInfo() }
                                                }) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.caption2)
                                                        .foregroundColor(.accentCyan)
                                                }
                                                .buttonStyle(.plain)

                                                Image(systemName: "lock.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.textMuted)
                                            }
                                            .padding(8)
                                            .background(Color.black.opacity(0.2))
                                            .cornerRadius(4)
                                                .frame(width: 120)
                                        }
                                    }
                                    settingsRow("Risk per Trade") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.riskPerTrade, in: 0.005...0.10, step: 0.005)
                                                .frame(width: 110)
                                            Text(String(format: "%.1f%%", viewModel.riskPerTrade * 100))
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                    settingsRow("Max Daily Risk") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.maxDailyRisk, in: 0.01...0.20, step: 0.005)
                                                .frame(width: 110)
                                            Text(String(format: "%.1f%%", viewModel.maxDailyRisk * 100))
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentRed)
                                                .frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                    settingsRow("Max Concurrent Trades") {
                                        Stepper("\(viewModel.maxConcurrentTrades)",
                                                value: $viewModel.maxConcurrentTrades, in: 1...10)
                                            .labelsHidden()
                                            .overlay(
                                                Text("\(viewModel.maxConcurrentTrades)")
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentCyan)
                                                    .frame(width: 28, alignment: .center)
                                                    .offset(x: -46)
                                            )
                                    }
                                }
                                .padding(16)
                            }
                            
                            // SCALPING CONFIGURATION CARD
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    sectionHeader("SCALPING CONFIGURATION", icon: "gauge.high", color: .accentGold)
                                    Divider().background(Color.borderSubtle)
                                    
                                    settingsRow("Manual Volume/Lot") {
                                        HStack(spacing: 8) {
                                            Toggle("", isOn: $viewModel.scalpingConfig.useManualLot)
                                                .toggleStyle(SwitchToggleStyle(tint: .accentGreen))
                                                .scaleEffect(0.8)
                                                .labelsHidden()
                                            
                                            if viewModel.scalpingConfig.useManualLot {
                                                TextField("0.01", value: $viewModel.scalpingConfig.manualLotSize, format: .number)
                                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                                    .frame(width: 50)
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            }
                                        }
                                    }

                                    settingsRow("Confidence Threshold") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.confidenceThreshold, in: 5...95, step: 1)
                                                .frame(width: 120)
                                            Text("\(Int(viewModel.scalpingConfig.confidenceThreshold))%")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 36, alignment: .trailing)
                                        }
                                    }
                                    
                                    settingsRow("Spread Tolerance") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.spreadTolerance, in: 1...30, step: 1)
                                                .frame(width: 120)
                                            Text("\(Int(viewModel.scalpingConfig.spreadTolerance)) bps")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                    
                                    settingsRow("Min Signal Score") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.minScore, in: 10...50, step: 1)
                                                .frame(width: 120)
                                            Text("\(Int(viewModel.scalpingConfig.minScore))")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 30, alignment: .trailing)
                                        }
                                    }
                                    
                                    settingsRow("Volatility Threshold") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.minVolatilityATR, in: 0.005...0.2, step: 0.005)
                                                .frame(width: 120)
                                            Text(String(format: "%.3f%%", viewModel.scalpingConfig.minVolatilityATR))
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 50, alignment: .trailing)
                                        }
                                    }
                                    .help("Minimum ATR % required to consider a trade. Set lower for more signals in quiet markets.")

                                    settingsRow("Broker Suffix") {
                                        HStack(spacing: 8) {
                                            TextField("e.g. m", text: $viewModel.scalpingConfig.brokerSuffix)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .frame(width: 60)
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            Spacer()
                                        }
                                    }
                                    .help("Appends this suffix to symbols for execution (e.g. EURUSD -> EURUSDm for Exness Real).")

                                    settingsRow("Cooldown (seconds)") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.cooldownSeconds, in: 30...600, step: 15)
                                                .frame(width: 120)
                                            Text("\(Int(viewModel.scalpingConfig.cooldownSeconds))s")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                    }

                                    settingsRow("Trend Confluence") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.mandatoryConfluenceLevel, in: 0...3, step: 1)
                                                .frame(width: 120)
                                            let levelText = ["None", "H4", "H4+D1", "Elite"][Int(viewModel.mandatoryConfluenceLevel)]
                                            Text(levelText)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 50, alignment: .trailing)
                                        }
                                        .onChange(of: viewModel.mandatoryConfluenceLevel) { old, newValue in
                                            viewModel.scalpingConfig.mandatoryConfluenceLevel = Int(newValue)
                                        }
                                    }
                                    
                                    settingsRow("Strategy Pillars") {
                                        HStack(spacing: 8) {
                                            Slider(value: Binding(
                                                get: { Double(viewModel.scalpingConfig.minConfluencePillars) },
                                                set: { viewModel.scalpingConfig.minConfluencePillars = Int($0) }
                                            ), in: 1...7, step: 1)
                                            .frame(width: 120)
                                            Text("\(viewModel.scalpingConfig.minConfluencePillars)/7")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 36, alignment: .trailing)
                                        }
                                    }
                                    .help("Minimum number of strategy pillars that must align to trigger a signal.")
                                    .help("0: M1 only, 1: H4 alignment, 2: H4+D1 (Recommended), 3: H4+D1+W1 (Elite Only)")
                                }
                                .padding(16)
                            }
                        }
                        
                        VStack(spacing: 14) {
                            // MT5 API CONNECTION CARD (God Mode)
                            GlassCard(borderColor: viewModel.mt5Connected ? Color.accentCyan.opacity(0.4) : Color.borderSubtle) {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        sectionHeader("MT5 CONNECTION", icon: "chart.bar.fill", color: .accentCyan)
                                        Spacer()
                                        HStack(spacing: 5) {
                                            PulsingDot(color: viewModel.mt5Connected ? .accentGreen : .accentRed)
                                            Text(viewModel.mt5Connected ? "MT5 READY" : "MT5 OFFLINE")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundColor(viewModel.mt5Connected ? .accentGreen : .accentRed)
                                                .tracking(1)
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background((viewModel.mt5Connected ? Color.accentGreen : Color.accentRed).opacity(0.1))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder((viewModel.mt5Connected ? Color.accentGreen : Color.accentRed).opacity(0.3), lineWidth: 1))
                                    }
                                    Divider().background(Color.borderSubtle)
                                    
                                    settingsRow("Bridge URL") {
                                        TextField("http://localhost:8891", text: $viewModel.mt5BridgeURL)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 200)
                                    }

                                    settingsRow("Auth Token") {
                                        SecureField("Bearer Token", text: $viewModel.mt5AuthToken)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 200)
                                    }
                                    
                                    settingsRow("MT5 Login") {
                                        TextField("Account Number", text: $viewModel.mt5Login)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 200)
                                    }
                                    
                                    settingsRow("MT5 Password") {
                                        SecureField("Password", text: $viewModel.mt5Password)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 200)
                                    }
                                    
                                    settingsRow("MT5 Server") {
                                        TextField("Server Name", text: $viewModel.mt5Server)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 200)
                                    }

                                    settingsRow("Magic Number") {
                                        TextField("888888", value: $viewModel.mt5MagicNumber, format: .number)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 100)
                                    }
                                    
                                    HStack(spacing: 10) {
                                        Button(action: {
                                            Task {
                                                await viewModel.connectToMT5()
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                if viewModel.isConnecting {
                                                    ProgressView()
                                                        .scaleEffect(0.5)
                                                        .tint(.bgPrimary)
                                                } else {
                                                    Image(systemName: "bolt.fill")
                                                }
                                                Text(viewModel.isConnecting ? "CONNECTING..." : (viewModel.mt5Connected ? "RECHECK MT5" : "CONNECT MT5"))
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(viewModel.isConnecting ? Color.accentCyan.opacity(0.5) : Color.accentCyan)
                                            .foregroundColor(.bgPrimary)
                                            .cornerRadius(7)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(viewModel.isConnecting)
                                    }
                                }
                                .padding(16)
                            }
                            
                            // ACTIVE TRADING PAIRS CARD
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("ACTIVE TRADING PAIRS", icon: "chart.line.uptrend.xyaxis", color: .accentCyan)
                                    Divider().background(Color.borderSubtle)
                                    
                                    let majorPairs = TradingPair.allCases.filter { !$0.isExotic }.map { $0.rawValue }.sorted()
                                    let exoticPairs = TradingPair.allCases.filter { $0.isExotic }.map { $0.rawValue }.sorted()
                                    
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 16) {
                                            if !majorPairs.isEmpty {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("MAJOR PAIRS").font(.system(size: 10, weight: .bold)).foregroundColor(.accentGold)
                                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                                                        ForEach(majorPairs, id: \.self) { symbol in
                                                            pairToggle(symbol: symbol)
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            if !exoticPairs.isEmpty {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("EXOTIC PAIRS").font(.system(size: 10, weight: .bold)).foregroundColor(.accentPurple)
                                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                                                        ForEach(exoticPairs, id: \.self) { symbol in
                                                            pairToggle(symbol: symbol)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 250)
                                    
                                    HStack {
                                        Button("Select All") { viewModel.activeSymbols = Set(viewModel.availableSymbols) }
                                            .font(.caption).foregroundColor(.accentCyan).buttonStyle(.plain)
                                        Text("·").foregroundColor(.textMuted)
                                        Button("Clear All") { viewModel.activeSymbols.removeAll() }
                                            .font(.caption).foregroundColor(.accentRed).buttonStyle(.plain)
                                        Spacer()
                                        Text("\(viewModel.activeSymbols.count) active").font(.caption2).foregroundColor(.textMuted)
                                    }
                                }
                                .padding(16)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        #endif
    }
    
    @ViewBuilder
    func pairToggle(symbol: String) -> some View {
        let isActive = viewModel.activeSymbols.contains(symbol)
        Button(action: {
            if isActive { viewModel.activeSymbols.remove(symbol) }
            else { viewModel.activeSymbols.insert(symbol) }
        }) {
            HStack {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isActive ? .accentGreen : .textMuted)
                Text(symbol).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isActive ? .textPrimary : .textSecondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentGreen.opacity(0.1) : Color.bgCardHover)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var mt5APISection: some View {
        #if os(iOS)
        Section("MT5 Connection") {
            TextField("Bridge URL", text: $viewModel.mt5BridgeURL)
            SecureField("Auth Token", text: $viewModel.mt5AuthToken)
            TextField("Magic Number", value: $viewModel.mt5MagicNumber, format: .number)
            Button(action: { Task { await viewModel.connectToMT5() } }) {
                Label(viewModel.mt5Connected ? "Reconnect MT5" : "Connect MT5", systemImage: "bolt.fill")
            }
        }
        #else
        EmptyView()
        #endif
    }
    
    private func settingsRow<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.textSecondary)
            Spacer()
            content()
        }
    }
    
    private func updateNotificationSettings() {
        // Update notification settings based on user preferences
        if !viewModel.notifyOnSignal && !viewModel.notifyOnTrade && !viewModel.notifyOnClose && !viewModel.notifyOnExpiry {
            // Disable all notifications
            NotificationManager.shared.removeAllNotifications()
        }
    }
    
    @ViewBuilder
    var riskSection: some View {
        #if os(iOS)
        Section("Risk Management") {
            HStack {
                Text("Account Balance"); Spacer()
                HStack {
                    Text("KES \(String(format: "%.2f", viewModel.accountBalance))")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        Task { await viewModel.refreshAccountInfo() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    Image(systemName: "lock.fill").font(.caption).foregroundColor(.gray)
                }
            }
            HStack {
                Text("Risk per Trade (%)"); Spacer()
                TextField("Percentage", value: $viewModel.riskPerTrade, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Max Daily Risk (%)"); Spacer()
                TextField("Percentage", value: $viewModel.maxDailyRisk, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Stepper("Max Concurrent Trades: \(viewModel.maxConcurrentTrades)",
                    value: $viewModel.maxConcurrentTrades, in: 1...10)
        }
        #else
        EmptyView()
        #endif
    }
    
    @ViewBuilder
    var scalpingConfigSection: some View {
        #if os(iOS)
        Section("Scalping Configuration") {
            Toggle("Manual Volume/Lot", isOn: $viewModel.scalpingConfig.useManualLot)
            
            if viewModel.scalpingConfig.useManualLot {
                HStack {
                    Text("Lot Size"); Spacer()
                    TextField("0.01", value: $viewModel.scalpingConfig.manualLotSize, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack {
                Text("Min Confidence %"); Spacer()
                Slider(value: $viewModel.scalpingConfig.confidenceThreshold, in: 5...98, step: 1)
                Text("\(Int(viewModel.scalpingConfig.confidenceThreshold))%")
            }
            HStack {
                Text("Trend Confluence"); Spacer()
                Slider(value: $viewModel.mandatoryConfluenceLevel, in: 0...3, step: 1)
                let levelText = ["None", "H4", "H4+D1", "Elite"][Int(viewModel.mandatoryConfluenceLevel)]
                Text(levelText).font(.caption).foregroundColor(.accentGold)
            }
            .onChange(of: viewModel.mandatoryConfluenceLevel) { old, newValue in
                viewModel.scalpingConfig.mandatoryConfluenceLevel = Int(newValue)
            }
            HStack {
                Text("Spread Tolerance (bps)"); Spacer()
                Slider(value: $viewModel.scalpingConfig.spreadTolerance, in: 1...30, step: 1)
                Text("\(Int(viewModel.scalpingConfig.spreadTolerance))")
            }
            HStack {
                Text("Min Signal Score"); Spacer()
                Slider(value: $viewModel.scalpingConfig.minScore, in: 10...50, step: 1)
                Text("\(Int(viewModel.scalpingConfig.minScore))")
            }
            HStack {
                Text("Volatility ATR %"); Spacer()
                Slider(value: $viewModel.scalpingConfig.minVolatilityATR, in: 0.005...0.2, step: 0.005)
                Text(String(format: "%.3f%%", viewModel.scalpingConfig.minVolatilityATR))
            }
            HStack {
                Text("Broker Suffix"); Spacer()
                TextField("m", text: $viewModel.scalpingConfig.brokerSuffix)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }
        }
        #else
        EmptyView()
        #endif
    }
    
    @ViewBuilder
    var tradingPairsSection: some View {
        #if os(iOS)
        Group {
            let majorPairs = TradingPair.allCases.filter { !$0.isExotic }.map { $0.rawValue }.sorted()
            let exoticPairs = TradingPair.allCases.filter { $0.isExotic }.map { $0.rawValue }.sorted()
            
            Section("Major Pairs") {
                ForEach(majorPairs, id: \.self) { symbol in
                    HStack {
                        Text(symbol); Spacer()
                        if viewModel.activeSymbols.contains(symbol) {
                            Image(systemName: "checkmark").foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.activeSymbols.contains(symbol) {
                            viewModel.activeSymbols.remove(symbol)
                        } else {
                            viewModel.activeSymbols.insert(symbol)
                        }
                    }
                }
            }
            
            Section("Exotic Pairs") {
                ForEach(exoticPairs, id: \.self) { symbol in
                    HStack {
                        Text(symbol); Spacer()
                        if viewModel.activeSymbols.contains(symbol) {
                            Image(systemName: "checkmark").foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.activeSymbols.contains(symbol) {
                            viewModel.activeSymbols.remove(symbol)
                        } else {
                            viewModel.activeSymbols.insert(symbol)
                        }
                    }
                }
            }
        }
        #else
        EmptyView()
        #endif
    }
    
    @ViewBuilder
    var igAPISection: some View {
        #if os(iOS)
        Section("IG API Connection") {
            HStack {
                Text("API Key"); Spacer()
                SecureField("Enter API key", text: $viewModel.igAPIKey)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Account ID"); Spacer()
                TextField("Account ID", text: $viewModel.igAccountID)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Environment", selection: $viewModel.igEnvironment) {
                Text("Live").tag("live")
                Text("Demo").tag("demo")
            }
            Toggle("Auto-Reconnect", isOn: $viewModel.igAutoReconnect)
            Button(action: { viewModel.connectToIG() }) {
                Label(viewModel.igConnected ? "Reconnect" : "Connect", systemImage: "bolt.fill")
            }
        }
        #else
        EmptyView()
        #endif
    }
    
    @ViewBuilder
    var notificationsSection: some View {
        #if os(iOS)
        Section("Notifications") {
            Toggle("Signal Alerts", isOn: $viewModel.notifyOnSignal)
            Toggle("Trade Executed", isOn: $viewModel.notifyOnTrade)
            Toggle("Trade Closed", isOn: $viewModel.notifyOnClose)
            Toggle("Expiry Warning", isOn: $viewModel.notifyOnExpiry)
            HStack {
                Text("Confidence Threshold"); Spacer()
                Text("\(Int(viewModel.scalpingConfig.confidenceThreshold))%")
                    .foregroundColor(.secondary)
                Stepper("  ", value: $viewModel.scalpingConfig.confidenceThreshold, in: 5...95, step: 5)
                    .labelsHidden()
            }
        }
        #else
        EmptyView()
        #endif
    }
    
    @ViewBuilder
    var saveButtonSection: some View {
        #if os(iOS)
        Section {
            Button("Save Settings") {
                viewModel.saveSettings()
            }.frame(maxWidth: .infinity)
        }
        #else
        EmptyView()
        #endif
    }
}
