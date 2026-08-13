import SwiftUI
import UserNotifications
import UserNotifications

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var coordinator: RefactoredAppCoordinator
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            Form {
                riskSection
                scalpingConfigSection
                elitePrecisionSection
                tradingPairsSection
                mt5APISection
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
                        Button(action: {
                            saveAllSettings()
                        }) {
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
                                                Text(String(format: "%.2f", viewModel.accountBalance))
                                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentCyan)
                                                Spacer()
                                                Button(action: {
                                                    Task { await viewModel.refreshAccountInfo() }
                                                }) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.caption)
                                                        .foregroundColor(.accentCyan)
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Image(systemName: "lock.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.textMuted)
                                            }
                                            .padding(8)
                                            .background(Color.black.opacity(0.2))
                                            .cornerRadius(4)
                                        }
                                        .frame(width: 120)
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

                                    Divider().background(Color.borderSubtle)

                                    settingsRow("Enable Hourly Limit") {
                                        Toggle("", isOn: $viewModel.enableHourlyLimit)
                                            .toggleStyle(SwitchToggleStyle(tint: .accentRed))
                                            .scaleEffect(0.8)
                                            .labelsHidden()
                                    }
                                    settingsRow("Max Trades per Hour") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.maxHourlyTrades, in: 1...15, step: 1)
                                                .frame(width: 100)
                                                .disabled(!viewModel.enableHourlyLimit)
                                            Text("\(Int(viewModel.maxHourlyTrades))")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(viewModel.enableHourlyLimit ? .accentRed : .textMuted)
                                                .frame(width: 20, alignment: .trailing)
                                        }
                                    }
                                    .opacity(viewModel.enableHourlyLimit ? 1.0 : 0.5)
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
                                                Picker("", selection: $viewModel.scalpingConfig.manualLotSize) {
                                                    ForEach([0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50, 1.00], id: \.self) { size in
                                                        Text(String(format: "%.2f", size)).tag(size)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 80)
                                                .background(Color.black.opacity(0.2))
                                                .cornerRadius(4)
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
                                            Slider(value: $viewModel.scalpingConfig.minVolatilityATR, in: 0.0005...0.02, step: 0.0005)
                                                .frame(width: 120)
                                            Text(String(format: "%.3f%%", viewModel.scalpingConfig.minVolatilityATR))
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 50, alignment: .trailing)
                                        }
                                    }
                                    .help("Minimum ATR % required to consider a trade. Set lower for more signals in quiet markets.")
                                    
                                    settingsRow("Volume Ratio") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.minVolumeRatio, in: 0.0...3.0, step: 0.1)
                                                .frame(width: 120)
                                            Text(String(format: "%.1fx", viewModel.scalpingConfig.minVolumeRatio))
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 50, alignment: .trailing)
                                        }
                                    }
                                    .help("Minimum relative volume surge (Institutional Presence) required to trade. Default: 1.3x.")

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
                                                set: { viewModel.scalpingConfig.minConfluencePillars = $0 }
                                            ), in: 1...7, step: 1)
                                            .frame(width: 120)
                                            Text("\(Int(viewModel.scalpingConfig.minConfluencePillars))/7")
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
                            // ELITE PRECISION V10.0 CARD
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    sectionHeader("ELITE PRECISION V10.0", icon: "target", color: .accentCyan)
                                    Divider().background(Color.borderSubtle)
                                    
                                    settingsRow("Order Flow Filter") {
                                        Toggle("", isOn: $viewModel.scalpingConfig.enableOrderFlowFilter)
                                            .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                            .labelsHidden()
                                    }
                                    
                                    settingsRow("Delta Threshold") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.orderFlowThreshold, in: 10...500, step: 5)
                                                .frame(width: 110)
                                            Text("\(Int(viewModel.scalpingConfig.orderFlowThreshold))")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentCyan)
                                                .frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                    
                                    settingsRow("Smart Pullback") {
                                        Toggle("", isOn: $viewModel.scalpingConfig.enablePullbackEntry)
                                            .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                            .labelsHidden()
                                    }
                                    
                                    if viewModel.scalpingConfig.enablePullbackEntry {
                                        settingsRow("Pullback EMA") {
                                            Stepper("\(Int(viewModel.scalpingConfig.pullbackEMAPeriod))", value: $viewModel.scalpingConfig.pullbackEMAPeriod, in: 5...100)
                                                .labelsHidden()
                                        }
                                    }
                                    
                                    settingsRow("ROC Period") {
                                        Stepper("\(Int(viewModel.scalpingConfig.rocPeriod))", value: $viewModel.scalpingConfig.rocPeriod, in: 1...20)
                                            .labelsHidden()
                                    }
                                    
                                    settingsRow("ML Trend Filter") {
                                        Toggle("", isOn: $viewModel.scalpingConfig.enableMLTrendFilter)
                                            .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                            .labelsHidden()
                                    }
                                    
                                    if viewModel.scalpingConfig.enableMLTrendFilter {
                                        settingsRow("ML Threshold") {
                                            HStack(spacing: 8) {
                                                Slider(value: $viewModel.scalpingConfig.mlConfidenceThreshold, in: 0.5...0.95, step: 0.05)
                                                    .frame(width: 110)
                                                Text(String(format: "%.0f%%", viewModel.scalpingConfig.mlConfidenceThreshold * 100))
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentCyan)
                                                    .frame(width: 42, alignment: .trailing)
                                            }
                                        }
                                    }
                                    
                                    settingsRow("Risk/Reward Check") {
                                        Toggle("", isOn: $viewModel.scalpingConfig.enableRRCheck)
                                            .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                            .labelsHidden()
                                    }
                                    
                                    if viewModel.scalpingConfig.enableRRCheck {
                                        settingsRow("Min R/R Ratio") {
                                            HStack(spacing: 8) {
                                                Slider(value: $viewModel.scalpingConfig.minRRRatio, in: 0.5...5.0, step: 0.1)
                                                    .frame(width: 110)
                                                Text(String(format: "%.1f", viewModel.scalpingConfig.minRRRatio))
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentCyan)
                                                    .frame(width: 42, alignment: .trailing)
                                            }
                                        }
                                    }
                                    
                                    settingsRow("Fixed Stop Loss (Pips)") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.fixedSLPips, in: 5...100, step: 1)
                                                .frame(width: 110)
                                            Text("\(Int(viewModel.scalpingConfig.fixedSLPips))")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentCyan)
                                                .frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                    
                                    settingsRow("Volatility Scale Min") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.volatilityMultiplierMin, in: 0.1...1.0, step: 0.1)
                                                .frame(width: 110)
                                            Text(String(format: "%.1fx", viewModel.scalpingConfig.volatilityMultiplierMin))
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentCyan)
                                                .frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                    
                                    Divider().background(Color.borderSubtle)
                                    
                                    sectionHeader("PARTIAL TP (50/30/20)", icon: "chart.pie.fill", color: .accentGold)
                                    
                                    settingsRow("Level 1 Pips") {
                                        Stepper("\(Int(viewModel.scalpingConfig.partialTP1_Pips))", value: $viewModel.scalpingConfig.partialTP1_Pips, in: 5...50).labelsHidden()
                                    }
                                    settingsRow("Level 2 Pips") {
                                        Stepper("\(Int(viewModel.scalpingConfig.partialTP2_Pips))", value: $viewModel.scalpingConfig.partialTP2_Pips, in: 10...100).labelsHidden()
                                    }
                                    settingsRow("Level 3 Pips") {
                                        Stepper("\(Int(viewModel.scalpingConfig.partialTP3_Pips))", value: $viewModel.scalpingConfig.partialTP3_Pips, in: 15...150).labelsHidden()
                                    }

                                    Divider().background(Color.borderSubtle)
                                    
                                    sectionHeader("STRATEGY WEIGHTS", icon: "scalemass", color: .accentCyan)
                                    
                                    settingsRow("HTF Alignment") { Stepper("\(Int(viewModel.scalpingConfig.weightHTFAlignment))", value: $viewModel.scalpingConfig.weightHTFAlignment, in: 0...100).labelsHidden() }
                                    settingsRow("Momentum Exhaustion") { Stepper("\(Int(viewModel.scalpingConfig.weightMomentumExhaustion))", value: $viewModel.scalpingConfig.weightMomentumExhaustion, in: 0...100).labelsHidden() }
                                    settingsRow("Volume Surge") { Stepper("\(Int(viewModel.scalpingConfig.weightVolumeSurge))", value: $viewModel.scalpingConfig.weightVolumeSurge, in: 0...100).labelsHidden() }
                                    settingsRow("EMA Stack") { Stepper("\(Int(viewModel.scalpingConfig.weightEMAStack))", value: $viewModel.scalpingConfig.weightEMAStack, in: 0...100).labelsHidden() }
                                    settingsRow("Bollinger Reject") { Stepper("\(Int(viewModel.scalpingConfig.weightBollingerRejection))", value: $viewModel.scalpingConfig.weightBollingerRejection, in: 0...100).labelsHidden() }
                                    settingsRow("CCI Cycle") { Stepper("\(Int(viewModel.scalpingConfig.weightCCICycle))", value: $viewModel.scalpingConfig.weightCCICycle, in: 0...100).labelsHidden() }
                                    settingsRow("SAR Trend") { Stepper("\(Int(viewModel.scalpingConfig.weightSARTrend))", value: $viewModel.scalpingConfig.weightSARTrend, in: 0...100).labelsHidden() }
                                    settingsRow("Momentum Surge") { Stepper("\(Int(viewModel.scalpingConfig.weightMomentumSurge))", value: $viewModel.scalpingConfig.weightMomentumSurge, in: 0...100).labelsHidden() }
                                    settingsRow("Order Flow") { Stepper("\(Int(viewModel.scalpingConfig.weightOrderFlow))", value: $viewModel.scalpingConfig.weightOrderFlow, in: 0...100).labelsHidden() }
                                    settingsRow("ML Confirmation") { Stepper("\(Int(viewModel.scalpingConfig.weightMLConfirmed))", value: $viewModel.scalpingConfig.weightMLConfirmed, in: 0...100).labelsHidden() }
                                }
                                .padding(16)
                            }
                        }
                        
                        VStack(spacing: 14) {
                            // MT5 API CONNECTION CARD
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
                                        TextField("http://localhost:8890", text: $viewModel.mt5BridgeURL)
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
                                        Text("|").foregroundColor(.textMuted)
                                        Button("Clear All") { viewModel.activeSymbols.removeAll() }
                                            .font(.caption).foregroundColor(.accentRed).buttonStyle(.plain)
                                        Spacer()
                                        Text("\(viewModel.activeSymbols.count) active").font(.caption2).foregroundColor(.textMuted)
                                    }
                                }
                                .padding(16)
                            }
                            
                            // NEWS FILTER CARD
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    sectionHeader("NEWS FILTER", icon: "globe.americas.fill", color: .accentGold)
                                    Divider().background(Color.borderSubtle)
                                    
                                    Toggle("Enable News Protection", isOn: $viewModel.scalpingConfig.enableNewsFilter)
                                        .toggleStyle(SwitchToggleStyle(tint: .accentGold))
                                        .labelsHidden()
                                    
                                    settingsRow("Pause Before High (min)") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.pauseBeforeHighImpactMinutes, in: 0...120, step: 15)
                                                .frame(width: 100)
                                            Text("\(Int(viewModel.scalpingConfig.pauseBeforeHighImpactMinutes))m")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                    }
                                    
                                    settingsRow("Pause Before Medium (min)") {
                                        HStack(spacing: 8) {
                                            Slider(value: $viewModel.scalpingConfig.pauseBeforeMediumImpactMinutes, in: 0...60, step: 5)
                                                .frame(width: 100)
                                            Text("\(Int(viewModel.scalpingConfig.pauseBeforeMediumImpactMinutes))m")
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentGold)
                                                .frame(width: 40, alignment: .trailing)
                                        }
                                    }
                                    
                                    Toggle("Auto-Raise Spread Tolerance", isOn: $viewModel.scalpingConfig.autoRaiseSpreadDuringNews)
                                        .font(.caption)
                                    
                                    if viewModel.scalpingConfig.autoRaiseSpreadDuringNews {
                                        settingsRow("News Spread Mult") {
                                            HStack(spacing: 8) {
                                                Slider(value: $viewModel.scalpingConfig.newsSpreadMultiplier, in: 1.0...10.0, step: 0.5)
                                                    .frame(width: 100)
                                                Text("\(String(format: "%.1f", viewModel.scalpingConfig.newsSpreadMultiplier))x")
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentGold)
                                                    .frame(width: 40, alignment: .trailing)
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                            }
                            
                            // NOTIFICATION CARD
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    sectionHeader("NOTIFICATIONS & SYSTEM", icon: "bell.badge.fill", color: .accentCyan)
                                    Divider().background(Color.borderSubtle)
                                    
                                    Toggle("Signal Alerts", isOn: $viewModel.notifyOnSignal)
                                        .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                    Toggle("Trade Executions", isOn: $viewModel.notifyOnTrade)
                                        .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                    Toggle("Trade Closures", isOn: $viewModel.notifyOnClose)
                                        .toggleStyle(SwitchToggleStyle(tint: .accentCyan))
                                    
                                    Divider().background(Color.borderSubtle)
                                    
                                    Button(action: {
                                        NotificationManager.shared.requestAuthorization()
                                        Task { @MainActor in
                                            let content = UNMutableNotificationContent()
                                            content.title = "Stellas System Check"
                                            content.body = "Notification pipe is now active and synced."
                                            content.sound = .default
                                            let request = UNNotificationRequest(identifier: "test_mac", content: content, trigger: nil)
                                            try? await UNUserNotificationCenter.current().add(request)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "exclamationmark.shield.fill")
                                            Text("FORCE ENABLE NOTIFICATIONS")
                                        }
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.accentCyan.opacity(0.1))
                                        .foregroundColor(.accentCyan)
                                        .cornerRadius(7)
                                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentCyan.opacity(0.3), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
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
    
    private func saveAllSettings() {
        // Ensure ScalpingConfig is updated before saving
        ScalpingConfig.shared.confidenceThreshold = viewModel.scalpingConfig.confidenceThreshold
        ScalpingConfig.shared.spreadTolerance = viewModel.scalpingConfig.spreadTolerance
        ScalpingConfig.shared.minVolatilityATR = viewModel.scalpingConfig.minVolatilityATR
        ScalpingConfig.shared.minVolumeRatio = viewModel.scalpingConfig.minVolumeRatio
        ScalpingConfig.shared.cooldownSeconds = viewModel.scalpingConfig.cooldownSeconds
        ScalpingConfig.shared.minConfluencePillars = viewModel.scalpingConfig.minConfluencePillars
        ScalpingConfig.shared.brokerSuffix = viewModel.scalpingConfig.brokerSuffix
        ScalpingConfig.shared.enableHourlyLimit = viewModel.enableHourlyLimit
        ScalpingConfig.shared.maxHourlyTrades = Int(viewModel.maxHourlyTrades)
        
        // V10.0 Save Sync
        ScalpingConfig.shared.enableOrderFlowFilter = viewModel.scalpingConfig.enableOrderFlowFilter
        ScalpingConfig.shared.orderFlowThreshold = viewModel.scalpingConfig.orderFlowThreshold
        ScalpingConfig.shared.enablePullbackEntry = viewModel.scalpingConfig.enablePullbackEntry
        ScalpingConfig.shared.pullbackEMAPeriod = viewModel.scalpingConfig.pullbackEMAPeriod
        ScalpingConfig.shared.rocPeriod = viewModel.scalpingConfig.rocPeriod
        ScalpingConfig.shared.enableMLTrendFilter = viewModel.scalpingConfig.enableMLTrendFilter
        ScalpingConfig.shared.mlConfidenceThreshold = viewModel.scalpingConfig.mlConfidenceThreshold
        ScalpingConfig.shared.enableSwingSL = viewModel.scalpingConfig.enableSwingSL
        ScalpingConfig.shared.swingLookback = viewModel.scalpingConfig.swingLookback
        ScalpingConfig.shared.volatilityMultiplierMin = viewModel.scalpingConfig.volatilityMultiplierMin
        
        // V10.0 Partial TP Sync
        ScalpingConfig.shared.partialTP1_Pips = viewModel.scalpingConfig.partialTP1_Pips
        ScalpingConfig.shared.partialTP2_Pips = viewModel.scalpingConfig.partialTP2_Pips
        ScalpingConfig.shared.partialTP3_Pips = viewModel.scalpingConfig.partialTP3_Pips
        
        // Strategy Weights Sync
        ScalpingConfig.shared.weightHTFAlignment = viewModel.scalpingConfig.weightHTFAlignment
        ScalpingConfig.shared.weightMomentumExhaustion = viewModel.scalpingConfig.weightMomentumExhaustion
        ScalpingConfig.shared.weightVolumeSurge = viewModel.scalpingConfig.weightVolumeSurge
        ScalpingConfig.shared.weightEMAStack = viewModel.scalpingConfig.weightEMAStack
        ScalpingConfig.shared.weightBollingerRejection = viewModel.scalpingConfig.weightBollingerRejection
        ScalpingConfig.shared.weightCCICycle = viewModel.scalpingConfig.weightCCICycle
        ScalpingConfig.shared.weightSARTrend = viewModel.scalpingConfig.weightSARTrend
        ScalpingConfig.shared.weightMomentumSurge = viewModel.scalpingConfig.weightMomentumSurge
        ScalpingConfig.shared.weightOrderFlow = viewModel.scalpingConfig.weightOrderFlow
        ScalpingConfig.shared.weightMLConfirmed = viewModel.scalpingConfig.weightMLConfirmed
        ScalpingConfig.shared.fixedSLPips = viewModel.scalpingConfig.fixedSLPips
        ScalpingConfig.shared.enableRRCheck = viewModel.scalpingConfig.enableRRCheck
        ScalpingConfig.shared.minRRRatio = viewModel.scalpingConfig.minRRRatio
        
        viewModel.saveSettings()
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
    
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Spacer()
            content()
        }
    }
}
