import SwiftUI

/// Production settings UI for the runner-continuation / anti-exhaustion gate.
/// All values bind directly to ScalpingConfig so changes are persisted by the existing
/// SAVE ALL flow and consumed by RunnerContinuationConfiguration.
struct RunnerContinuationSettingsCard: View {
    @ObservedObject var config: ScalpingConfig

    private let gold = Color.accentGold
    private let cyan = Color.accentCyan

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("RUNNER CONTINUATION", icon: "figure.run", color: .accentGold)
                Text("Momentum continuation + anti-exhaustion confirmation. Only closed candles are evaluated.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().background(Color.borderSubtle)

                settingsRow("Enable Runner Gate") {
                    Toggle("", isOn: $config.enableRunnerContinuation)
                        .toggleStyle(SwitchToggleStyle(tint: .accentGold))
                        .labelsHidden()
                }

                settingsRow("Candle Lookback") {
                    HStack(spacing: 12) {
                        Text("\(config.runnerCandleLookback)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(gold)
                            .frame(width: 30, alignment: .trailing)
                        Stepper("", value: $config.runnerCandleLookback, in: 2...8)
                            .labelsHidden()
                    }
                    .disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Minimum Aligned Candles") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(config.runnerMinimumAlignedCandles) },
                            set: { config.runnerMinimumAlignedCandles = min(Int($0.rounded()), config.runnerCandleLookback) }
                        ), in: 2...Double(max(2, config.runnerCandleLookback)), step: 1)
                        .frame(width: 140)
                        Text("\(config.runnerMinimumAlignedCandles)/\(config.runnerCandleLookback)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(gold)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Require Latest Candle") {
                    Toggle("", isOn: $config.runnerRequireLatestCandleAlignment)
                        .toggleStyle(SwitchToggleStyle(tint: .accentGold))
                        .labelsHidden()
                        .disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Progressive Closes") {
                    Toggle("", isOn: $config.runnerRequireProgressiveCloses)
                        .toggleStyle(SwitchToggleStyle(tint: .accentGold))
                        .labelsHidden()
                        .disabled(!config.enableRunnerContinuation)
                }

                Divider().background(Color.borderSubtle)
                sectionHeader("MOMENTUM / PRICE ACTION", icon: "speedometer", color: .accentCyan)

                settingsRow("Min Body / Range") {
                    HStack(spacing: 10) {
                        Slider(value: $config.runnerMinimumBodyToRangeRatio, in: 0.10...0.90, step: 0.05).frame(width: 140)
                        Text(String(format: "%.0f%%", config.runnerMinimumBodyToRangeRatio * 100))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cyan).frame(width: 50, alignment: .trailing)
                    }.disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Max Opposing Wick / Body") {
                    HStack(spacing: 10) {
                        Slider(value: $config.runnerMaximumOpposingWickToBodyRatio, in: 0.10...2.0, step: 0.05).frame(width: 140)
                        Text(String(format: "%.2fx", config.runnerMaximumOpposingWickToBodyRatio))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cyan).frame(width: 50, alignment: .trailing)
                    }.disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Min Momentum Acceleration") {
                    HStack(spacing: 10) {
                        Slider(value: $config.runnerMinimumAccelerationRatio, in: 0.80...2.50, step: 0.05).frame(width: 140)
                        Text(String(format: "%.2fx", config.runnerMinimumAccelerationRatio))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cyan).frame(width: 50, alignment: .trailing)
                    }.disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Max Breakout Extension") {
                    HStack(spacing: 10) {
                        Slider(value: $config.runnerMaximumBreakoutExtensionATR, in: 0.10...2.50, step: 0.05).frame(width: 140)
                        Text(String(format: "%.2f ATR", config.runnerMaximumBreakoutExtensionATR))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cyan).frame(width: 65, alignment: .trailing)
                    }.disabled(!config.enableRunnerContinuation)
                }

                Divider().background(Color.borderSubtle)
                sectionHeader("ANTI-RUNNER / EXHAUSTION", icon: "exclamationmark.triangle.fill", color: .accentRed)

                settingsRow("Range Exhaustion Multiplier") {
                    HStack(spacing: 10) {
                        Slider(value: $config.runnerAntiRunnerRangeMultiplier, in: 1.0...3.0, step: 0.05).frame(width: 140)
                        Text(String(format: "%.2fx", config.runnerAntiRunnerRangeMultiplier))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentRed).frame(width: 50, alignment: .trailing)
                    }.disabled(!config.enableRunnerContinuation)
                }

                settingsRow("Exhaustion Wick Ratio") {
                    HStack(spacing: 10) {
                        Slider(value: $config.runnerAntiRunnerWickRatio, in: 0.50...3.0, step: 0.05).frame(width: 140)
                        Text(String(format: "%.2fx", config.runnerAntiRunnerWickRatio))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentRed).frame(width: 50, alignment: .trailing)
                    }.disabled(!config.enableRunnerContinuation)
                }

                settingsRow("ATR Lookback") {
                    HStack(spacing: 12) {
                        Text("\(config.runnerATRLookback)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentRed).frame(width: 30, alignment: .trailing)
                        Stepper("", value: $config.runnerATRLookback, in: 5...100)
                            .labelsHidden()
                    }.disabled(!config.enableRunnerContinuation)
                }
            }
            .padding(16)
            .opacity(config.enableRunnerContinuation ? 1.0 : 0.65)
        }
    }
}
