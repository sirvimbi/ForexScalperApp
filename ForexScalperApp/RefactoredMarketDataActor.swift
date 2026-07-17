// MARK: - Enhanced MarketDataActor with Caching
import Foundation

actor RefactoredMarketDataActor: MarketDataProvider {
    private var candles: [String: [String: [Kline]]] = [:]
    private var latestPrices: [String: Double] = [:]
    private let maxCandles = 3000 // Deep memory for long-term indicators and God Mode patterns
    private let priceCache = NSCache<NSString, NSNumber>() // For quick price lookups
    
    func addCandle(symbol: String, timeframe: String, candle: Kline) {
        if candles[symbol] == nil {
            candles[symbol] = [:]
        }
        if candles[symbol]?[timeframe] == nil {
            candles[symbol]?[timeframe] = []
        }
        
        var array = candles[symbol]![timeframe]!
        
        // Update or append
        if let index = array.lastIndex(where: { $0.closeTime == candle.closeTime }) {
            array[index] = candle
        } else {
            array.append(candle)
            if array.count > maxCandles {
                array.removeFirst()
            }
        }
        
        candles[symbol]![timeframe] = array
        
        // Update latest price
        if timeframe == "1m" {
            latestPrices[symbol] = candle.close
            priceCache.setObject(NSNumber(value: candle.close), forKey: symbol as NSString)
            
            // Print occasional debug info
            if array.count % 100 == 0 {
                print("📊 Market data: \(symbol) 1m now has \(array.count) candles, last price: \(candle.close)")
            }
        }
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
        let has1h = (symbolCandles["1h"]?.count ?? 0) >= 20
        
        return has1m && has5m && has1h
    }
}
