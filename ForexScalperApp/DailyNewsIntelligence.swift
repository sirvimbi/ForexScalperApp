import Foundation

@MainActor
final class DailyNewsIntelligence {
    static let shared = DailyNewsIntelligence()
    private var lastPublishedDay: Date?
    private init() {
        Task { @MainActor in await self.publishIfNeeded() }
        let interval = max(5, DailyNewsConfiguration.load().refreshIntervalMinutes) * 60
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in Task { @MainActor in await DailyNewsIntelligence.shared.publishIfNeeded() } }
    }
    func publishIfNeeded(force: Bool = false) async {
        let settings = DailyNewsConfiguration.load(), calendar = Calendar.current, now = Date()
        if !force, let lastPublishedDay, calendar.isDate(lastPublishedDay, inSameDayAs: now) { return }
        let events = NewsService.shared.upcomingEvents.filter { calendar.isDate($0.time, inSameDayAs: now) && $0.time >= now.addingTimeInterval(-settings.eventLookbackHours * 3600) }
        guard !events.isEmpty else { godLog("📰 DAILY NEWS INTELLIGENCE | no calendar events available today", level: .info); return }
        var currencyScores: [String: Double] = [:], drivers: [String: [String]] = [:]
        for event in events { currencyScores[event.currency, default: 0] += eventScore(event, settings: settings); drivers[event.currency, default: []].append(event.title) }
        let watchCurrencies = currencyScores.sorted { abs($0.value) > abs($1.value) }.prefix(settings.watchCurrencyCount), watchPairs = makePairBiases(watchCurrencies.map { ($0.key, $0.value) }, settings: settings)
        let top = watchPairs.prefix(settings.watchCurrencyCount).map { "\($0.symbol)=\($0.bias) (\(String(format: "%+.2f", $0.score)))" }.joined(separator: " | ")
        let driverText = watchCurrencies.prefix(min(settings.watchCurrencyCount, 4)).map { "\($0.key): \(Array(Set(drivers[$0.key] ?? [])).prefix(2).joined(separator: ", "))" }.joined(separator: " • ")
        let insight = GodModeInsight(id: UUID(), type: .newsBroadcast, symbol: "MACRO", title: "DAILY NEWS WATCHLIST", message: "Pair bias: \(top). Drivers: \(driverText). This is a scenario bias derived from today's calendar, not a trade guarantee.", sentiment: .none, affectedPairs: watchPairs.map(\.symbol), timestamp: now)
        NotificationCenter.default.post(name: .newGodModeInsight, object: insight); lastPublishedDay = now; godLog("📰 DAILY NEWS INTELLIGENCE | published | watch=\(top)", level: .success)
    }
    private func eventScore(_ event: NewsEvent, settings: DailyNewsConfiguration) -> Double {
        let impact = event.impact == .high ? settings.highImpactWeight : event.impact == .medium ? settings.mediumImpactWeight : settings.lowImpactWeight, title = event.title.lowercased()
        guard let f = numeric(event.forecast), let p = numeric(event.previous) else { return (title.contains("rate") || title.contains("cpi") || title.contains("inflation") || title.contains("employment") || title.contains("nfp")) ? impact * settings.macroKeywordFallbackMultiplier : 0 }
        var direction = f - p; if title.contains("unemployment") || title.contains("jobless") { direction = -direction }
        return max(-settings.directionalScoreClamp, min(settings.directionalScoreClamp, direction)) * impact
    }
    private func numeric(_ value: String?) -> Double? { guard let value else { return nil }; return Double(value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")) }
    private func numeric(_ value: Double?) -> Double? { value }
    private func numeric(_ value: Int?) -> Double? { value.map(Double.init) }
    private func makePairBiases(_ currencies: [(String, Double)], settings: DailyNewsConfiguration) -> [(symbol: String, score: Double, bias: String)] {
        let pairs = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP"], scores = Dictionary(uniqueKeysWithValues: currencies)
        return pairs.map { pair in let base = String(pair.prefix(3)), quote = String(pair.suffix(3)), score = (scores[base] ?? 0) - (scores[quote] ?? 0); return (pair, score, score > settings.pairBiasThreshold ? "BULLISH" : score < -settings.pairBiasThreshold ? "BEARISH" : "NEUTRAL") }.sorted { abs($0.score) > abs($1.score) }
    }
}
