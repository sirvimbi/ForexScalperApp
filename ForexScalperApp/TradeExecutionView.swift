// TradeExecutionView.swift
import SwiftUI

struct TradeExecutionView: View {
    let signal: Signal
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) var dismiss
    @State private var positionSizeText: String = "1000"
    @State private var positionSize: Double = 1000
    @State private var stopLoss: Double = 0
    @State private var takeProfit: Double = 0
    @State private var isIGConnected: Bool = false
    @State private var showIGError: Bool = false
    @State private var igErrorMessage: String = ""
    @State private var isExecuting: Bool = false
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            Form {
                Section("Signal Details") {
                    HStack {
                        Text("Symbol"); Spacer()
                        Text(signal.symbol).bold()
                    }
                    HStack {
                        Text("Direction"); Spacer()
                        Text(signal.type.displayName)
                            .foregroundColor(signal.type == .buy ? .green : .red)
                            .bold()
                    }
                    HStack {
                        Text("Entry Price"); Spacer()
                        Text(String(format: "$%.5f", signal.price)).monospacedDigit()
                    }
                    HStack {
                        Text("Confidence"); Spacer()
                        Text("\(Int(signal.confidence))%")
                            .foregroundColor(confidenceColor)
                            .bold()
                    }
                    
                    // Show source info
                    HStack {
                        Text("Source"); Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(signal.source == .binance ? Color.yellow :
                                      signal.source == .ig ? Color.purple :
                                      viewModel.activeSource == .ig ? Color.purple : Color.accentCyan)
                                .frame(width: 6, height: 6)
                            Text(sourceDisplayName)
                                .font(.caption.bold())
                        }
                    }
                    
                    // Show IG connection status if applicable
                    if shouldExecuteOnIG {
                        HStack {
                            Text("IG Status"); Spacer()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(viewModel.igConnected ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.igConnected ? "CONNECTED" : "DISCONNECTED")
                                    .font(.caption)
                                    .foregroundColor(viewModel.igConnected ? .green : .red)
                            }
                        }
                    }
                }
                
                Section("Position Sizing") {
                    HStack {
                        Text("Position Size"); Spacer()
                        TextField("Amount", text: $positionSizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: positionSizeText) { newValue in
                                if let v = Double(newValue) { positionSize = v; calculateRisk() }
                            }
                    }
                    HStack {
                        ForEach(["500", "1000", "5000", "10000"], id: \.self) { amount in
                            Button(action: {
                                positionSizeText = amount
                                positionSize = Double(amount) ?? 1000
                                calculateRisk()
                            }) {
                                let k = (Int(amount) ?? 0) / 1000
                                Text(k == 1 ? "$1k" : "$\(k)k")
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                Section("Risk Management") {
                    HStack {
                        Text("Stop Loss"); Spacer()
                        Text(String(format: "$%.5f", stopLoss))
                            .foregroundColor(.red)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Take Profit"); Spacer()
                        Text(String(format: "$%.5f", takeProfit))
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Risk Amount"); Spacer()
                        Text(String(format: "$%.2f", riskAmount))
                            .foregroundColor(.red)
                            .bold()
                    }
                    HStack {
                        Text("Potential Reward"); Spacer()
                        Text(String(format: "$%.2f", potentialReward))
                            .foregroundColor(.green)
                            .bold()
                    }
                    HStack {
                        Text("Risk/Reward Ratio"); Spacer()
                        Text("1:\(String(format: "%.1f", rewardRatio))")
                            .foregroundColor(rewardRatio >= 2 ? .green : .orange)
                            .bold()
                    }
                }
                
                if shouldExecuteOnIG && !viewModel.igConnected {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("IG is not connected. Trade will only be saved locally.")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                }
                
                if isExecuting {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Execute Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Execute") { executeTrade() }
                        .bold()
                        .disabled(isExecuting || (shouldExecuteOnIG && !viewModel.igConnected))
                }
            }
            .alert("IG Trading Error", isPresented: $showIGError) {
                Button("OK", role: .cancel) { }
                Button("View Settings") {
                    // Switch to settings tab
                    NotificationCenter.default.post(name: .switchToSettingsTab, object: nil)
                    dismiss()
                }
            } message: {
                Text(igErrorMessage)
            }
        }
        .onAppear {
            calculateRisk()
            checkIGConnection()
        }
        #else
        // macOS version
        VStack(spacing: 20) {
            HStack {
                Text("Execute Trade").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Signal Details
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(signal.symbol).font(.title.bold())
                            HStack {
                                Text(signal.type.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(signal.type == .buy ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                    .foregroundColor(signal.type == .buy ? .green : .red)
                                    .cornerRadius(4)
                                Text("\(Int(signal.confidence))% Confidence")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                                Text(signal.timeframe.uppercased())
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.2))
                                    .foregroundColor(.purple)
                                    .cornerRadius(4)
                                
                                // Source badge
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(signal.source == .binance ? Color.yellow :
                                              signal.source == .ig ? Color.purple :
                                              viewModel.activeSource == .ig ? Color.purple : Color.accentCyan)
                                        .frame(width: 6, height: 6)
                                    Text(sourceDisplayName)
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Entry Price").font(.caption).foregroundColor(.secondary)
                            Text(String(format: "$%.5f", signal.price))
                                .font(.title3.monospacedDigit())
                        }
                    }
                    .padding(.horizontal)
                    
                    // IG Connection Status (if applicable)
                    if shouldExecuteOnIG {
                        HStack {
                            Image(systemName: viewModel.igConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(viewModel.igConnected ? .green : .yellow)
                            Text(viewModel.igConnected ? "IG Connected" : "IG Disconnected - Local only")
                                .font(.caption)
                                .foregroundColor(viewModel.igConnected ? .green : .yellow)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(viewModel.igConnected ? Color.green.opacity(0.1) : Color.yellow.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    Divider()
                    
                    // Position Size
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position Size").font(.headline)
                        HStack {
                            Text("$").font(.title3).foregroundColor(.secondary)
                            TextField("Amount", text: $positionSizeText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 150)
                                .onChange(of: positionSizeText) { newValue in
                                    if let v = Double(newValue) {
                                        positionSize = v
                                        calculateRisk()
                                    }
                                }
                        }
                        HStack(spacing: 8) {
                            ForEach(["500", "1000", "5000", "10000"], id: \.self) { amount in
                                Button(action: {
                                    positionSizeText = amount
                                    positionSize = Double(amount) ?? 1000
                                    calculateRisk()
                                }) {
                                    let k = (Int(amount) ?? 0) / 1000
                                    Text(k == 1 ? "$1k" : "$\(k)k")
                                        .font(.caption)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Risk Analysis
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Risk Analysis").font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Stop Loss").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.5f", stopLoss))
                                    .font(.body.monospacedDigit()).foregroundColor(.red)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Take Profit").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.5f", takeProfit))
                                    .font(.body.monospacedDigit()).foregroundColor(.green)
                            }
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Risk Amount").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.2f", riskAmount))
                                    .font(.body.monospacedDigit()).foregroundColor(.red)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Potential Reward").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.2f", potentialReward))
                                    .font(.body.monospacedDigit()).foregroundColor(.green)
                            }
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Risk/Reward").font(.caption).foregroundColor(.secondary)
                                Text("1:\(String(format: "%.1f", rewardRatio))")
                                    .font(.body.bold())
                                    .foregroundColor(rewardRatio >= 2 ? .green : .orange)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            Divider()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Decline") {
                    viewModel.denySignal(signal)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .foregroundColor(.red)
                
                Spacer()
                
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing)
                }
                
                Button("Execute Trade") { executeTrade() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .disabled(isExecuting || (shouldExecuteOnIG && !viewModel.igConnected))
            }
            .padding()
        }
        .frame(width: 550, height: 650)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            calculateRisk()
            checkIGConnection()
        }
        .alert("IG Trading Error", isPresented: $showIGError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(igErrorMessage)
        }
        #endif
    }
    
    // MARK: - Computed Properties
    
    private var riskAmount: Double {
        let max = viewModel.accountBalance * viewModel.riskPerTrade
        return min(positionSize * 0.01, max)
    }
    
    private var potentialReward: Double { riskAmount * 2 }
    
    private var rewardRatio: Double {
        guard riskAmount > 0 else { return 0 }
        return potentialReward / riskAmount
    }
    
    private var confidenceColor: Color {
        signal.confidence >= 80 ? .green : signal.confidence >= 60 ? .orange : .red
    }
    
    private var sourceDisplayName: String {
        if signal.source != .auto && signal.source != .both {
            return signal.source.displayName
        }
        return viewModel.activeSource.displayName
    }
    
    private var shouldExecuteOnIG: Bool {
        return signal.source == .ig ||
               viewModel.activeSource == .ig ||
               (signal.source == .auto && viewModel.activeSource == .ig)
    }
    
    // MARK: - Methods
    
    private func checkIGConnection() {
        isIGConnected = viewModel.igConnected
    }
    
    private func calculateRisk() {
        let riskPerUnit = riskAmount / positionSize
        let priceMove = signal.price * riskPerUnit
        
        if signal.type == .buy {
            stopLoss = signal.price - priceMove
            takeProfit = signal.price + priceMove * 2
        } else {
            stopLoss = signal.price + priceMove
            takeProfit = signal.price - priceMove * 2
        }
    }
    
    private func executeTrade() {
        // Prevent double execution
        guard !isExecuting else { return }
        isExecuting = true
        
        // Validate position size
        guard positionSize > 0 else {
            showIGError = true
            igErrorMessage = "Please enter a valid position size"
            isExecuting = false
            return
        }
        
        // Check IG connection if needed
        if shouldExecuteOnIG && !viewModel.igConnected {
            showIGError = true
            igErrorMessage = "IG is not connected. Please connect to IG in Settings or switch to local trading mode."
            isExecuting = false
            return
        }
        
        // Create a copy of the signal with updated values
        var updatedSignal = signal
        updatedSignal.status = .accepted
        updatedSignal.acceptedAt = Date()
        updatedSignal.acceptedPrice = signal.price
        updatedSignal.positionSize = positionSize
        updatedSignal.stopLoss = stopLoss
        updatedSignal.takeProfit = takeProfit
        updatedSignal.expiryTime = Date().addingTimeInterval(signal.expiryDuration * 2)
        
        // Set the source based on user selection and connection status
        if viewModel.activeSource == .ig && viewModel.igConnected {
            updatedSignal.source = .ig
            print("📤 Setting signal source to IG for execution")
        } else if viewModel.activeSource == .binance {
            updatedSignal.source = .binance
        } else if viewModel.activeSource == .auto {
            // In auto mode, prefer IG if connected and confidence is high
            if viewModel.igConnected && signal.confidence >= 75 {
                updatedSignal.source = .ig
                print("📤 Auto mode: Using IG for execution (connected, confidence \(Int(signal.confidence))%)")
            } else {
                updatedSignal.source = .binance
                print("📤 Auto mode: Using Binance for execution")
            }
        }
        
        print("📊 Executing trade: \(updatedSignal.symbol) \(updatedSignal.type) on \(updatedSignal.source.displayName)")
        print("   Position Size: $\(String(format: "%.2f", positionSize))")
        print("   Stop Loss: $\(String(format: "%.5f", stopLoss))")
        print("   Take Profit: $\(String(format: "%.5f", takeProfit))")
        
        if shouldExecuteOnIG && viewModel.igConnected {
            print("   ⚡ This trade will be sent to IG")
        } else {
            print("   📋 This trade will be saved locally only")
        }
        
        // Pass to view model for execution
        viewModel.acceptSignal(updatedSignal)
        
        // Small delay to allow for execution before dismissing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
                    
                    // Show IG Deal ID if available
                    if let dealId = trade.externalDealId {
                        HStack {
                            Text("IG Deal ID"); Spacer()
                            Text(dealId)
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
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
                        if let pct = trade.pnlPercent {
                            HStack {
                                Text("Percentage"); Spacer()
                                Text(String(format: "%.2f%%", pct))
                                    .foregroundColor(pnl >= 0 ? .green : .red)
                                    .bold()
                            }
                        }
                    }
                }
                
                Section("Timeline") {
                    HStack {
                        Text("Entry Time"); Spacer()
                        Text(formatDate(trade.entryTime))
                            .font(.caption)
                    }
                    if let exitTime = trade.exitTime {
                        HStack {
                            Text("Exit Time"); Spacer()
                            Text(formatDate(exitTime))
                                .font(.caption)
                        }
                        let duration = exitTime.timeIntervalSince(trade.entryTime)
                        HStack {
                            Text("Duration"); Spacer()
                            Text(String(format: "%d:%02d", Int(duration)/60, Int(duration)%60))
                                .font(.caption)
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
                                Text(trade.status.rawValue.uppercased())
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(trade.status == .active ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                                    .foregroundColor(trade.status == .active ? .blue : .gray)
                                    .cornerRadius(4)
                                Text("\(Int(trade.confidence))% Confidence")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                                
                                // Show IG badge if applicable
                                if trade.externalDealId != nil {
                                    Text("IG")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.purple.opacity(0.2))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                            }
                            
                            // Show IG Deal ID
                            if let dealId = trade.externalDealId {
                                Text("IG Deal ID: \(dealId)")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                    .padding(.top, 4)
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
                            Spacer()
                            if let exitPrice = trade.exitPrice {
                                VStack(alignment: .trailing) {
                                    Text("Exit Price").font(.caption).foregroundColor(.secondary)
                                    Text(String(format: "$%.5f", exitPrice))
                                        .font(.title3.monospacedDigit())
                                }
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
                                Spacer()
                                if let pct = trade.pnlPercent {
                                    VStack(alignment: .trailing) {
                                        Text("P&L %").font(.caption).foregroundColor(.secondary)
                                        Text(String(format: "%.2f%%", pct))
                                            .font(.title3.bold())
                                            .foregroundColor(pnl >= 0 ? .green : .red)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position Details").font(.headline)
                        Divider()
                        if let ps = trade.positionSize {
                            HStack {
                                Text("Position Size").font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "$%.2f", ps)).font(.subheadline.monospacedDigit())
                            }
                        }
                        if let sl = trade.stopLoss {
                            HStack {
                                Text("Stop Loss").font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "$%.5f", sl))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.red)
                            }
                        }
                        if let tp = trade.takeProfit {
                            HStack {
                                Text("Take Profit").font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "$%.5f", tp))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline").font(.headline)
                        Divider()
                        HStack {
                            Text("Entry Time").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                            Text(formatDate(trade.entryTime)).font(.subheadline)
                        }
                        if let exitTime = trade.exitTime {
                            HStack {
                                Text("Exit Time").font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(exitTime)).font(.subheadline)
                            }
                            let duration = exitTime.timeIntervalSince(trade.entryTime)
                            HStack {
                                Text("Duration").font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%d:%02d", Int(duration)/60, Int(duration)%60))
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
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
        .background(Color(.windowBackgroundColor))
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
