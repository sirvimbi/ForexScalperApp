import SwiftUI

struct LiveSignalsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var coordinator: RefactoredAppCoordinator
    @ObservedObject var newsService = NewsService.shared
    @Binding var selectedSignal: Signal?
    @Binding var selectedTrade: TradeRecord?
    @Binding var showTradeSheet: Bool
    @Binding var isNotificationBannerDismissed: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("LIVE SIGNALS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                
                Spacer()
                
                newsTicker
                
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
                            HStack(spacing: 3) {
                                Image(systemName: source.icon)
                                    .font(.system(size: 9))
                                Text(source.displayName)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 8)
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
                    NotificationBanner(isAuthorized: NotificationManager.shared.isAuthorized, isDismissed: $isNotificationBannerDismissed)
                    
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
                        NoSignalsView(connectionStatus: viewModel.mt5Connected ? "Connected" : coordinator.connectionStatus, signalsCount: allSignals.count, signals: allSignals)
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
        .navigationTitle("Stellas")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    var newsTicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .foregroundColor(.accentGold)
                .font(.system(size: 12))
            
            if newsService.isFetching && newsService.upcomingEvents.isEmpty {
                Text("LOADING CALENDAR...")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.textMuted)
            } else if let nextEvent = newsService.upcomingEvents.first(where: { $0.time > Date() }) {
                HStack(spacing: 6) {
                    TagBadge(text: nextEvent.currency, color: .white.opacity(0.8))
                    Text(nextEvent.title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    
                    Text(formatNewsTime(nextEvent.time))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.accentGold)
                    
                    TagBadge(text: nextEvent.impact.rawValue, color: nextEvent.impact.color)
                }
            } else {
                Text("NO UPCOMING HIGH IMPACT NEWS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }
    
    private func formatNewsTime(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff < 3600 {
            return "in \(Int(diff/60))m"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "at \(formatter.string(from: date))"
        }
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
                                   ? ((signal.pnl ?? 0) >= 0 ? .accentGreen : .accentRed)
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(signal.symbol)
                                .font(.system(size: 24, weight: .bold))
                            
                            if let insight = signal.selfLearningInsight {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 10))
                                    Text("INSIGHT")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentCyan.opacity(0.2))
                                .foregroundColor(.accentCyan)
                                .cornerRadius(4)
                                .help(insight)
                            }
                        }
                    }
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
                                                 ((signal.pnl ?? 0) >= 0 ? .accentGreen : .accentRed))
                            Text(signal.status == .accepted ? "Trade Active" : "Trade Closed")
                                .foregroundColor(signal.status == .accepted ? .accentCyan :
                                                 ((signal.pnl ?? 0) >= 0 ? .accentGreen : .accentRed))
                                .font(.headline)
                            Spacer()
                            if let pnl = signal.pnl {
                                Text(String(format: "P/L: %@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl))
                                    .font(.caption.bold())
                                    .foregroundColor(pnl >= 0 ? .accentGreen : .accentRed)
                            }
                        }
                        
                        if let acceptedPrice = signal.acceptedPrice {
                            HStack {
                                Text("Entry ").font(.caption).foregroundColor(.textSecondary)
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
                                    Text("Stop Loss").font(.caption).foregroundColor(.textMuted)
                                    Text(String(format: "%@%.5f", viewModel.currencySymbol, stopLoss))
                                        .font(.caption.monospacedDigit()).foregroundColor(.accentRed)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Take Profit").font(.caption).foregroundColor(.textMuted)
                                    Text(String(format: "%@%.5f", viewModel.currencySymbol, takeProfit))
                                        .font(.caption.monospacedDigit()).foregroundColor(.accentGreen)
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
                                    .font(.caption).foregroundColor(.accentCyan).italic()
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
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentGreen)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .buttonStyle(.plain)
                        
                        Button(action: { viewModel.denySignal(signal) }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Deny")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentRed)
                        .foregroundColor(.white)
                        .cornerRadius(8)
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
            )
            .shadow(color: color.opacity(0.2), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
