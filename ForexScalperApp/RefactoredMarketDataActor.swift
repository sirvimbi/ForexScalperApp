// MARK: - Enhanced MarketDataActor with Caching
import Foundation

actor RefactoredMarketDataActor: MarketDataProvider {
    private var candles: [String: [String: [Kline]]] = [:]
    private var latestPrices: [String: Double] = [:]
    private let maxCandles = 3000 // Deep memory for long-term indicators and God Mode patterns
    private let priceCache = NSCache<NSString, NSNumber>() // For quick price lookups
    
    func addCandles(symbol: String, timeframe: String, newCandles: [Kline]) {
        if candles[symbol] == nil {
            candles[symbol] = [:]
        }
        if candles[symbol]?[timeframe] == nil {
            candles[symbol]?[timeframe] = CandlePersistenceManager.shared.loadCandles(for: symbol, timeframe: timeframe)
        }
        
        var array = candles[symbol]![timeframe]!
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
        
        candles[symbol]![timeframe] = array
        
        if addedCount > 0 {
            CandlePersistenceManager.shared.saveCandles(newCandles, for: symbol, timeframe: timeframe)
        }
        
        if timeframe == "1m", let last = array.last {
            latestPrices[symbol] = last.close
            priceCache.setObject(NSNumber(value: last.close), forKey: symbol as NSString)
        }
    }
    
    func addCandle(symbol: String, timeframe: String, candle: Kline) {
        addCandles(symbol: symbol, timeframe: timeframe, newCandles: [candle])
    }
    
    func getCandles(symbol: String, timeframe: String) async -> [Kline] {
        return candles[symbol]?[timeframe] ?? []
    }
    
    func getLatestPrice(symbol: String) async -> Double? {
        // Check cache first for performance
        if let cached = priceCache.object(forKey: symbol as NSString) {
            return cached.doubleValue
        }
        return latestPrices[symbol]
    }
    
    func getCandlesBulk(symbols: [String], timeframe: String) async -> [String: [Kline]] {
        var result: [String: [Kline]] = [:]
        for symbol in symbols {
            result[symbol] = candles[symbol]?[timeframe] ?? []
        }
        return result
    }
    
    func isReadyForSignals(symbol: String) -> Bool {
        guard let symbolCandles = candles[symbol] else { return false }
        
        let has1m = (symbolCandles["1m"]?.count ?? 0) >= 100
        let has5m = (symbolCandles["5m"]?.count ?? 0) >= 50
        let has15m = (symbolCandles["15m"]?.count ?? 0) >= 30
        let has1h = (symbolCandles["1h"]?.count ?? 0) >= 20
        let has4h = (symbolCandles["4h"]?.count ?? 0) >= 20
        let hasD1 = (symbolCandles["D1"]?.count ?? 0) >= 15
        
        return has1m && has5m && has15m && has1h && has4h && hasD1
    }
}
