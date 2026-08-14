// MARK: - Enhanced MarketDataActor with Thread-Safe Caching
import Foundation

actor RefactoredMarketDataActor: MarketDataProvider {
    private var candleStore: [String: [Kline]] = [:]
    private var latestPrices: [String: Double] = [:]
    private var isHydrated: Set<String> = []
    
    private let maxCandles = 3000
    private let priceCache = NSCache<NSString, NSNumber>()

    private let diagnosticMinimums: [String: Int] = [
        "1m": 100,
        "5m": 50,
        "15m": 30,
        "30m": 20,
        "1h": 20,
        "4h": 20,
        "D1": 15,
        "W1": 1
    ]
    
    func addCandles(symbol: String, timeframe: String, newCandles: [Kline]) async {
        let key = "\(symbol)_\(timeframe)"
        
        if !isHydrated.contains(key) {
            let cached = await CandlePersistenceManager.shared.loadCandles(for: symbol, timeframe: timeframe)
            candleStore[key] = normalizeCandles(cached)
            isHydrated.insert(key)

            godLog("💧 CANDLE HYDRATE | \(symbol) | \(timeframe) | persisted=\(cached.count)", level: cached.isEmpty ? .warning : .diagnostic)
        }
        
        var array = candleStore[key] ?? []
        let normalizedIncoming = normalizeCandles(newCandles)
        var addedCount = 0
        
        for candle in normalizedIncoming {
            if let index = array.lastIndex(where: { $0.closeTime == candle.closeTime }) {
                array[index] = candle
            } else {
                array.append(candle)
                addedCount += 1
            }
        }
        
        array.sort { $0.closeTime < $1.closeTime }
        if array.count > maxCandles {
            array.removeFirst(array.count - maxCandles)
        }
        
        candleStore[key] = array
        
        if addedCount > 0 {
            await CandlePersistenceManager.shared.saveCandles(normalizedIncoming, for: symbol, timeframe: timeframe)
        }
        
        if timeframe == "1m", let last = array.last {
            latestPrices[symbol] = last.close
            priceCache.setObject(NSNumber(value: last.close), forKey: symbol as NSString)
        }

        logCandleInventory(symbol: symbol, timeframe: timeframe, candles: array, added: addedCount)
    }
    
    func addCandle(symbol: String, timeframe: String, candle: Kline) async {
        await addCandles(symbol: symbol, timeframe: timeframe, newCandles: [candle])
    }
    
    func getCandles(symbol: String, timeframe: String) async -> [Kline] {
        let key = "\(symbol)_\(timeframe)"
        let candles = candleStore[key] ?? []
        logCandleInventory(symbol: symbol, timeframe: timeframe, candles: candles, added: nil)
        return candles
    }
    
    private func normalizeCandles(_ candles: [Kline]) -> [Kline] {
        candles.map { candle in
            let date = candle.closeTime
            let epochSeconds = date.timeIntervalSince1970
            let milliseconds: Int

            // Kline's integer closeTime initializer represents milliseconds.
            // Some existing feeds supplied epoch seconds, which were therefore
            // interpreted as milliseconds and appeared around January 1970.
            if date < Date(timeIntervalSince1970: 946684800) {
                milliseconds = Int(epochSeconds * 1_000_000)
            } else {
                milliseconds = Int(epochSeconds * 1_000)
            }

            return Kline(
                open: candle.open,
                high: candle.high,
                low: candle.low,
                close: candle.close,
                volume: candle.volume,
                closeTime: milliseconds,
                spread: candle.spread,
                isClosed: candle.isClosed
            )
        }
    }
    
    private func logCandleInventory(symbol: String, timeframe: String, candles: [Kline], added: Int?) {
        let minimum = diagnosticMinimums[timeframe] ?? 1
        let count = candles.count
        let depthOK = count >= minimum
        let status = count == 0 ? "MISSING" : (depthOK ? "READY" : "PARTIAL")
        let level: LogLevel = count == 0 ? .warning : (depthOK ? .success : .diagnostic)

        let latest = candles.last.map { formatCandleDate($0.closeTime) } ?? "none"
        let oldest = candles.first.map { formatCandleDate($0.closeTime) } ?? "none"
        let missing = max(0, minimum - count)
        let delta = added.map { " | added=\($0)" } ?? ""

        godLog("🕯️ CANDLE \(status) | \(symbol) | TF=\(timeframe) | received=\(count) | required=\(minimum) | missing=\(missing) | oldest=\(oldest) | latest=\(latest)\(delta)", level: level)
    }

    private func formatCandleDate(_ time: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: time)
    }
    
    func getLatestPrice(symbol: String) async -> Double? {
        if let cached = priceCache.object(forKey: symbol as NSString) {
            return cached.doubleValue
        }
        return latestPrices[symbol]
    }
    
    func getCandlesBulk(symbols: [String], timeframe: String) async -> [String: [Kline]] {
        var result: [String: [Kline]] = [:]
        for symbol in symbols {
            let key = "\(symbol)_\(timeframe)"
            result[symbol] = candleStore[key] ?? []
        }
        return result
    }
    
    func isReadyForSignals(symbol: String) async -> Bool {
        let tfs = ["1m", "5m", "15m", "1h", "4h", "D1"]
        let requirements = [100, 50, 30, 20, 20, 15]
        
        for (i, tf) in tfs.enumerated() {
            let key = "\(symbol)_\(tf)"
            if (candleStore[key]?.count ?? 0) < requirements[i] {
                return false
            }
        }
        return true
    }
}
