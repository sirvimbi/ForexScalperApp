// NewsService.swift - Autonomous Economic Calendar Integration
import Foundation
import Combine

class NewsService: ObservableObject {
    static let shared = NewsService()
    
    @Published var upcomingEvents: [NewsEvent] = []
    @Published var isFetching = false
    @Published var lastFetch: Date?
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        return URLSession(configuration: config)
    }()
    
    private init() {
        // Initial fetch
        Task { await fetchNews() }
        
        // Auto-refresh every 30 minutes
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task { await self.fetchNews() }
        }
    }
    
    func fetchNews() async {
        guard !isFetching else { return }
        
        await MainActor.run { isFetching = true }
        defer { DispatchQueue.main.async { self.isFetching = false } }
        
        print("🌍 NewsService: Fetching economic calendar...")
        
        // Use a public economic calendar feed (This is a common public JSON feed for demo/dev purposes)
        // In production, you might want to use a more robust paid API or a reliable scraper
        let urlString = "https://nfs.forexfactory.com/ffcal_week_this.xml"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await session.data(from: url)
            let events = parseForexFactoryXML(data)
            
            await MainActor.run {
                self.upcomingEvents = events.sorted { $0.time < $1.time }
                self.lastFetch = Date()
                print("✅ NewsService: Loaded \(events.count) events")
            }
        } catch {
            print("❌ NewsService: Failed to fetch news: \(error)")
        }
    }
    
    private func parseForexFactoryXML(_ data: Data) -> [NewsEvent] {
        // Since Swift doesn't have a built-in XML to Object mapper without complex boilerplate, 
        // and we want to keep it lightweight, we'll use a simple XML Parser approach 
        // OR a regex-based approach for this specific structure.
        
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        var events: [NewsEvent] = []
        
        // Regex patterns for FF XML fields
        let eventPattern = "<event>(.*?)</event>"
        let titlePattern = "<title>(.*?)</title>"
        let countryPattern = "<country>(.*?)</country>"
        let datePattern = "<date><!\\[CDATA\\[(.*?)\\]\\]></date>"
        let timePattern = "<time><!\\[CDATA\\[(.*?)\\]\\]></time>"
        let impactPattern = "<impact><!\\[CDATA\\[(.*?)\\]\\]></impact>"
        
        let eventRegex = try? NSRegularExpression(pattern: eventPattern, options: [.dotMatchesLineSeparators])
        let nsString = xmlString as NSString
        let matches = eventRegex?.matches(in: xmlString, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy h:mma" // Example: 07-23-2026 8:30am
        dateFormatter.timeZone = TimeZone(abbreviation: "EST") // FF XML is usually EST
        
        for match in matches {
            let eventContent = nsString.substring(with: match.range(at: 1))
            let contentNS = eventContent as NSString
            
            let title = extract(pattern: titlePattern, from: eventContent)
            let country = extract(pattern: countryPattern, from: eventContent)
            let dateStr = extract(pattern: datePattern, from: eventContent)
            let timeStr = extract(pattern: timePattern, from: eventContent)
            let impactStr = extract(pattern: impactPattern, from: eventContent)
            
            // Convert impact string to enum
            let impact: NewsImpact
            switch impactStr.lowercased() {
            case "high": impact = .high
            case "medium": impact = .medium
            case "low": impact = .low
            default: impact = .none
            }
            
            // Parse Date
            if let date = dateFormatter.date(from: "\(dateStr) \(timeStr)") {
                events.append(NewsEvent(
                    title: title,
                    currency: country,
                    impact: impact,
                    time: date,
                    actual: nil,
                    forecast: nil,
                    previous: nil
                ))
            }
        }
        
        return events
    }
    
    private func extract(pattern: String, from: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return "" }
        let nsString = from as NSString
        if let match = regex.firstMatch(in: from, options: [], range: NSRange(location: 0, length: nsString.length)) {
            return nsString.substring(with: match.range(at: 1))
        }
        return ""
    }
    
    // MARK: - Analysis Methods
    
    func getImpactForSymbol(_ symbol: String, timeframeMinutes: Int = 60) -> (impact: NewsImpact, event: String?) {
        let now = Date()
        let windowEnd = now.addingTimeInterval(TimeInterval(timeframeMinutes * 60))
        
        // Filter events for this symbol's currencies (e.g. EUR and USD for EURUSD)
        let base = String(symbol.prefix(3))
        let quote = String(symbol.suffix(3))
        
        let relevantEvents = upcomingEvents.filter { event in
            (event.currency == base || event.currency == quote) &&
            event.time >= now && event.time <= windowEnd
        }
        
        if let highest = relevantEvents.max(by: { a, b in
            let impacts: [NewsImpact: Int] = [.none: 0, .low: 1, .medium: 2, .high: 3]
            return (impacts[a.impact] ?? 0) < (impacts[b.impact] ?? 0)
        }) {
            return (highest.impact, highest.title)
        }
        
        return (.none, nil)
    }
}
