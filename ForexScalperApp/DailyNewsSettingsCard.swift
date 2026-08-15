import SwiftUI

struct DailyNewsSettingsCard: View {
    @ObservedObject var controller: DailyNewsSettingsController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "newspaper.fill").foregroundColor(.accentGold); Text("DAILY NEWS INTELLIGENCE").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary); Spacer() }
            Text("Controls the informational daily macro watchlist. It does not become a hard trade gate.").font(.system(size: 9)).foregroundColor(.textSecondary)
            newsSlider("High impact weight", value: $controller.values.highImpactWeight, range: 0...10, step: 0.5)
            newsSlider("Medium impact weight", value: $controller.values.mediumImpactWeight, range: 0...10, step: 0.5)
            newsSlider("Low impact weight", value: $controller.values.lowImpactWeight, range: 0...5, step: 0.25)
            newsSlider("Macro keyword fallback", value: $controller.values.macroKeywordFallbackMultiplier, range: 0...1, step: 0.01)
            newsSlider("Directional score clamp", value: $controller.values.directionalScoreClamp, range: 0.5...10, step: 0.5)
            newsSlider("Pair bias threshold", value: $controller.values.pairBiasThreshold, range: 0.1...5, step: 0.1)
            newsSlider("Watch currencies", value: Binding(get: { Double(controller.values.watchCurrencyCount) }, set: { controller.values.watchCurrencyCount = Int($0.rounded()) }), range: 2...12, step: 1)
            newsSlider("Event lookback (hours)", value: $controller.values.eventLookbackHours, range: 0...12, step: 0.5)
            newsSlider("Refresh check (minutes)", value: $controller.values.refreshIntervalMinutes, range: 5...120, step: 5)
            HStack(spacing: 8) {
                Button("SAVE NEWS SETTINGS") { controller.save() }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.bgPrimary).padding(.horizontal, 10).padding(.vertical, 6).background(Color.accentGold).cornerRadius(6).buttonStyle(.plain)
                Button("RELOAD") { controller.reload() }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).padding(.horizontal, 10).padding(.vertical, 6).background(Color.accentGold.opacity(0.10)).cornerRadius(6).buttonStyle(.plain)
            }
        }.padding(.top, 4)
    }
    @ViewBuilder private func newsSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 8) { Text(label).font(.system(size: 9)).foregroundColor(.textSecondary).lineLimit(1).minimumScaleFactor(0.75); Slider(value: value, in: range, step: step); Text(String(format: "%.1f", value.wrappedValue)).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.accentGold).frame(width: 45, alignment: .trailing) }
    }
}
