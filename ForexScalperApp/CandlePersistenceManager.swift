import Foundation

actor CandlePersistenceManager {
    nonisolated static let shared = CandlePersistenceManager()

    private let fileManager = FileManager.default
    private let baseDirectory: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("com.godmode.scalper/candles", isDirectory: true)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func saveCandles(_ candles: [Kline], for symbol: String, timeframe: String) async {
        guard !candles.isEmpty else {
            godLog("⚠️ Persistence: Refusing to overwrite \(symbol) \(timeframe) with an empty candle set", level: .warning)
            return
        }

        let fileURL = getFileURL(symbol: symbol, timeframe: timeframe)
        let existing = await loadCandles(for: symbol, timeframe: timeframe)
        var mergedMap = Dictionary(grouping: existing, by: { $0.closeTime }).mapValues { $0.first! }

        for candle in candles {
            let normalized = normalizedCandle(candle)
            mergedMap[normalized.closeTime] = normalized
        }

        let merged = mergedMap.values.sorted { $0.closeTime < $1.closeTime }
        let final = Array(merged.suffix(5000))

        do {
            let data = try JSONEncoder().encode(final)
            try data.write(to: fileURL, options: .atomic)
            godLog("💾 Persistence: saved \(final.count) candles | \(symbol) | \(timeframe) | latest=\(formatDate(final.last?.closeTime))", level: .diagnostic)
        } catch {
            godLog("❌ Persistence: Failed to save candles for \(symbol) \(timeframe): \(error.localizedDescription)", level: .error)
        }
    }

    func loadCandles(for symbol: String, timeframe: String) async -> [Kline] {
        let fileURL = getFileURL(symbol: symbol, timeframe: timeframe)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let candles = try JSONDecoder().decode([Kline].self, from: data)
            return candles.map(normalizedCandle).sorted { $0.closeTime < $1.closeTime }
        } catch {
            godLog("⚠️ Persistence: Failed to load \(symbol) \(timeframe): \(error.localizedDescription)", level: .warning)
            return []
        }
    }

    func getLatestCandleTime(for symbol: String, timeframe: String) async -> Int? {
        let candles = await loadCandles(for: symbol, timeframe: timeframe)
        return candles.last?.closeTime
    }

    private func normalizedCandle(_ candle: Kline) -> Kline {
        Kline(
            open: candle.open,
            high: candle.high,
            low: candle.low,
            close: candle.close,
            volume: candle.volume,
            closeTime: normalizeEpochMilliseconds(candle.closeTime),
            spread: candle.spread,
            isClosed: candle.isClosed
        )
    }

    private func normalizeEpochMilliseconds(_ timestamp: Int) -> Int {
        guard timestamp > 0 else { return timestamp }
        if timestamp < 100_000_000_000 { return timestamp * 1_000 }
        return timestamp
    }

    private func formatDate(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "none" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000.0))
    }

    private func getFileURL(symbol: String, timeframe: String) -> URL {
        let safeSymbol = symbol.replacingOccurrences(of: "/", with: "_")
        return baseDirectory.appendingPathComponent("\(safeSymbol)_\(timeframe).json")
    }
}
