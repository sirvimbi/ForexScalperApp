// TradeExecutionView.swift
import SwiftUI

struct TradeExecutionView: View {
    let signal: Signal
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var positionSize: Double = 0.1
    @State private var stopLoss: Double = 0
    @State private var takeProfit: Double = 0
    @State private var orderType: MT5OrderType = .buy
    @State private var fillingType: MT5FillingType = .ioc
    @State private var executionMode: MT5ExecutionMode = .market
    @State private var deviation: Int = 10
    @State private var comment: String = "ELITE_SCALPER"
    
    @State private var isExecuting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            Form {
                Section("God Mode Execution") {
                    HStack {
                        Text("Asset"); Spacer()
                        Text(signal.symbol).font(.headline).foregroundColor(.accentCyan)
                    }
                    
                    Picker("Order Type", selection: $orderType) {
                        Text("Buy").tag(MT5OrderType.buy)
                        Text("Sell").tag(MT5OrderType.sell)
                        Text("Buy Limit").tag(MT5OrderType.buyLimit)
                        Text("Sell Limit").tag(MT5OrderType.sellLimit)
                    }
                    
                    Picker("Execution", selection: $executionMode) {
                        Text("Market").tag(MT5ExecutionMode.market)
                        Text("Instant").tag(MT5ExecutionMode.instant)
                    }
                    
                    HStack {
                        Text("Volume (Lots)"); Spacer()
                        TextField("0.1", value: $positionSize, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                
                Section("Risk (Automatic Elite Levels)") {
                    HStack {
                        Text("Price"); Spacer()
                        Text(String(format: "%.5f", signal.price)).monospacedDigit()
                    }
                    HStack {
                        Text("Stop Loss"); Spacer()
                        TextField("S/L", value: $stopLoss, format: .number)
                            .foregroundColor(.accentRed)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Take Profit"); Spacer()
                        TextField("T/P", value: $takeProfit, format: .number)
                            .foregroundColor(.accentGreen)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Advanced MT5 Config") {
                    Picker("Filling Mode", selection: $fillingType) {
                        Text("IOC").tag(MT5FillingType.ioc)
                        Text("FOK").tag(MT5FillingType.fok)
                        Text("Return").tag(MT5FillingType.any)
                    }
                    Stepper("Deviation: \(deviation)", value: $deviation, in: 0...50)
                    TextField("Comment", text: $comment)
                }
            }
            .navigationTitle("MT5 EXECUTION")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abort") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("EXECUTE") { executeTrade() }
                        .bold()
                        .foregroundColor(.accentGreen)
                        .disabled(isExecuting)
                }
            }
        }
        .onAppear {
            setupInitialValues()
        }
        #else
        // macOS God Mode UI
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(spacing: 16) {
                    executionCard
                    riskCard
                    advancedCard
                }
                .padding()
            }
            
            footer
        }
        .frame(width: 500, height: 600)
        .background(Color.bgPrimary)
        .onAppear {
            setupInitialValues()
        }
        #endif
    }
    
    // MARK: - Components
    
    #if os(macOS)
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOD MODE EXECUTION").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.accentGold)
                Text(signal.symbol).font(.title.bold()).foregroundColor(.white)
            }
            Spacer()
            TagBadge(text: signal.type.displayName, color: signal.type == .buy ? .accentGreen : .accentRed)
        }
        .padding()
        .background(Color.bgSecondary)
    }
    
    var executionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ORDER CONFIGURATION").font(.caption.bold()).foregroundColor(.textMuted)
                
                HStack {
                    Text("Type").frame(width: 100, alignment: .leading)
                    Picker("", selection: $orderType) {
                        Text("BUY").tag(MT5OrderType.buy)
                        Text("SELL").tag(MT5OrderType.sell)
                    }.pickerStyle(.segmented)
                }
                
                HStack {
                    Text("Volume").frame(width: 100, alignment: .leading)
                    TextField("", value: $positionSize, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("LOTS").font(.caption).foregroundColor(.textMuted)
                }
            }
            .padding()
        }
    }
    
    var riskCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ELITE RISK LEVELS").font(.caption.bold()).foregroundColor(.textMuted)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("STOP LOSS").font(.caption2).foregroundColor(.accentRed)
                        TextField("", value: $stopLoss, format: .number)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("TAKE PROFIT").font(.caption2).foregroundColor(.accentGreen)
                        TextField("", value: $takeProfit, format: .number)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding()
        }
    }
    
    var advancedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("MT5 ENGINE OPTIMIZATION").font(.caption.bold()).foregroundColor(.textMuted)
                
                HStack {
                    Text("Execution").frame(width: 100, alignment: .leading)
                    Picker("", selection: $executionMode) {
                        Text("Market").tag(MT5ExecutionMode.market)
                        Text("Instant").tag(MT5ExecutionMode.instant)
                    }.pickerStyle(.menu)
                }
                
                HStack {
                    Text("Filling").frame(width: 100, alignment: .leading)
                    Picker("", selection: $fillingType) {
                        Text("IOC").tag(MT5FillingType.ioc)
                        Text("FOK").tag(MT5FillingType.fok)
                    }.pickerStyle(.menu)
                }
            }
            .padding()
        }
    }
    
    var footer: some View {
        HStack {
            Button("ABORT") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            Button { executeTrade() } label: {
                HStack {
                    if isExecuting { ProgressView().scaleEffect(0.5).tint(.bgPrimary) }
                    Text("EXECUTE TRADE")
                }
                .font(.headline.bold())
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentGreen)
                .foregroundColor(.bgPrimary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isExecuting)
        }
        .padding()
        .background(Color.bgSecondary)
    }
    #endif
    
    private func setupInitialValues() {
        positionSize = signal.positionSize ?? 0.1
        stopLoss = signal.stopLoss ?? 0
        takeProfit = signal.takeProfit ?? 0
        orderType = signal.orderType ?? (signal.type == .buy ? .buy : .sell)
        fillingType = signal.filler ?? .ioc
        executionMode = signal.executionMode ?? .market
        deviation = signal.deviation ?? 10
        comment = signal.comment ?? "GOD_MODE"
    }
    
    private func executeTrade() {
        isExecuting = true
        
        var finalSignal = signal
        finalSignal.positionSize = positionSize
        finalSignal.stopLoss = stopLoss
        finalSignal.takeProfit = takeProfit
        finalSignal.orderType = orderType
        finalSignal.filler = fillingType
        finalSignal.executionMode = executionMode
        finalSignal.deviation = deviation
        finalSignal.comment = comment
        
        viewModel.acceptSignal(finalSignal)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isExecuting = false
            dismiss()
        }
    }
}

// MARK: - Trade Detail View
struct TradeDetailView: View {
    let trade: TradeRecord
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            Form {
                Section("Trade Overview") {
                    HStack {
                        Text("Symbol"); Spacer()
                        Text(trade.symbol).bold()
                    }
                    HStack {
                        Text("Direction"); Spacer()
                        Text(trade.type.displayName)
                            .foregroundColor(trade.type == .buy ? .green : .red)
                            .bold()
                    }
                    HStack {
                        Text("Status"); Spacer()
                        Text(trade.status.rawValue.uppercased())
                            .foregroundColor(trade.status == .active ? .blue : .gray)
                            .bold()
                    }
                }
                
                Section("Prices") {
                    HStack {
                        Text("Entry"); Spacer()
                        Text(String(format: "$%.5f", trade.entryPrice)).monospacedDigit()
                    }
                    if let exitPrice = trade.exitPrice {
                        HStack {
                            Text("Exit"); Spacer()
                            Text(String(format: "$%.5f", exitPrice)).monospacedDigit()
                        }
                    }
                }
                
                if let pnl = trade.pnl {
                    Section("P&L") {
                        HStack {
                            Text("Total"); Spacer()
                            Text(String(format: "%@$%.2f", pnl >= 0 ? "+" : "", pnl))
                                .foregroundColor(pnl >= 0 ? .green : .red)
                                .bold()
                        }
                    }
                }
            }
            .navigationTitle("Trade Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #else
        VStack(spacing: 20) {
            HStack {
                Text("Trade Details").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }.foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trade.symbol).font(.title.bold())
                            HStack {
                                Text(trade.type.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(trade.type == .buy ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                    .foregroundColor(trade.type == .buy ? .green : .red)
                                    .cornerRadius(4)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Entry Price").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.5f", trade.entryPrice))
                                    .font(.title3.monospacedDigit())
                            }
                        }
                        Divider()
                        if let pnl = trade.pnl {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("P&L").font(.caption).foregroundColor(.secondary)
                                    Text(String(format: "%@$%.2f", pnl >= 0 ? "+" : "", pnl))
                                        .font(.title2.bold())
                                        .foregroundColor(pnl >= 0 ? .green : .red)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.bgSecondary)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            Divider()
            
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .padding()
        }
        .frame(width: 500, height: 600)
        .background(Color.bgPrimary)
        #endif
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let switchToSettingsTab = Notification.Name("switchToSettingsTab")
}
