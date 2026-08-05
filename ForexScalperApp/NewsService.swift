import Foundation
import Combine

@MainActor
class NewsService: ObservableObject {
    static let shared = NewsService()
    
    @Published private(set) var upcomingEvents: [NewsEvent] = []
    @Published private(set) var isFetching = false
    private var lastFetch: Date?
    private var broadcastedEventIds = Set<String>()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
    
    private init() {
        Task {
            await fetchNews()
        }
        
        // Refresh every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await NewsService.shared.fetchNews() }
        }
    }
    
    func fetchNews() async {
        guard !isFetching else { return }
        
        isFetching = true
        defer { isFetching = false }
        
        godLog("🌍 NewsService: Fetching economic calendar...", level: .diagnostic)
        
        let urlString = "https://nfs.forexfactory.com/ffcal_week_this.xml"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await session.data(from: url)
            let events = parseForexFactoryXML(data)
            
            if !events.isEmpty {
                self.upcomingEvents = events.sorted { $0.time < $1.time }
                self.lastFetch = Date()
                godLog("✅ NewsService: Loaded \(events.count) economic events", level: .success)
                
                // Generate insights for upcoming high impact news
                generateNewsBroadcasts()
                return
            }
        } catch {
            godLog("❌ NewsService: Failed to fetch news: \(error.localizedDescription)", level: .error)
        }
        
        // FALLBACK: Use a hardcoded calendar based on standard market times
        godLog("⚠️ NewsService: Using fallback institutional calendar", level: .warning)
        self.upcomingEvents = generateFallbackEvents()
        generateNewsBroadcasts()
    }
    
    private func generateNewsBroadcasts() {
        let now = Date()
        let highImpactEvents = upcomingEvents.filter { $0.impact == .high && $0.time > now && $0.time < now.addingTimeInterval(3600 * 24) }
        
        for event in highImpactEvents {
            let eventKey = "\(event.title)_\(event.time.timeIntervalSince1970)"
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
            
            godLog("📡 NEWS BROADCAST: \(event.title) (\(event.currency)) - Sentiment: \(analysis.sentiment.displayName)", level: .info)
        }
    }
    
    private func analyzeEvent(_ event: NewsEvent) -> (summary: String, sentiment: SignalType, pairs: [String]) {
        let title = event.title.lowercased()
        let curr = event.currency.uppercased()
        
        var summary = "Institutional volatility expected for \(curr). "
        var sentiment: SignalType = .none
        var pairs: [String] = []
        
        // Logic for common events
        if title.contains("interest rate") || title.contains("cpi") || title.contains("inflation") {
            summary += "Central bank focus. Tightening expected to be Bullish for \(curr)."
            sentiment = .buy
        } else if title.contains("employment") || title.contains("nfp") || title.contains("jobless") {
            summary += "Labor market strength is Bullish for \(curr) yields."
            sentiment = .buy
        } else if title.contains("gdp") {
            summary += "Growth data usually drives direct currency demand."
            sentiment = .buy
        } else {
            summary += "High volatility anticipated. Monitor price action for breakouts."
        }
        
        // Affected pairs
        let allPairs = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY"]
        pairs = allPairs.filter { $0.contains(curr) }
        
        return (summary, sentiment, pairs)
    }
    
    private func generateFallbackEvents() -> [NewsEvent] {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        
        var events: [NewsEvent] = []
        
        // Standard high-impact windows (Monday-Friday)
        if weekday >= 2 && weekday <= 6 {
            let currencies = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD"]
            let windows = [
                (hour: 0, min: 30, impact: NewsImpact.medium, name: "Asian Session Open"),
                (hour: 8, min: 0, impact: NewsImpact.high, name: "London Session Open"),
                (hour: 13, min: 30, impact: NewsImpact.high, name: "US Pre-Market Data"),
                (hour: 15, min: 0, impact: NewsImpact.high, name: "US Open Volatility"),
                (hour: 19, min: 0, impact: NewsImpact.medium, name: "Late US Session")
            ]
            
            for window in windows {
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = window.hour
                components.minute = window.min
                
                if let eventTime = calendar.date(from: components) {
                    for curr in currencies {
                        events.append(NewsEvent(
                            title: window.name,
                            currency: curr,
                            impact: window.impact,
                            time: eventTime,
                            actual: nil, forecast: nil, previous: nil
                        ))
                    }
                }
            }
        }
        
        return events
    }
    
    private func parseForexFactoryXML(_ data: Data) -> [NewsEvent] {
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
        
        var events: [NewsEvent] = []
        let itemPattern = "<event>(.*?)</event>"
        
        do {
            let regex = try NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM-dd-yyyy HH:mm"
            dateFormatter.timeZone = TimeZone(identifier: "EST") // Forex Factory is usually EST
            
            for match in matches {
                let range = Range(match.range(at: 1), in: xmlString)!
                let content = String(xmlString[range])
                
                let title = extract(pattern: "<title>(.*?)</title>", from: content)
                let currency = extract(pattern: "<country>(.*?)</currency>", from: content)
                let dateStr = extract(pattern: "<date>(.*?)</date>", from: content)
                let timeStr = extract(pattern: "<time>(.*?)</time>", from: content)
                let impactStr = extract(pattern: "<impact>(.*?)</impact>", from: content)
                
                if let time = dateFormatter.date(from: "\(dateStr) \(timeStr)") {
                    let impact: NewsImpact
                    switch impactStr.lowercased() {
                    case "high": impact = .high
                    case "medium": impact = .medium
                    default: impact = .none
                    }
                    
                    events.append(NewsEvent(
                        title: title,
                        currency: currency,
                        impact: impact,
                        time: time,
                        actual: nil, forecast: nil, previous: nil
                    ))
                }
            }
        } catch {
            print("❌ XML Parse Error: \(error)")
        }
        
        return events
    }
    
    private func extract(pattern: String, from: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return "" }
        if let match = regex.firstMatch(in: from, options: [], range: NSRange(from.startIndex..., in: from)) {
            let range = Range(match.range(at: 1), in: from)!
            return String(from[range])
        }
        return ""
    }
    
    // MARK: - Analysis Methods
    
    func getImpactForSymbol(_ symbol: String, timeframeMinutes: Int) -> (impact: NewsImpact, event: String?) {
        let now = Date()
        let windowEnd = now.addingTimeInterval(TimeInterval(timeframeMinutes * 60))
        
        // Extract relevant currencies for this symbol (e.g., "EURUSD" -> ["EUR", "USD"])
        let base = String(symbol.prefix(3))
        let quote = String(symbol.suffix(3))
        
        let relevantEvents = upcomingEvents.filter { event in
            (event.currency == base || event.currency == quote) &&
            event.time >= now && event.time <= windowEnd
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
