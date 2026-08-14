// SettingsView.swift - V22 integration

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var coordinator: RefactoredAppCoordinator
    @StateObject private var v22TrailingController = V22TrailingActivationController()

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
                Section("V22 TRAILING STOP") { V22TrailingActivationSettingsCard(controller: v22TrailingController) }
                saveButtonSection
            }
            .navigationTitle("Settings")
            .onAppear { v22TrailingController.refreshFromMT5() }
        }
        #else
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("SETTINGS").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).tracking(2)
                        Spacer()
                        Button(action: { saveAllSettings() }) {
                            HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)); Text("SAVE ALL").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1) }
                                .foregroundColor(.bgPrimary).padding(.horizontal, 14).padding(.vertical, 7).background(Color.accentCyan).cornerRadius(7)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 20).padding(.vertical, 14)
                    Divider().background(Color.borderSubtle)
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 20) {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    sectionHeader("RISK MANAGEMENT", icon: "shield.fill", color: .accentRed)
                                    Divider().background(Color.borderSubtle)
                                    settingsRow("Account Balance") {
                                        HStack(spacing: 6) {
                                            Text(viewModel.currencySymbol).foregroundColor(.textMuted).font(.caption)
                                            HStack {
                                                Text(String(format: "%.2f", viewModel.accountBalance)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan)
                                                Spacer()
                                                Button(action: { Task { await viewModel.refreshAccountInfo() } }) { Image(systemName: "arrow.clockwise").font(.caption).foregroundColor(.accentCyan) }.buttonStyle(.plain)
                                                Image(systemName: "lock.fill").font(.caption).foregroundColor(.textMuted)
                                            }.padding(8).background(Color.bgSecondary).cornerRadius(4)
                                        }.frame(width: 160)
                                    }
                                    settingsRow("Risk per Trade") { HStack(spacing: 10) { Slider(value: $viewModel.riskPerTrade, in: 0.005...0.10, step: 0.005).frame(width: 140); Text(String(format: "%.1f%%", viewModel.riskPerTrade * 100)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 50, alignment: .trailing) } }
                                    settingsRow("Max Daily Risk") { HStack(spacing: 10) { Slider(value: $viewModel.maxDailyRisk, in: 0.01...0.20, step: 0.005).frame(width: 140); Text(String(format: "%.1f%%", viewModel.maxDailyRisk * 100)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentRed).frame(width: 50, alignment: .trailing) } }
                                    settingsRow("Max Concurrent Trades") { HStack(spacing: 12) { Text("\(viewModel.maxConcurrentTrades)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.maxConcurrentTrades, in: 1...10).labelsHidden() } }
                                    settingsRow("Daily Trade Limit") { HStack(spacing: 12) { Text("\(viewModel.dailyTradeLimit)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.dailyTradeLimit, in: 1...100).labelsHidden() } }
                                    Divider().background(Color.borderSubtle)
                                    settingsRow("Enable Hourly Limit") { Toggle("", isOn: $viewModel.enableHourlyLimit).toggleStyle(SwitchToggleStyle(tint: .accentRed)).scaleEffect(0.8).labelsHidden() }
                                    settingsRow("Max Trades per Hour") { HStack(spacing: 10) { Slider(value: $viewModel.maxHourlyTrades, in: 1...15, step: 1).frame(width: 120).disabled(!viewModel.enableHourlyLimit); Text("\(Int(viewModel.maxHourlyTrades))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(viewModel.enableHourlyLimit ? .accentRed : .textMuted).frame(width: 30, alignment: .trailing) } }.opacity(viewModel.enableHourlyLimit ? 1.0 : 0.5)
                                }.padding(16)
                            }
                            GlassCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    sectionHeader("SCALPING CONFIGURATION", icon: "gauge.high", color: .accentGold)
                                    Divider().background(Color.borderSubtle)
                                    settingsRow("Manual Volume/Lot") {
                                        HStack(spacing: 10) {
                                            Toggle("", isOn: $viewModel.scalpingConfig.useManualLot).toggleStyle(SwitchToggleStyle(tint: .accentGreen)).scaleEffect(0.8).labelsHidden()
                                            if viewModel.scalpingConfig.useManualLot {
                                                Picker("", selection: $viewModel.scalpingConfig.manualLotSize) { ForEach([0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10,0.15,0.20,0.25,0.30,0.40,0.50,1.00], id: \.self) { size in Text(String(format: "%.2f", size)).tag(size) } }.pickerStyle(MenuPickerStyle()).frame(width: 90).background(Color.bgSecondary).cornerRadius(4).font(.system(size: 12, weight: .bold, design: .monospaced))
                                            }
                                        }
                                    }
                                    settingsRow("Confidence Threshold") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.confidenceThreshold, in: 5...95, step: 1).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.confidenceThreshold))%").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 45, alignment: .trailing) } }
                                    settingsRow("Spread Tolerance") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.spreadTolerance, in: 1...30, step: 1).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.spreadTolerance)) bps").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 60, alignment: .trailing) } }
                                    settingsRow("Min Signal Score") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.minScore, in: 10...50, step: 1).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.minScore))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 40, alignment: .trailing) } }
                                    settingsRow("Volatility Threshold") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.minVolatilityATR, in: 0.0005...0.02, step: 0.0005).frame(width: 140); Text(String(format: "%.3f%%", viewModel.scalpingConfig.minVolatilityATR)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 65, alignment: .trailing) } }
                                    settingsRow("Volume Ratio") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.minVolumeRatio, in: 0.0...3.0, step: 0.1).frame(width: 140); Text(String(format: "%.1fx", viewModel.scalpingConfig.minVolumeRatio)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 55, alignment: .trailing) } }
                                    settingsRow("Broker Suffix") { HStack(spacing: 10) { TextField("e.g. m", text: $viewModel.scalpingConfig.brokerSuffix).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 80).font(.system(size: 12, weight: .bold, design: .monospaced)); Spacer() } }
                                    settingsRow("Cooldown (seconds)") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.cooldownSeconds, in: 30...600, step: 15).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.cooldownSeconds))s").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 50, alignment: .trailing) } }
                                    settingsRow("Trend Confluence") { HStack(spacing: 10) { Slider(value: $viewModel.mandatoryConfluenceLevel, in: 0...3, step: 1).frame(width: 120); let levelText = ["None","H4","H4+D1","Elite"][Int(viewModel.mandatoryConfluenceLevel)]; Text(levelText).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 60, alignment: .trailing) } }
                                    settingsRow("Strategy Pillars") { HStack(spacing: 10) { Slider(value: Binding(get: { Double(viewModel.scalpingConfig.minConfluencePillars) }, set: { viewModel.scalpingConfig.minConfluencePillars = $0 }), in: 1...7, step: 1).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.minConfluencePillars))/7").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 45, alignment: .trailing) } }
                                }.padding(16)
                            }
                        }
                        VStack(spacing: 20) {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    sectionHeader("ELITE PRECISION V10.0", icon: "target", color: .accentCyan)
                                    Divider().background(Color.borderSubtle)
                                    settingsRow("Order Flow Filter") { Toggle("", isOn: $viewModel.scalpingConfig.enableOrderFlowFilter).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).labelsHidden() }
                                    settingsRow("Delta Threshold") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.orderFlowThreshold, in: 10...500, step: 5).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.orderFlowThreshold))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 50, alignment: .trailing) } }
                                    settingsRow("Smart Pullback") { Toggle("", isOn: $viewModel.scalpingConfig.enablePullbackEntry).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).labelsHidden() }
                                    if viewModel.scalpingConfig.enablePullbackEntry { settingsRow("Pullback EMA") { HStack(spacing: 12) { Text("\(Int(viewModel.scalpingConfig.pullbackEMAPeriod))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.scalpingConfig.pullbackEMAPeriod, in: 5...100).labelsHidden() } } }
                                    settingsRow("ROC Period") { HStack(spacing: 12) { Text("\(Int(viewModel.scalpingConfig.rocPeriod))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.scalpingConfig.rocPeriod, in: 1...20).labelsHidden() } }
                                    settingsRow("ML Trend Filter") { Toggle("", isOn: $viewModel.scalpingConfig.enableMLTrendFilter).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).labelsHidden() }
                                    if viewModel.scalpingConfig.enableMLTrendFilter { settingsRow("ML Threshold") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.mlConfidenceThreshold, in: 0.5...0.95, step: 0.05).frame(width: 140); Text(String(format: "%.0f%%", viewModel.scalpingConfig.mlConfidenceThreshold * 100)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 50, alignment: .trailing) } } }
                                    settingsRow("Risk/Reward Check") { Toggle("", isOn: $viewModel.scalpingConfig.enableRRCheck).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).labelsHidden() }
                                    if viewModel.scalpingConfig.enableRRCheck { settingsRow("Min R/R Ratio") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.minRRRatio, in: 0.5...5.0, step: 0.1).frame(width: 140); Text(String(format: "%.1f", viewModel.scalpingConfig.minRRRatio)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 50, alignment: .trailing) } } }
                                    settingsRow("Fixed Stop Loss (Pips)") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.fixedSLPips, in: 5...100, step: 1).frame(width: 140); Text("\(Int(viewModel.scalpingConfig.fixedSLPips))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 50, alignment: .trailing) } }
                                    settingsRow("Volatility Scale Min") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.volatilityMultiplierMin, in: 0.1...1.0, step: 0.1).frame(width: 140); Text(String(format: "%.1fx", viewModel.scalpingConfig.volatilityMultiplierMin)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 50, alignment: .trailing) } }
                                    Divider().background(Color.borderSubtle)
                                    sectionHeader("PARTIAL TP (50/30/20)", icon: "chart.pie.fill", color: .accentGold)
                                    settingsRow("Level 1 Pips") { HStack(spacing: 12) { Text("\(Int(viewModel.scalpingConfig.partialTP1_Pips))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.scalpingConfig.partialTP1_Pips, in: 5...50).labelsHidden() } }
                                    settingsRow("Level 2 Pips") { HStack(spacing: 12) { Text("\(Int(viewModel.scalpingConfig.partialTP2_Pips))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.scalpingConfig.partialTP2_Pips, in: 10...100).labelsHidden() } }
                                    settingsRow("Level 3 Pips") { HStack(spacing: 12) { Text("\(Int(viewModel.scalpingConfig.partialTP3_Pips))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 30, alignment: .trailing); Stepper("", value: $viewModel.scalpingConfig.partialTP3_Pips, in: 15...150).labelsHidden() } }
                                    Divider().background(Color.borderSubtle)
                                    sectionHeader("STRATEGY WEIGHTS", icon: "scalemass", color: .accentCyan)
                                    Group { settingsRow("HTF Alignment") { weightStepper($viewModel.scalpingConfig.weightHTFAlignment) }; settingsRow("Momentum Exhaustion") { weightStepper($viewModel.scalpingConfig.weightMomentumExhaustion) }; settingsRow("Volume Surge") { weightStepper($viewModel.scalpingConfig.weightVolumeSurge) }; settingsRow("EMA Stack") { weightStepper($viewModel.scalpingConfig.weightEMAStack) }; settingsRow("Bollinger Reject") { weightStepper($viewModel.scalpingConfig.weightBollingerRejection) }; settingsRow("CCI Cycle") { weightStepper($viewModel.scalpingConfig.weightCCICycle) }; settingsRow("SAR Trend") { weightStepper($viewModel.scalpingConfig.weightSARTrend) }; settingsRow("Momentum Surge") { weightStepper($viewModel.scalpingConfig.weightMomentumSurge) }; settingsRow("Order Flow") { weightStepper($viewModel.scalpingConfig.weightOrderFlow) }; settingsRow("ML Confirmation") { weightStepper($viewModel.scalpingConfig.weightMLConfirmed) } }
                                }.padding(16)
                            }
                        }
                        VStack(spacing: 20) {
                            GlassCard(borderColor: viewModel.mt5Connected ? Color.accentCyan.opacity(0.4) : Color.borderSubtle) {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack { sectionHeader("MT5 CONNECTION", icon: "chart.bar.fill", color: .accentCyan); Spacer(); HStack(spacing: 5) { PulsingDot(color: viewModel.mt5Connected ? .accentGreen : .accentRed); Text(viewModel.mt5Connected ? "MT5 READY" : "MT5 OFFLINE").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(viewModel.mt5Connected ? .accentGreen : .accentRed).tracking(1) }.padding(.horizontal, 10).padding(.vertical, 5).background((viewModel.mt5Connected ? Color.accentGreen : Color.accentRed).opacity(0.1)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder((viewModel.mt5Connected ? Color.accentGreen : Color.accentRed).opacity(0.3), lineWidth: 1)) }
                                    Divider().background(Color.borderSubtle)
                                    settingsRow("Bridge URL") { TextField("http://localhost:8890", text: $viewModel.mt5BridgeURL).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 220) }
                                    settingsRow("Auth Token") { SecureField("Bearer Token", text: $viewModel.mt5AuthToken).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 220) }
                                    settingsRow("MT5 Login") { TextField("Account Number", text: $viewModel.mt5Login).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 220) }
                                    settingsRow("MT5 Password") { SecureField("Password", text: $viewModel.mt5Password).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 220) }
                                    settingsRow("MT5 Server") { TextField("Server Name", text: $viewModel.mt5Server).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 220) }
                                    settingsRow("Magic Number") { TextField("888888", value: $viewModel.mt5MagicNumber, format: .number).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 100) }
                                    HStack(spacing: 10) {
                                        Button(action: { Task { await viewModel.connectToMT5() } }) { HStack(spacing: 6) { Image(systemName: "bolt.fill"); Text(viewModel.mt5Connected ? "RECHECK MT5" : "CONNECT MT5") }.font(.system(size: 11, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.accentCyan).foregroundColor(.bgPrimary).cornerRadius(7) }.buttonStyle(.plain).disabled(viewModel.isConnecting)
                                        Button(action: { Task { await viewModel.disconnectFromMT5() } }) { HStack(spacing: 6) { Image(systemName: "bolt.slash.fill"); Text("DISCONNECT") }.font(.system(size: 11, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).padding(.vertical, 10).background(viewModel.mt5Connected ? Color.accentRed.opacity(0.18) : Color.bgSecondary).foregroundColor(viewModel.mt5Connected ? .accentRed : .textMuted).cornerRadius(7) }.buttonStyle(.plain).disabled(viewModel.isConnecting || !viewModel.mt5Connected)
                                    }
                                }.padding(16)
                            }
                            V22TrailingActivationSettingsCard(controller: v22TrailingController)
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    sectionHeader("ACTIVE TRADING PAIRS", icon: "chart.line.uptrend.xyaxis", color: .accentCyan); Divider().background(Color.borderSubtle)
                                    let majorPairs = TradingPair.allCases.filter { !$0.isExotic }.map { $0.rawValue }.sorted(); let exoticPairs = TradingPair.allCases.filter { $0.isExotic }.map { $0.rawValue }.sorted()
                                    ScrollView { VStack(alignment: .leading, spacing: 16) {
                                        if !majorPairs.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) { Text("MAJOR PAIRS").font(.system(size: 10, weight: .bold)).foregroundColor(.accentGold); LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) { ForEach(majorPairs, id: \.self) { symbol in pairToggle(symbol: symbol) } } }
                                        }
                                        if !exoticPairs.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) { Text("EXOTIC PAIRS").font(.system(size: 10, weight: .bold)).foregroundColor(.accentPurple); LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) { ForEach(exoticPairs, id: \.self) { symbol in pairToggle(symbol: symbol) } } }
                                        }
                                    }.frame(maxHeight: 250)
                                    HStack { Button("Select All") { viewModel.activeSymbols = Set(viewModel.availableSymbols) }.font(.caption).foregroundColor(.accentCyan).buttonStyle(.plain); Text("|").foregroundColor(.textMuted); Button("Clear All") { viewModel.activeSymbols.removeAll() }.font(.caption).foregroundColor(.accentRed).buttonStyle(.plain); Spacer(); Text("\(viewModel.activeSymbols.count) active").font(.caption2).foregroundColor(.textMuted) }
                                }.padding(16)
                            }
                            GlassCard { VStack(alignment: .leading, spacing: 14) { sectionHeader("NEWS FILTER", icon: "globe.americas.fill", color: .accentGold); Divider().background(Color.borderSubtle); Toggle("Enable News Protection", isOn: $viewModel.scalpingConfig.enableNewsFilter).toggleStyle(SwitchToggleStyle(tint: .accentGold)).labelsHidden(); settingsRow("Pause Before High (min)") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.pauseBeforeHighImpactMinutes, in: 0...120, step: 15).frame(width: 120); Text("\(Int(viewModel.scalpingConfig.pauseBeforeHighImpactMinutes))m").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 45, alignment: .trailing) } }; settingsRow("Pause Before Medium (min)") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.pauseBeforeMediumImpactMinutes, in: 0...60, step: 5).frame(width: 120); Text("\(Int(viewModel.scalpingConfig.pauseBeforeMediumImpactMinutes))m").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 45, alignment: .trailing) } }; Toggle("Auto-Raise Spread Tolerance", isOn: $viewModel.scalpingConfig.autoRaiseSpreadDuringNews).font(.caption).foregroundColor(.textSecondary); if viewModel.scalpingConfig.autoRaiseSpreadDuringNews { settingsRow("News Spread Mult") { HStack(spacing: 10) { Slider(value: $viewModel.scalpingConfig.newsSpreadMultiplier, in: 1.0...10.0, step: 0.5).frame(width: 120); Text("\(String(format: "%.1f", viewModel.scalpingConfig.newsSpreadMultiplier))x").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 45, alignment: .trailing) } } } }.padding(16) }
                            GlassCard { VStack(alignment: .leading, spacing: 16) { sectionHeader("NOTIFICATIONS & SYSTEM", icon: "bell.badge.fill", color: .accentCyan); Divider().background(Color.borderSubtle); Toggle("Signal Alerts", isOn: $viewModel.notifyOnSignal).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).foregroundColor(.textSecondary); Toggle("Trade Executions", isOn: $viewModel.notifyOnTrade).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).foregroundColor(.textSecondary); Toggle("Trade Closures", isOn: $viewModel.notifyOnClose).toggleStyle(SwitchToggleStyle(tint: .accentCyan)).foregroundColor(.textSecondary); Divider().background(Color.borderSubtle); Button(action: { NotificationManager.shared.requestAuthorization(); Task { @MainActor in let content = UNMutableNotificationContent(); content.title = "Stellas System Check"; content.body = "Notification pipe is now active and synced."; content.sound = .default; let request = UNNotificationRequest(identifier: "test_mac", content: content, trigger: nil); try? await UNUserNotificationCenter.current().add(request) } }) { HStack { Image(systemName: "exclamationmark.shield.fill"); Text("FORCE ENABLE NOTIFICATIONS") }.font(.system(size: 11, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.accentCyan.opacity(0.1)).foregroundColor(.accentCyan).cornerRadius(7).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentCyan.opacity(0.3), lineWidth: 1)) }.buttonStyle(.plain) }.padding(16) }
                        }
                    }.padding(24)
                }
            }
        }
        #endif
    }

    @ViewBuilder private func weightStepper(_ binding: Binding<Double>) -> some View { HStack(spacing: 12) { Text("\(Int(binding.wrappedValue))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.accentCyan).frame(width: 30, alignment: .trailing); Stepper("", value: binding, in: 0...100).labelsHidden() } }

    private func saveAllSettings() {
        ScalpingConfig.shared.confidenceThreshold = viewModel.scalpingConfig.confidenceThreshold
        ScalpingConfig.shared.spreadTolerance = viewModel.scalpingConfig.spreadTolerance
        ScalpingConfig.shared.minVolatilityATR = viewModel.scalpingConfig.minVolatilityATR
        ScalpingConfig.shared.minVolumeRatio = viewModel.scalpingConfig.minVolumeRatio
        ScalpingConfig.shared.cooldownSeconds = viewModel.scalpingConfig.cooldownSeconds
        ScalpingConfig.shared.minConfluencePillars = viewModel.scalpingConfig.minConfluencePillars
        ScalpingConfig.shared.brokerSuffix = viewModel.scalpingConfig.brokerSuffix
        ScalpingConfig.shared.enableHourlyLimit = viewModel.enableHourlyLimit
        ScalpingConfig.shared.maxDailyTrades = viewModel.dailyTradeLimit
        ScalpingConfig.shared.maxHourlyTrades = Int(viewModel.maxHourlyTrades)
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
        ScalpingConfig.shared.partialTP1_Pips = viewModel.scalpingConfig.partialTP1_Pips
        ScalpingConfig.shared.partialTP2_Pips = viewModel.scalpingConfig.partialTP2_Pips
        ScalpingConfig.shared.partialTP3_Pips = viewModel.scalpingConfig.partialTP3_Pips
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

    @ViewBuilder func pairToggle(symbol: String) -> some View {
        let isActive = viewModel.activeSymbols.contains(symbol)
        Button(action: { if isActive { viewModel.activeSymbols.remove(symbol) } else { viewModel.activeSymbols.insert(symbol) } }) {
            HStack { Image(systemName: isActive ? "checkmark.circle.fill" : "circle").foregroundColor(isActive ? .accentGreen : .textMuted); Text(symbol).font(.system(size: 10, design: .monospaced)).foregroundColor(isActive ? .textPrimary : .textSecondary) }.padding(6).frame(maxWidth: .infinity, alignment: .leading).background(isActive ? Color.accentGreen.opacity(0.1) : Color.bgCardHover).cornerRadius(6)
        }.buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View { HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(color); Text(title).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary).tracking(1) } }
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View { HStack { Text(label).font(.system(size: 12)).foregroundColor(.textSecondary).lineLimit(1).minimumScaleFactor(0.8); Spacer(); content() } }
}
