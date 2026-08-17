import SwiftUI

/// Settings UI for the runner-continuation / anti-exhaustion gate.
/// Values are bound directly to ScalpingConfig, which persists them to scalping_config.json.
struct RunnerContinuationSettingsView: View {
    @ObservedObject private var config = ScalpingConfig.shared

    var body: some View {
        #if os(iOS)
        Form {
            runnerSection
        }
        .navigationTitle("Runner Continuation")
        #else
        ScrollView {
            runnerSection
                .padding(16)
        }
        #endif
    }

    @ViewBuilder
    private var runnerSection: some View {
        Section {
            Toggle("Enable Runner Continuation", isOn: $config.enableRunnerContinuation)

            Stepper("Candle Lookback: \(config.runnerCandleLookback)", value: $config.runnerCandleLookback, in: 2...8)
            Stepper("Minimum Aligned: \(config.runnerMinimumAlignedCandles)", value: $config.runnerMinimumAlignedCandles, in: 2...8)

            Toggle("Require Latest Candle Alignment", isOn: $config.runnerRequireLatestCandleAlignment)
            Toggle("Require Progressive Closes", isOn: $config.runnerRequireProgressiveCloses)

            HStack {
                Text("Minimum Body / Range")
                Spacer()
                Text(String(format: "%.0f%%", config.runnerMinimumBodyToRangeRatio * 100))
            }
            Slider(value: $config.runnerMinimumBodyToRangeRatio, in: 0.05...0.95, step: 0.05)

            HStack {
                Text("Maximum Opposing Wick / Body")
                Spacer()
                Text(String(format: "%.2fx", config.runnerMaximumOpposingWickToBodyRatio))
            }
            Slider(value: $config.runnerMaximumOpposingWickToBodyRatio, in: 0.0...3.0, step: 0.05)

            HStack {
                Text("Minimum Momentum Acceleration")
                Spacer()
                Text(String(format: "%.2fx", config.runnerMinimumAccelerationRatio))
            }
            Slider(value: $config.runnerMinimumAccelerationRatio, in: 0.50...3.0, step: 0.05)

            HStack {
                Text("Maximum Breakout Extension")
                Spacer()
                Text(String(format: "%.2f ATR", config.runnerMaximumBreakoutExtensionATR))
            }
            Slider(value: $config.runnerMaximumBreakoutExtensionATR, in: 0.10...3.0, step: 0.05)

            HStack {
                Text("Anti-Runner Range Multiplier")
                Spacer()
                Text(String(format: "%.2fx", config.runnerAntiRunnerRangeMultiplier))
            }
            Slider(value: $config.runnerAntiRunnerRangeMultiplier, in: 1.0...4.0, step: 0.05)

            HStack {
                Text("Anti-Runner Wick Ratio")
                Spacer()
                Text(String(format: "%.2fx", config.runnerAntiRunnerWickRatio))
            }
            Slider(value: $config.runnerAntiRunnerWickRatio, in: 0.25...4.0, step: 0.05)

            Stepper("ATR Lookback: \(config.runnerATRLookback)", value: $config.runnerATRLookback, in: 5...100)
        } header: {
            Text("RUNNER CONTINUATION / ANTI-EXHAUSTION")
        } footer: {
            Text("The gate requires directional candle confirmation, accelerating momentum, clean candle bodies/wicks, controlled breakout extension, and no detected exhaustion pattern. Settings are persisted with the rest of the scalping configuration.")
        }
        .onChange(of: config.enableRunnerContinuation) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerCandleLookback) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerMinimumAlignedCandles) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerRequireLatestCandleAlignment) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerRequireProgressiveCloses) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerMinimumBodyToRangeRatio) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerMaximumOpposingWickToBodyRatio) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerMinimumAccelerationRatio) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerMaximumBreakoutExtensionATR) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerAntiRunnerRangeMultiplier) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerAntiRunnerWickRatio) { _, _ in config.saveConfig() }
        .onChange(of: config.runnerATRLookback) { _, _ in config.saveConfig() }
    }
}
