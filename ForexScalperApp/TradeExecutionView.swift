import SwiftUI

struct TradeExecutionView: View {
    let signal: Signal
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var positionSize: Double = 0.1
    @State private var stopLoss: Double = 0
    @State private var takeProfit: Double = 0
    @State private var orderType: MT5OrderType = .buy
    @State private var fillingType: MT5FillingType = .ioc
    @State private var executionMode: MT5ExecutionMode = .market
    @State private var deviation: Int = 10
    @State private var comment: String = "ELITE_SCALPER"
    @State private var isExecuting = false

    var body: some View {
        #if os(iOS)
        NavigationView {
            Form {
                Section("Stellas Execution") {
                    HStack { Text("Asset"); Spacer(); Text(signal.symbol).font(.headline).foregroundColor(.accentCyan) }
                    Picker("Order Type", selection: $orderType) { Text("Buy").tag(MT5OrderType.buy); Text("Sell").tag(MT5OrderType.sell); Text("Buy Limit").tag(MT5OrderType.buyLimit); Text("Sell Limit").tag(MT5OrderType.sellLimit) }
                    Picker("Execution", selection: $executionMode) { Text("Market").tag(MT5ExecutionMode.market); Text("Instant").tag(MT5ExecutionMode.instant) }
                    HStack { Text("Volume (Lots)"); Spacer(); TextField("0.1", value: $positionSize, format: .number).multilineTextAlignment(.trailing).frame(width: 80) }
                }
                Section("Risk") {
                    HStack { Text("Price"); Spacer(); Text(String(format: "%.5f", signal.price)).monospacedDigit() }
                    HStack { Text("Stop Loss"); Spacer(); TextField("S/L", value: $stopLoss, format: .number).foregroundColor(.accentRed).multilineTextAlignment(.trailing) }
                    HStack { Text("Take Profit"); Spacer(); TextField("T/P", value: $takeProfit, format: .number).foregroundColor(.accentGreen).multilineTextAlignment(.trailing) }
                }
                Section("Advanced MT5 Config") {
                    Picker("Filling Mode", selection: $fillingType) { Text("IOC").tag(MT5FillingType.ioc); Text("FOK").tag(MT5FillingType.fok); Text("Return").tag(MT5FillingType.any) }
                    Stepper("Deviation: \(deviation)", value: $deviation, in: 0...50)
                    TextField("Comment", text: $comment)
                }
            }
            .navigationTitle("MT5 EXECUTION")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abort") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("EXECUTE") { executeTrade() }.bold().foregroundColor(.accentGreen).disabled(isExecuting) }
            }
        }
        .onAppear { setupInitialValues() }
        #else
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 2) { Text("GOD MODE EXECUTION").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.accentGold); Text(signal.symbol).font(.title.bold()).foregroundColor(.white) }; Spacer(); TagBadge(text: signal.type.displayName, color: signal.type == .buy ? .accentGreen : .accentRed) }.padding().background(Color.bgSecondary)
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard { VStack(alignment: .leading, spacing: 12) { Text("ORDER CONFIGURATION").font(.caption.bold()).foregroundColor(.white.opacity(0.7)); HStack { Text("TYPE").foregroundColor(.white).frame(width: 100, alignment: .leading); Picker("", selection: $orderType) { Text("BUY").tag(MT5OrderType.buy); Text("SELL").tag(MT5OrderType.sell) }.pickerStyle(.segmented) }; HStack { Text("VOLUME").foregroundColor(.white).frame(width: 100, alignment: .leading); TextField("", value: $positionSize, format: .number).textFieldStyle(RoundedBorderTextFieldStyle()); Text("LOTS").font(.caption).foregroundColor(.white.opacity(0.7)) } }.padding() }
                    GlassCard { VStack(alignment: .leading, spacing: 12) { Text("ELITE RISK LEVELS").font(.caption.bold()).foregroundColor(.white.opacity(0.7)); HStack { VStack(alignment: .leading) { Text("STOP LOSS").font(.caption2).foregroundColor(.accentRed); TextField("", value: $stopLoss, format: .number).textFieldStyle(PlainTextFieldStyle()).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.white) }; Spacer(); VStack(alignment: .trailing) { Text("TAKE PROFIT").font(.caption2).foregroundColor(.accentGreen); TextField("", value: $takeProfit, format: .number).textFieldStyle(PlainTextFieldStyle()).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.white).multilineTextAlignment(.trailing) } }.padding() }
                    GlassCard { VStack(alignment: .leading, spacing: 10) { Text("MT5 ENGINE OPTIMIZATION").font(.caption.bold()).foregroundColor(.white.opacity(0.7)); HStack { Text("EXECUTION").foregroundColor(.white).frame(width: 100, alignment: .leading); Picker("", selection: $executionMode) { Text("Market").tag(MT5ExecutionMode.market); Text("Instant").tag(MT5ExecutionMode.instant) }.pickerStyle(.menu).foregroundColor(.white) }; HStack { Text("FILLING").foregroundColor(.white).frame(width: 100, alignment: .leading); Picker("", selection: $fillingType) { Text("IOC").tag(MT5FillingType.ioc); Text("FOK").tag(MT5FillingType.fok) }.pickerStyle(.menu).foregroundColor(.white) } }.padding() }
                }.padding()
            }
            HStack { Button("ABORT") { dismiss() }.buttonStyle(.plain).foregroundColor(.white.opacity(0.8)); Spacer(); Button { executeTrade() } label: { HStack { if isExecuting { ProgressView().scaleEffect(0.5) }; Text("EXECUTE TRADE") }.font(.headline.bold()).padding(.horizontal, 24).padding(.vertical, 12).background(Color.accentGreen).foregroundColor(.bgPrimary).cornerRadius(8) }.buttonStyle(.plain).disabled(isExecuting) }.padding().background(Color.bgSecondary)
        }
        .frame(width: 500, height: 600)
        .background(Color.bgPrimary)
        .onAppear { setupInitialValues() }
        #endif
    }

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
        guard positionSize >= 0.01 else { viewModel.showNotification(title: "Invalid Volume", message: "Minimum trade volume is 0.01 lots"); return }
        var finalSignal = signal
        finalSignal.positionSize = positionSize
        finalSignal.stopLoss = stopLoss > 0 ? stopLoss : nil
        finalSignal.takeProfit = takeProfit > 0 ? takeProfit : nil
        finalSignal.orderType = orderType
        finalSignal.filler = fillingType
        finalSignal.executionMode = executionMode
        finalSignal.deviation = deviation
        finalSignal.comment = comment
        isExecuting = true
        viewModel.acceptSignal(finalSignal)
        viewModel.showNotification(title: "Execution Dispatched", message: "\(orderType.rawValue) \(signal.symbol) @ \(String(format: "%.5f", signal.price))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isExecuting = false; dismiss() }
    }
}

struct TradeDetailView: View {
    let trade: TradeRecord
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text("Trade Details").font(.title2.bold()).foregroundColor(.white); Spacer(); Button("Close") { dismiss() }.foregroundColor(.white) }.padding(.horizontal).padding(.top)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(trade.symbol).font(.title.bold()).foregroundColor(.white)
                    Text(trade.type.displayName).font(.caption.bold()).foregroundColor(trade.type == .buy ? .accentGreen : .accentRed)
                    HStack { Text("Entry").foregroundColor(.white.opacity(0.7)); Spacer(); Text(String(format: "%@%.5f", viewModel.currencySymbol, trade.entryPrice)).foregroundColor(.white).monospacedDigit() }
                    if let exit = trade.exitPrice { HStack { Text("Exit").foregroundColor(.white.opacity(0.7)); Spacer(); Text(String(format: "%@%.5f", viewModel.currencySymbol, exit)).foregroundColor(.white).monospacedDigit() } }
                    if let pnl = trade.pnl { HStack { Text("P&L").foregroundColor(.white.opacity(0.7)); Spacer(); Text(String(format: "%@%@%.2f", pnl >= 0 ? "+" : "", viewModel.currencySymbol, pnl)).foregroundColor(pnl >= 0 ? .accentGreen : .accentRed).bold() } }
                }.padding()
            }
            Button("Close") { dismiss() }.buttonStyle(.borderedProminent).padding()
        }.frame(width: 500, height: 600).background(Color.bgPrimary)
    }
}
