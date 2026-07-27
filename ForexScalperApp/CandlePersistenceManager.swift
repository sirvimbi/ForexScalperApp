import Foundation

class CandlePersistenceManager {
    static let shared = CandlePersistenceManager()
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("com.godmode.scalper/candles", isDirectory: true)
        
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    
    func saveCandles(_ candles: [Kline], for symbol: String, timeframe: String) {
        guard !candles.isEmpty else { return }
        
        let fileURL = getFileURL(symbol: symbol, timeframe: timeframe)
        
        // Load existing to merge
        let existing = loadCandles(for: symbol, timeframe: timeframe)
        
        // Merge and deduplicate by closeTime
        let existingMap = Dictionary(grouping: existing, by: { $0.closeTime }).mapValues { $0.first! }
        var mergedMap = existingMap
        
        for candle in candles {
            mergedMap[candle.closeTime] = candle
        }
        
        let merged = mergedMap.values.sorted { $0.closeTime < $1.closeTime }
        
        // Keep last 5000 candles to avoid massive files
        let final = Array(merged.suffix(5000))
        
        do {
            let data = try JSONEncoder().encode(final)
            try data.write(to: fileURL, options: .atomic)
            // godLog("💾 Persistence: Saved \(final.count) candles for \(symbol) \(timeframe)")
        } catch {
            godLog("❌ Persistence: Failed to save candles for \(symbol) \(timeframe): \(error)", level: .error)
        }
    }
    
    func loadCandles(for symbol: String, timeframe: String) -> [Kline] {
        let fileURL = getFileURL(symbol: symbol, timeframe: timeframe)
        
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Kline].self, from: data)
        } catch {
            return []
        }
    }
    
    func getLatestCandleTime(for symbol: String, timeframe: String) -> Int? {
        return loadCandles(for: symbol, timeframe: timeframe).last?.closeTime
    }
    
    private func getFileURL(symbol: String, timeframe: String) -> URL {
        let safeSymbol = symbol.replacingOccurrences(of: "/", with: "_")
        return baseDirectory.appendingPathComponent("\(safeSymbol)_\(timeframe).json")
    }
}
