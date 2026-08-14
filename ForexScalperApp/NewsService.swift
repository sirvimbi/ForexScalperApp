import Foundation
import Combine

@MainActor
final class NewsService: ObservableObject {

    static let shared = NewsService()

    @Published private(set) var upcomingEvents: [NewsEvent] = []
    @Published private(set) var isFetching = false

    private var lastFetch: Date?
    private var broadcastedEventIds = Set<String>()

    private let minimumRefreshInterval: TimeInterval = 300

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // Forex Factory's current weekly XML export is served by Fair Economy.
    // The legacy nfs.forexfactory.com and cdn-nfs.faireconomy.media hosts
    // are no longer reliable and produce NSURLError -1003 on macOS.
    private let calendarURLs: [URL] = [
        URL(string: "https://nfs.faireconomy.media/ff_calendar_thisweek.xml")!
    ]

    private init() {
        Task { [weak self] in
            await self?.fetchNews()
        }

        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                await NewsService.shared.fetchNews()
            }
        }
    }

    func fetchNews(force: Bool = false) async {
        guard !isFetching else { return }

        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < minimumRefreshInterval {
            return
        }

        isFetching = true
        defer { isFetching = false }

        godLog("🌍 NewsService: Fetching economic calendar...", level: .diagnostic)

        for url in calendarURLs {
            do {
                godLog("🌐 NewsService: Trying calendar source: \(url.host ?? "unknown")", level: .diagnostic)

                var request = URLRequest(url: url)
                request.setValue("ForexScalperApp/10.6", forHTTPHeaderField: "User-Agent")
                request.setValue("application/xml,text/xml;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 12

                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    godLog("⚠️ NewsService: Calendar source returned HTTP \(httpResponse.statusCode)", level: .warning)
                    continue
                }

                guard !data.isEmpty else {
                    godLog("⚠️ NewsService: Calendar source returned an empty response", level: .warning)
                    continue
                }

                let events = parseForexFactoryXML(data)

                if !events.isEmpty {
                    upcomingEvents = events.sorted { $0.time < $1.time }
                    lastFetch = Date()
                    godLog("✅ NewsService: Loaded \(events.count) economic events", level: .success)
                    generateNewsBroadcasts()
                    return
                }

                godLog("⚠️ NewsService: Calendar response contained no parseable events", level: .warning)

            } catch let error as URLError {
                godLog("⚠️ NewsService: Calendar request failed (\(error.code.rawValue)): \(error.localizedDescription)", level: .warning)
            } catch {
                godLog("⚠️ NewsService: Calendar request failed: \(error.localizedDescription)", level: .warning)
            }
        }

        if upcomingEvents.isEmpty {
            godLog("⚠️ NewsService: Remote calendar unavailable; using fallback institutional calendar", level: .warning)
            upcomingEvents = generateFallbackEvents()
            generateNewsBroadcasts()
        }
    }

    private func generateNewsBroadcasts() {
        let now = Date()
        let next24Hours = now.addingTimeInterval(3600 * 24)

        let highImpactEvents = upcomingEvents.filter {
            $0.impact == .high && $0.time > now && $0.time < next24Hours
        }

        for event in highImpactEvents {
            let eventKey = "\(event.title)_\(event.currency)_\(event.time.timeIntervalSince1970)"
            guard !broadcastedEventIds.contains(eventKey) else { continue }

            let analysis = analyzeEvent(event)
            let insight = GodModeInsight(
                id: UUID(),
                type: .newsBroadcast,
                symbol: event.currency,
                title: event.title,
                message: analysis.summary,
                sentiment: analysis.sentiment,
                affectedPairs: analysis.pairs,
                timestamp: event.time
            )

            NotificationCenter.default.post(name: .newGodModeInsight, object: insight)
            broadcastedEventIds.insert(eventKey)

            godLog("📡 NEWS BROADCAST: \(event.title) (\(event.currency))", level: .info)
        }
    }

    private func analyzeEvent(_ event: NewsEvent) -> (summary: String, sentiment: SignalType, pairs: [String]) {
        let title = event.title.lowercased()
        let curr = event.currency.uppercased()
        var summary = "Institutional volatility expected for \(curr). "
        var sentiment: SignalType = .none

        if title.contains("interest rate") || title.contains("rate decision") || title.contains("cpi") || title.contains("inflation") {
            summary += "Hawkish expectations can support \(curr), while dovish expectations can weaken it."
            sentiment = .buy
        } else if title.contains("employment") || title.contains("nfp") || title.contains("jobless") {
            summary += "Labor-market data can materially affect currency yields."
            sentiment = .buy
        } else if title.contains("gdp") {
            summary += "Growth data can drive direct currency demand."
            sentiment = .buy
        } else {
            summary += "High volatility anticipated. Monitor price action."
        }

        let allPairs = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY"]
        let pairs = allPairs.filter { $0.contains(curr) }

        return (summary, sentiment, pairs)
    }

    private func generateFallbackEvents() -> [NewsEvent] {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        var events: [NewsEvent] = []

        guard weekday >= 2 && weekday <= 6 else { return events }

        let currencies = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD"]
        let windows: [(hour: Int, min: Int, impact: NewsImpact, name: String)] = [
            (0, 30, .medium, "Asian Session Open"),
            (8, 0, .high, "London Session Open"),
            (13, 30, .high, "US Pre-Market Data"),
            (15, 0, .high, "US Open Volatility")
        ]

        for window in windows {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = window.hour
            components.minute = window.min
            components.second = 0

            guard let eventTime = calendar.date(from: components), eventTime > now else { continue }

            for curr in currencies {
                events.append(NewsEvent(title: window.name, currency: curr, impact: window.impact, time: eventTime, actual: nil, forecast: nil, previous: nil))
            }
        }
        return events
    }

    private func parseForexFactoryXML(_ data: Data) -> [NewsEvent] {
        guard let xmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }

        var events: [NewsEvent] = []
        let itemPattern = "<event>(.*?)</event>"

        do {
            let regex = try NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators])
            let fullRange = NSRange(xmlString.startIndex..., in: xmlString)
            let matches = regex.matches(in: xmlString, options: [], range: fullRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: xmlString) else { continue }
                let content = String(xmlString[range])

                let title = cleanValue(extract(tag: "title", from: content))
                let currency = cleanValue(extract(tag: "country", from: content))
                let dateStr = cleanValue(extract(tag: "date", from: content))
                let timeStr = cleanValue(extract(tag: "time", from: content))
                let impactStr = cleanValue(extract(tag: "impact", from: content))

                if title.isEmpty || currency.isEmpty || dateStr.isEmpty || timeStr.isEmpty { continue }
                guard let eventTime = parseDate(dateStr: dateStr, timeStr: timeStr) else { continue }

                let impact: NewsImpact
                switch impactStr.lowercased() {
                case "high": impact = .high
                case "medium": impact = .medium
                default: impact = .none
                }

                events.append(NewsEvent(title: title, currency: currency.uppercased(), impact: impact, time: eventTime, actual: nil, forecast: nil, previous: nil))
            }
        } catch {
            godLog("❌ NewsService: XML Regex Error: \(error.localizedDescription)", level: .error)
        }
        return events
    }

    private func extract(tag: String, from content: String) -> String {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return "" }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: content) else { return "" }
        return String(content[valueRange])
    }

    private func cleanValue(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "<!\\[CDATA\\[", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\]\\]>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func parseDate(dateStr: String, timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        let fullStr = "\(dateStr) \(timeStr)"
        let formats = [
            "MM-dd-yyyy h:mma",
            "MM-dd-yyyy hh:mma",
            "MM-dd-yyyy HH:mm",
            "yyyy-MM-dd HH:mm"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: fullStr) {
                return date
            }
        }
        return nil
    }

    func getImpactForSymbol(_ symbol: String, timeframeMinutes: Int) -> (impact: NewsImpact, event: String?) {
        let now = Date()
        let windowEnd = now.addingTimeInterval(TimeInterval(timeframeMinutes * 60))
        let normalizedSymbol = symbol.uppercased().filter { $0.isLetter }

        guard normalizedSymbol.count >= 6 else { return (.none, nil) }

        let base = String(normalizedSymbol.prefix(3))
        let quote = String(normalizedSymbol.suffix(3))

        let relevantEvents = upcomingEvents.filter { event in
            (event.currency.uppercased() == base || event.currency.uppercased() == quote)
                && event.time >= now
                && event.time <= windowEnd
        }

        if let high = relevantEvents.first(where: { $0.impact == .high }) {
            return (.high, high.title)
        }
        if let medium = relevantEvents.first(where: { $0.impact == .medium }) {
            return (.medium, medium.title)
        }
        return (.none, nil)
    }
}
