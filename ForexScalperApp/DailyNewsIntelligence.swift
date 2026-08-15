import Foundation

/// Produces one daily macro watchlist from the calendar already maintained by NewsService.
/// Forecast/previous values are treated as directional context, never as guaranteed outcomes.
@MainActor
final class DailyNewsIntelligence {
    static let shared = DailyNewsIntelligence()
    private var lastPublishedDay: Date?
    private init() {}

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
            let score = eventScore(event)
            currencyScores[event.currency, default: 0] += score
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
            id: UUID(),
            type: .newsBroadcast,
            symbol: "MACRO",
            title: "DAILY NEWS WATCHLIST",
            message: "Pair bias: \(top). Drivers: \(driverText). This is a scenario bias derived from today's calendar, not a trade guarantee.",
            sentiment: .none,
            affectedPairs: watchPairs.map(\.symbol),
            timestamp: now
        )
        NotificationCenter.default.post(name: .newGodModeInsight, object: insight)
        lastPublishedDay = now
        godLog("📰 DAILY NEWS INTELLIGENCE | published | watch=\(top)", level: .success)
    }

    private func eventScore(_ event: NewsEvent) -> Double {
        let impact: Double = event.impact == .high ? 3.0 : event.impact == .medium ? 1.5 : 0.5
        let title = event.title.lowercased()
        let previous = numeric(event.previous), forecast = numeric(event.forecast)
        guard let f = forecast, let p = previous else {
            if title.contains("rate") || title.contains("cpi") || title.contains("inflation") || title.contains("employment") || title.contains("nfp") {
                return impact * 0.15
            }
            return 0
        }
        let delta = f - p
        var direction = delta
        // For inflation, stronger-than-previous data is generally more hawkish;
        // for employment/growth, stronger is likewise supportive. The score is a bias,
        // not an assertion that the market must react in that direction.
        if title.contains("unemployment") || title.contains("jobless") {
            direction = -delta
        }
        return max(-4, min(4, direction)) * impact
    }

    private func numeric(_ value: String?) -> Double? {
        guard let value else { return nil }
        let cleaned = value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")
        return Double(cleaned)
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
