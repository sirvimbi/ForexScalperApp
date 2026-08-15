import Foundation

/// Produces one daily macro watchlist from the calendar already maintained by NewsService.
/// Forecast/previous values are treated as directional context, never as guaranteed outcomes.
@MainActor
final class DailyNewsIntelligence {
    static let shared = DailyNewsIntelligence()
    private var lastPublishedDay: Date?

    private init() {
        Task { @MainActor in
            await self.publishIfNeeded()
        }
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in await DailyNewsIntelligence.shared.publishIfNeeded() }
        }
    }

    func publishIfNeeded(force: Bool = false) async {
        let calendar = Calendar.current
        let now = Date()
        if !force, let lastPublishedDay, calendar.isDate(lastPublishedDay, inSameDayAs: now) { return }
        let events = NewsService.shared.upcomingEvents.filter {
            calendar.isDate($0.time, inSameDayAs: now) && $0.time >= now.addingTimeInterval(-3600)
        }
        guard !events.isEmpty else {
            godLog("📰 DAILY NEWS INTELLIGENCE | no calendar events available today", level: .info)
            return
        }

        var currencyScores: [String: Double] = [:]
        var drivers: [String: [String]] = [:]
        for event in events {
            currencyScores[event.currency, default: 0] += eventScore(event)
            drivers[event.currency, default: []].append(event.title)
        }

        let ranked = currencyScores.sorted { abs($0.value) > abs($1.value) }
        let watchCurrencies = ranked.prefix(6)
        let watchPairs = makePairBiases(watchCurrencies.map { ($0.key, $0.value) })
        let top = watchPairs.prefix(6).map { pair in
            "\(pair.symbol)=\(pair.bias) (\(String(format: "%+.2f", pair.score)))"
        }.joined(separator: " | ")
        let driverText = watchCurrencies.prefix(4).map { currency, _ in
            "\(currency): \(Array(Set(drivers[currency] ?? [])).prefix(2).joined(separator: ", "))"
        }.joined(separator: " • ")

        let insight = GodModeInsight(
            id: UUID(), type: .newsBroadcast, symbol: "MACRO",
            title: "DAILY NEWS WATCHLIST",
            message: "Pair bias: \(top). Drivers: \(driverText). This is a scenario bias derived from today's calendar, not a trade guarantee.",
            sentiment: .none, affectedPairs: watchPairs.map(\.symbol), timestamp: now
        )
        NotificationCenter.default.post(name: .newGodModeInsight, object: insight)
        lastPublishedDay = now
        godLog("📰 DAILY NEWS INTELLIGENCE | published | watch=\(top)", level: .success)
    }

    private func eventScore(_ event: NewsEvent) -> Double {
        let impact: Double = event.impact == .high ? 3.0 : event.impact == .medium ? 1.5 : 0.5
        let title = event.title.lowercased()
        guard let f = numeric(event.forecast), let p = numeric(event.previous) else {
            if title.contains("rate") || title.contains("cpi") || title.contains("inflation") || title.contains("employment") || title.contains("nfp") { return impact * 0.15 }
            return 0
        }
        var direction = f - p
        if title.contains("unemployment") || title.contains("jobless") { direction = -direction }
        return max(-4, min(4, direction)) * impact
    }

    private func numeric(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: ""))
    }

    private func makePairBiases(_ currencies: [(String, Double)]) -> [(symbol: String, score: Double, bias: String)] {
        let pairs = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP"]
        let scores = Dictionary(uniqueKeysWithValues: currencies)
        return pairs.map { pair in
            let base = String(pair.prefix(3)), quote = String(pair.suffix(3))
            let score = (scores[base] ?? 0) - (scores[quote] ?? 0)
            let bias = score > 1.0 ? "BULLISH" : score < -1.0 ? "BEARISH" : "NEUTRAL"
            return (pair, score, bias)
        }.sorted { abs($0.score) > abs($1.score) }
    }
}
