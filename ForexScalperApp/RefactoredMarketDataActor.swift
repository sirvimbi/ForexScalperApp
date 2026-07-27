// MARK: - Enhanced MarketDataActor with Thread-Safe Caching
import Foundation

actor RefactoredMarketDataActor: MarketDataProvider {
    // CRITICAL: Flattened storage to prevent nested dictionary re-entrancy crashes
    private var candleStore: [String: [Kline]] = [:] // Key: "Symbol_Timeframe"
    private var latestPrices: [String: Double] = [:]
    private var isHydrated: Set<String> = [] // Key: "Symbol_Timeframe"
    
    private let maxCandles = 3000
    private let priceCache = NSCache<NSString, NSNumber>()
    
    func addCandles(symbol: String, timeframe: String, newCandles: [Kline]) async {
        let key = "\(symbol)_\(timeframe)"
        
        // 1. HYDRATION GUARD: Load from persistence only once
        if !isHydrated.contains(key) {
            let cached = await CandlePersistenceManager.shared.loadCandles(for: symbol, timeframe: timeframe)
            
            // Re-check after await to prevent race during hydration
            if candleStore[key] == nil {
                candleStore[key] = cached
            }
            isHydrated.insert(key)
        }
        
        var array = candleStore[key] ?? []
        var addedCount = 0
        
        for candle in newCandles {
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
        
        // Use direct assignment to ensure value type safety
        candleStore[key] = array
        
        if addedCount > 0 {
            await CandlePersistenceManager.shared.saveCandles(newCandles, for: symbol, timeframe: timeframe)
        }
        
        if timeframe == "1m", let last = array.last {
            latestPrices[symbol] = last.close
            priceCache.setObject(NSNumber(value: last.close), forKey: symbol as NSString)
        }
    }
    
    func addCandle(symbol: String, timeframe: String, candle: Kline) async {
        await addCandles(symbol: symbol, timeframe: timeframe, newCandles: [candle])
    }
    
    func getCandles(symbol: String, timeframe: String) async -> [Kline] {
        let key = "\(symbol)_\(timeframe)"
        return candleStore[key] ?? []
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
