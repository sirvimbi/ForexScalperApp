// RegimeDetectorProtocol.swift
import Foundation
import Combine // Add this import

// Implementation
actor HeuristicRegimeDetector: Core.RegimeDetector {
    private let marketData: MarketDataProvider
    
    init(marketData: MarketDataProvider) {
        self.marketData = marketData
    }
    
    func currentRegime(symbol: String) async -> Core.MarketRegime {
        let candles1h = await marketData.getCandles(symbol: symbol, timeframe: "1h")
        guard candles1h.count >= 50 else { return Core.MarketRegime.ranging }
        
        let closes = candles1h.map { $0.close }
        let atrArray = Indicators.atr(candles1h, period: 14)
        guard let atr = atrArray.last, let avgPrice = closes.last, avgPrice != 0 else { return Core.MarketRegime.ranging }
        
        let volatilityPercent = (atr / avgPrice) * 100
        
        // Approximate trend strength using linear regression slope on last 20 hours
        let slope = linearRegressionSlope(Array(closes.suffix(20)))
        let normalizedSlope = slope / (atr / avgPrice) // rough strength
        
        if volatilityPercent > 1.2 {
            return Core.MarketRegime.volatile
        } else if normalizedSlope > 0.5 {
            return Core.MarketRegime.strongUptrend
        } else if normalizedSlope < -0.5 {
            return Core.MarketRegime.strongDowntrend
        } else if volatilityPercent < 0.3 {
            return Core.MarketRegime.quiet
        } else {
            return Core.MarketRegime.ranging
        }
    }
    
    private func linearRegressionSlope(_ y: [Double]) -> Double {
        let n = y.count
        guard n > 1 else { return 0 }
        let x = Array(0..<n).map { Double($0) }
        let meanX = x.reduce(0, +) / Double(n)
        let meanY = y.reduce(0, +) / Double(n)
        let numerator = zip(x, y).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominator = x.map { pow($0 - meanX, 2) }.reduce(0, +)
        return denominator == 0 ? 0 : numerator / denominator
    }
}
