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
            topBar
            Divider().background(Color.borderSubtle)
            #endif
            ScrollView {
                LazyVStack(spacing: 12) {
                    NotificationBanner(isAuthorized: NotificationManager.shared.isAuthorized, isDismissed: $isNotificationBannerDismissed)
                    #if os(iOS)
                    HStack { Text("Live Signals").font(.largeTitle).bold().foregroundColor(.white); Spacer(); Text("LIVE").font(.caption).foregroundColor(.accentGreen) }.padding(.horizontal)
                    #endif
                    let pending = coordinator.signals.filter { $0.status == .pending }
                    if pending.isEmpty {
                        NoSignalsView(connectionStatus: viewModel.mt5Connected ? "Connected" : coordinator.connectionStatus, signalsCount: coordinator.signals.count, signals: coordinator.signals)
                    } else {
                        ForEach(pending.sorted(by: { $0.timestamp > $1.timestamp })) { signal in signalCard(signal).id(signal.id) }
                    }
                }.padding(20).animation(.easeInOut, value: pending.count)
            }
            .refreshable { viewModel.refreshData() }
            .onAppear { viewModel.startAutoRefresh(interval: 2.0) }
            .onDisappear { viewModel.stopAutoRefresh() }
        }
        .background(Color.bgPrimary)
        #if os(iOS)
        .navigationTitle("Stellas")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if os(macOS)
    private var topBar: some View {
        HStack(spacing: 12) {
            Text("LIVE SIGNALS").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).tracking(2)
            Spacer()
            newsTicker
            Spacer()
            HStack(spacing: 4) { Circle().fill(Color.accentGreen).frame(width: 6, height: 6); Text("LIVE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentGreen) }.padding(.horizontal, 8).padding(.vertical, 4).background(Color.accentGreen.opacity(0.1)).cornerRadius(4)
            HStack(spacing: 6) {
                Text("SOURCE:").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textMuted)
                ForEach(SignalSource.allCases.filter { $0 != .both }, id: \.self) { source in
                    Button { coordinator.switchSignalSource(source) } label: { Text(source.displayName).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(coordinator.selectedSignalSource == source ? .accentCyan : .textSecondary).padding(.horizontal, 7).padding(.vertical, 4).background(coordinator.selectedSignalSource == source ? Color.accentCyan.opacity(0.18) : Color.bgCardHover).cornerRadius(5) }.buttonStyle(.plain)
                }
            }
            Button { viewModel.refreshData() } label: { Image(systemName: "arrow.clockwise").foregroundColor(.accentCyan) }.buttonStyle(.plain).help("Refresh live data")
            HStack(spacing: 8) {
                Toggle(isOn: $viewModel.isAutoTradeEnabled) { Image(systemName: viewModel.isAutoTradeEnabled ? "bolt.fill" : "bolt.slash.fill").foregroundColor(.accentGreen) }.toggleStyle(SwitchToggleStyle(tint: .accentGreen)).scaleEffect(0.7)
                if viewModel.isAutoTradeEnabled { Text("\(Int(viewModel.minAutoTradeConfidence))%").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentGold) }
            }
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var newsTicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.americas.fill").foregroundColor(.accentGold)
            if let next = newsService.upcomingEvents.first(where: { $0.time > Date() }) {
                Text(next.title.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary).lineLimit(1)
                Text(formatNewsTime(next.time)).font(.system(size: 9, design: .monospaced)).foregroundColor(.accentGold)
                TagBadge(text: next.impact.rawValue, color: next.impact.color)
            } else { Text("NO UPCOMING HIGH IMPACT NEWS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.textMuted) }
        }.padding(.horizontal, 10).padding(.vertical, 5).background(Color.bgSecondary.opacity(0.5)).cornerRadius(6)
    }
    #endif

    private func formatNewsTime(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff < 3600 { return "in \(max(0, Int(diff / 60)))m" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return "at \(f.string(from: date))"
    }

    @ViewBuilder
    private func signalCard(_ signal: Signal) -> some View {
        let isBuy = signal.type == .buy
        let sideColor: Color = isBuy ? .accentGreen : .accentRed
        let minutes = Int(signal.timeRemaining) / 60
        let seconds = Int(signal.timeRemaining) % 60

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) { Image(systemName: isBuy ? "arrow.up.circle.fill" : "arrow.down.circle.fill"); Text(signal.type.displayName).font(.system(size: 16, weight: .bold)) }.foregroundColor(sideColor)
                Spacer()
                Text(signal.source.rawValue).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.white).padding(.horizontal, 7).padding(.vertical, 4).background(Color.white.opacity(0.08)).cornerRadius(5)
                TagBadge(text: signal.timeframe.uppercased(), color: .accentPurple)
                if signal.status == .pending { Text(String(format: "%02d:%02d", minutes, seconds)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(signal.isExpiringSoon ? .accentRed : .accentGold) }
            }

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(signal.symbol).font(.system(size: 24, weight: .black, design: .monospaced)).foregroundColor(.white)
                    if signal.selfLearningInsight != nil { Label("INSIGHT", systemImage: "brain.head.profile").font(.system(size: 9, weight: .bold)).foregroundColor(.accentCyan) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(String(format: "KES %.5f", signal.price)).font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                    HStack(spacing: 8) { Text("Vol: \(Int(signal.volume))").font(.caption).foregroundColor(.white.opacity(0.75)); Text("Confidence: \(Int(signal.confidence))%").font(.caption).foregroundColor(.white) }
                }
            }

            BarIndicator(value: signal.confidence / 100, color: signal.confidence < 70 ? .accentRed : signal.confidence < 80 ? .orange : signal.confidence < 90 ? .accentGold : .accentGreen).frame(height: 4)

            HStack(spacing: 18) {
                valueBlock("ENTRY", String(format: "%.5f", signal.price), .white)
                if let sl = signal.stopLoss { valueBlock("SL", String(format: "%.5f", sl), .accentRed) }
                if let tp = signal.takeProfit { valueBlock("TP", String(format: "%.5f", tp), .accentGreen) }
                if let lots = signal.positionSize { valueBlock("LOTS", String(format: "%.2f", lots), .accentCyan) }
                Spacer()
            }

            if signal.status == .pending {
                HStack(spacing: 10) {
                    Button { selectedSignal = signal; showTradeSheet = true } label: { Label("REVIEW / EXECUTE", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }.padding(.vertical, 9).background(Color.accentGreen).foregroundColor(.white).cornerRadius(7).buttonStyle(.plain)
                    Button { viewModel.denySignal(signal) } label: { Label("DENY", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity) }.padding(.vertical, 9).background(Color.accentRed).foregroundColor(.white).cornerRadius(7).buttonStyle(.plain)
                }
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCard).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(sideColor.opacity(0.3), lineWidth: 1)))
        .shadow(color: sideColor.opacity(0.18), radius: 8, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let tradeId = signal.tradeId, let trade = viewModel.activeTrades.first(where: { $0.id == tradeId }) ?? viewModel.tradeHistory.first(where: { $0.id == tradeId }) { selectedTrade = trade; showTradeSheet = true }
            else if signal.status == .pending { selectedSignal = signal; showTradeSheet = true }
        }
    }

    private func valueBlock(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.55)); Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(color) }
    }
}