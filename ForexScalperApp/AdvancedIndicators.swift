// AdvancedIndicators.swift
import Foundation

struct AdvancedIndicators {
    
    // MARK: - Commodity Channel Index (CCI)
    nonisolated static func cci(_ candles: [Kline], period: Int = 20) -> [Double] {
        guard candles.count > period else { return [] }
        
        var cciValues: [Double] = []
        
        for i in period..<candles.count {
            let slice = candles[(i - period)...i]
            let typicalPrices = slice.map { ($0.high + $0.low + $0.close) / 3.0 }
            let sma = typicalPrices.reduce(0, +) / Double(typicalPrices.count)
            
            let meanDeviation = typicalPrices.map { abs($0 - sma) }.reduce(0, +) / Double(typicalPrices.count)
            let cci = meanDeviation == 0 ? 0 : (typicalPrices.last! - sma) / (0.015 * meanDeviation)
            cciValues.append(cci)
        }
        
        return cciValues
    }
    
    // MARK: - Parabolic SAR
    nonisolated static func parabolicSAR(_ candles: [Kline], acceleration: Double = 0.02, maxAcceleration: Double = 0.2) -> [Double] {
        guard candles.count > 2 else { return [] }
        
        var sarValues: [Double] = []
        var af = acceleration
        var ep = candles[0].high
        var isUptrend = true
        var sar = candles[0].low
        
        for i in 1..<candles.count {
            let currentCandle = candles[i]
            
            if isUptrend {
                sar = sar + af * (ep - sar)
                
                if sar > currentCandle.low {
                    isUptrend = false
                    sar = ep
                    af = acceleration
                    ep = currentCandle.low
                } else {
                    if currentCandle.high > ep {
                        ep = currentCandle.high
                        af = min(af + acceleration, maxAcceleration)
                    }
                }
            } else {
                sar = sar - af * (sar - ep)
                
                if sar < currentCandle.high {
                    isUptrend = true
                    sar = ep
                    af = acceleration
                    ep = currentCandle.high
                } else {
                    if currentCandle.low < ep {
                        ep = currentCandle.low
                        af = min(af + acceleration, maxAcceleration)
                    }
                }
            }
            
            sarValues.append(sar)
        }
        
        return sarValues
    }
    
    // MARK: - Stochastic Oscillator
    nonisolated static func stochastic(_ candles: [Kline], periodK: Int = 14, periodD: Int = 3) -> (k: [Double], d: [Double]) {
        guard candles.count > periodK else { return ([], []) }
        
        var kValues: [Double] = []
        
        for i in periodK..<candles.count {
            let slice = candles[(i - periodK + 1)...i]
            let highestHigh = slice.map { $0.high }.max() ?? 0
            let lowestLow = slice.map { $0.low }.min() ?? 0
            let currentClose = candles[i].close
            
            let k = highestHigh == lowestLow ? 50 : ((currentClose - lowestLow) / (highestHigh - lowestLow)) * 100
            kValues.append(k)
        }
        
        let dValues = sma(kValues, period: periodD)
        
        return (kValues, dValues)
    }
    
    // MARK: - ATR (Average True Range) for volatility-based stops
    nonisolated static func atr(_ candles: [Kline], period: Int = 14) -> [Double] {
        guard candles.count > period else { return [] }
        
        var trValues: [Double] = []
        
        for i in 1..<candles.count {
            let high = candles[i].high
            let low = candles[i].low
            let prevClose = candles[i-1].close
            
            let tr = max(high - low, abs(high - prevClose), abs(low - prevClose))
            trValues.append(tr)
        }
        
        var atrValues: [Double] = []
        let firstAtr = trValues[0..<period].reduce(0, +) / Double(period)
        atrValues.append(firstAtr)
        
        for i in period..<trValues.count {
            let atr = (atrValues.last! * Double(period - 1) + trValues[i]) / Double(period)
            atrValues.append(atr)
        }
        
        return atrValues
    }
    
    // MARK: - Volume Profile
    nonisolated static func volumeProfile(_ candles: [Kline], levels: Int = 12) -> (valueArea: Double, poc: Double) {
        guard !candles.isEmpty else { return (0, 0) }
        
        let closes = candles.map { $0.close }
        let minPrice = closes.min() ?? 0
        let maxPrice = closes.max() ?? 0
        let range = maxPrice - minPrice
        let bucketSize = range / Double(levels)
        
        guard bucketSize > 0 else { return (0, 0) }
        
        var volumeByPrice: [Int: Double] = [:]
        
        for candle in candles {
            let bucketIndex = Int((candle.close - minPrice) / bucketSize)
            volumeByPrice[bucketIndex, default: 0] += candle.volume
        }
        
        // Find POC (Point of Control)
        let poc = volumeByPrice.max { $0.value < $1.value }?.key ?? 0
        let pocPrice = minPrice + (Double(poc) + 0.5) * bucketSize
        
        // Calculate Value Area (70% of volume)
        let totalVolume = volumeByPrice.values.reduce(0, +)
        let targetVolume = totalVolume * 0.7
        
        let sortedBuckets = volumeByPrice.sorted { $0.value > $1.value }
        var accumulatedVolume = 0.0
        var valueAreaBuckets: Set<Int> = []
        
        for bucket in sortedBuckets {
            if accumulatedVolume < targetVolume {
                valueAreaBuckets.insert(bucket.key)
                accumulatedVolume += bucket.value
            } else {
                break
            }
        }
        
        let minBucket = valueAreaBuckets.min() ?? 0
        let maxBucket = valueAreaBuckets.max() ?? 0
        let valueAreaLow = minPrice + Double(minBucket) * bucketSize
        let valueAreaHigh = minPrice + (Double(maxBucket) + 1) * bucketSize
        let valueArea = (valueAreaLow + valueAreaHigh) / 2
        
        return (valueArea, pocPrice)
    }
    
    // MARK: - Support/Resistance Levels
    nonisolated static func supportResistance(_ candles: [Kline], lookback: Int = 50) -> (support: Double, resistance: Double) {
        guard candles.count > lookback else { return (0, 0) }
        
        let recentCandles = Array(candles.suffix(lookback))
        
        // Find swing highs and lows
        var swingHighs: [Double] = []
        var swingLows: [Double] = []
        
        for i in 2..<recentCandles.count - 2 {
            if recentCandles[i].high > recentCandles[i-1].high &&
               recentCandles[i].high > recentCandles[i-2].high &&
               recentCandles[i].high > recentCandles[i+1].high &&
               recentCandles[i].high > recentCandles[i+2].high {
                swingHighs.append(recentCandles[i].high)
            }
            
            if recentCandles[i].low < recentCandles[i-1].low &&
               recentCandles[i].low < recentCandles[i-2].low &&
               recentCandles[i].low < recentCandles[i+1].low &&
               recentCandles[i].low < recentCandles[i+2].low {
                swingLows.append(recentCandles[i].low)
            }
        }
        
        let resistance = swingHighs.reduce(0, +) / Double(max(1, swingHighs.count))
        let support = swingLows.reduce(0, +) / Double(max(1, swingLows.count))
        
        return (support, resistance)
    }
    
    // MARK: - Market Profile (Trading sessions)
    nonisolated static func sessionAnalysis(_ candles: [Kline]) -> (asiaRange: (high: Double, low: Double),
                                                          londonRange: (high: Double, low: Double),
                                                          usRange: (high: Double, low: Double)) {
        let calendar = Calendar.current
        var asiaHigh = 0.0, asiaLow = Double.infinity
        var londonHigh = 0.0, londonLow = Double.infinity
        var usHigh = 0.0, usLow = Double.infinity
        
        for candle in candles {
            let date = Date(timeIntervalSince1970: TimeInterval(candle.closeTime / 1000))
            let hour = calendar.component(.hour, from: date)
            
            // Rough session times (UTC)
            switch hour {
            case 0...8: // Asia session
                asiaHigh = max(asiaHigh, candle.high)
                asiaLow = min(asiaLow, candle.low)
            case 8...16: // London session
                londonHigh = max(londonHigh, candle.high)
                londonLow = min(londonLow, candle.low)
            case 16...24: // US session
                usHigh = max(usHigh, candle.high)
                usLow = min(usLow, candle.low)
            default:
                break
            }
        }
        
        return (
            asiaRange: (asiaHigh.isFinite ? asiaHigh : 0, asiaLow.isFinite ? asiaLow : 0),
            londonRange: (londonHigh.isFinite ? londonHigh : 0, londonLow.isFinite ? londonLow : 0),
            usRange: (usHigh.isFinite ? usHigh : 0, usLow.isFinite ? usLow : 0)
        )
    }
    
    nonisolated private static func sma(_ values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }
        var result: [Double] = []
        for i in (period - 1)..<values.count {
            let sum = values[(i - period + 1)...i].reduce(0, +)
            result.append(sum / Double(period))
        }
        return result
    }
}
