import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedTrade: TradeRecord?
    @Binding var showTradeSheet: Bool
    
    var body: some View {
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
                        
                        Button(action: {
                            Task {
                                await viewModel.prepareCSVExport()
                            }
                        }) {
                            Label("DOWNLOAD CSV", systemImage: "arrow.down.doc.fill")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.accentCyan)
                                .foregroundColor(.bgPrimary)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
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
    
    @ViewBuilder
    func tradeRow(_ trade: TradeRecord, isActive: Bool) -> some View {
        let isBuy = trade.type == .buy
        let pnlColor: Color = (trade.pnl ?? 0) >= 0 ? .accentGreen : .accentRed
        
        Button(action: {
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
}
