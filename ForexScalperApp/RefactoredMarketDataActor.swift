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

    private var lastInventoryLog: [String: (count: Int, latest: Int, status: String, loggedAt: Date)] = [:]
    private let inventoryLogInterval: TimeInterval = 30

    func addCandles(symbol: String, timeframe: String, newCandles: [Kline]) async {
        let key = "\(symbol)_\(timeframe)"

        if !isHydrated.contains(key) {
            let cached = await CandlePersistenceManager.shared.loadCandles(for: symbol, timeframe: timeframe)
            if candleStore[key] == nil {
                candleStore[key] = cached.map(normalizeCandleTimestamp)
            }
            isHydrated.insert(key)
            godLog("💧 CANDLE HYDRATE | \(symbol) | TF=\(timeframe) | persisted=\(cached.count)", level: cached.isEmpty ? .warning : .diagnostic)
        }

        var array = candleStore[key] ?? []
        var addedCount = 0

        for rawCandle in newCandles {
            let candle = normalizeCandleTimestamp(rawCandle)
            if let index = array.lastIndex(where: { $0.closeTime == candle.closeTime }) {
                array[index] = candle
            } else {
                array.append(candle)
                addedCount += 1
            }
        }

        if array.count > maxCandles {
            array.removeFirst(array.count - maxCandles)
        }

        // Keep the store chronologically ordered after repairing legacy timestamps.
        array.sort { $0.closeTime < $1.closeTime }
        candleStore[key] = array

        if addedCount > 0 {
            await CandlePersistenceManager.shared.saveCandles(array.suffix(min(array.count, newCandles.count)), for: symbol, timeframe: timeframe)
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

    private func normalizeCandleTimestamp(_ candle: Kline) -> Kline {
        var seconds = Double(candle.closeTime)

        if seconds > 10_000_000_000 {
            // Milliseconds -> seconds.
            seconds /= 1000.0
        } else if seconds > 0 && seconds < 946_684_800 {
            // Common legacy corruption: milliseconds were divided by 1000 twice.
            // Forex/crypto market history in this app should not legitimately predate 2000.
            seconds *= 1000.0
        }

        return Kline(
            open: candle.open,
            high: candle.high,
            low: candle.low,
            close: candle.close,
            volume: candle.volume,
            closeTime: Int(seconds.rounded()),
            spread: candle.spread,
            isClosed: candle.isClosed
        )
    }

    private func logCandleInventory(symbol: String, timeframe: String, candles: [Kline], added: Int?) {
        let minimum = diagnosticMinimums[timeframe] ?? 1
        let count = candles.count
        let depthOK = count >= minimum
        let status = count == 0 ? "MISSING" : (depthOK ? "READY" : "PARTIAL")

        let latestEpoch = candles.last?.closeTime ?? 0
        let oldestEpoch = candles.first?.closeTime ?? 0
        let now = Date()
        let key = "\(symbol)_\(timeframe)"
        let previous = lastInventoryLog[key]
        let changed = previous?.count != count || previous?.latest != latestEpoch || previous?.status != status
        let periodic = previous == nil || now.timeIntervalSince(previous!.loggedAt) >= inventoryLogInterval

        guard changed || periodic || added.map({ $0 > 0 }) == true else { return }
        lastInventoryLog[key] = (count: count, latest: latestEpoch, status: status, loggedAt: now)

        let level: LogLevel = count == 0 ? .warning : (depthOK ? .success : .diagnostic)
        let missing = max(0, minimum - count)
        let delta = added.map { " | added=\($0)" } ?? ""

        godLog(
            "🕯️ CANDLE \(status) | \(symbol) | TF=\(timeframe) | received=\(count) | required=\(minimum) | missing=\(missing) | oldest=\(formatCandleDate(oldestEpoch)) | latest=\(formatCandleDate(latestEpoch))\(delta)",
            level: level
        )
    }

    private func formatCandleDate(_ epoch: Int) -> String {
        guard epoch > 0 else { return "none" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
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