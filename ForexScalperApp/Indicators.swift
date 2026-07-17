import Foundation

struct Indicators {
    
    // MARK: - Exponential Moving Average
    nonisolated static func ema(_ values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }
        var emaValues = [Double]()
        let multiplier = 2.0 / Double(period + 1)
        // Start with SMA
        let sma = values[0..<period].reduce(0, +) / Double(period)
        emaValues.append(sma)
        for i in period..<values.count {
            let ema = (values[i] - emaValues.last!) * multiplier + emaValues.last!
            emaValues.append(ema)
        }
        return emaValues
    }
    
    // MARK: - Simple Moving Average
    nonisolated static func sma(_ values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }
        var smaValues = [Double]()
        for i in (period - 1)..<values.count {
            let sum = values[(i - period + 1)...i].reduce(0, +)
            smaValues.append(sum / Double(period))
        }
        return smaValues
    }
    
    // MARK: - RSI
    nonisolated static func rsi(_ values: [Double], period: Int = 14) -> [Double] {
        guard values.count > period else { return [] }
        var gains = [Double]()
        var losses = [Double]()
        for i in 1..<values.count {
            let diff = values[i] - values[i-1]
            gains.append(max(diff, 0))
            losses.append(max(-diff, 0))
        }
        // First average
        let avgGain = gains[0..<period].reduce(0, +) / Double(period)
        let avgLoss = losses[0..<period].reduce(0, +) / Double(period)
        var rsiValues = [Double]()
        var prevAvgGain = avgGain
        var prevAvgLoss = avgLoss
        for i in period..<gains.count {
            let gain = gains[i]
            let loss = losses[i]
            let avgGain = (prevAvgGain * Double(period - 1) + gain) / Double(period)
            let avgLoss = (prevAvgLoss * Double(period - 1) + loss) / Double(period)
            let rs = avgLoss == 0 ? 100 : avgGain / avgLoss
            let rsi = 100 - 100 / (1 + rs)
            rsiValues.append(rsi)
            prevAvgGain = avgGain
            prevAvgLoss = avgLoss
        }
        return rsiValues
    }
    
    // MARK: - Bollinger Bands
    nonisolated static func bollingerBands(_ values: [Double], period: Int = 20, stdDev: Double = 2.0) -> (middle: [Double], upper: [Double], lower: [Double]) {
        guard values.count >= period else { return ([], [], []) }
        let middle = sma(values, period: period)
        var upper = [Double]()
        var lower = [Double]()
        for i in (period - 1)..<values.count {
            let slice = values[(i - period + 1)...i]
            let mean = middle[i - (period - 1)]
            let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(period)
            let sd = sqrt(variance)
            upper.append(mean + stdDev * sd)
            lower.append(mean - stdDev * sd)
        }
        return (middle, upper, lower)
    }
    
    // MARK: - MACD
    nonisolated static func macd(_ values: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> (macd: [Double], signal: [Double], histogram: [Double]) {
        let emaFast = ema(values, period: fast)
        let emaSlow = ema(values, period: slow)
        // Align lengths
        let minCount = min(emaFast.count, emaSlow.count)
        let macdLine = zip(emaFast.suffix(minCount), emaSlow.suffix(minCount)).map { $0 - $1 }
        let signalLine = ema(macdLine, period: signal)
        let histCount = min(macdLine.count, signalLine.count)
        let histogram = zip(macdLine.suffix(histCount), signalLine.suffix(histCount)).map { $0 - $1 }
        return (macdLine, signalLine, histogram)
    }
    
    // MARK: - ATR
    nonisolated static func atr(_ candles: [Kline], period: Int = 14) -> [Double] {
        guard candles.count > period else { return [] }
        var trs: [Double] = []
        for i in 1..<candles.count {
            let high = candles[i].high
            let low = candles[i].low
            let prevClose = candles[i-1].close
            let tr = max(high - low, abs(high - prevClose), abs(low - prevClose))
            trs.append(tr)
        }
        // First ATR is SMA of first 'period' TRs
        var atrValues: [Double] = []
        let firstAtr = trs[0..<period].reduce(0, +) / Double(period)
        atrValues.append(firstAtr)
        for i in period..<trs.count {
            let atr = (atrValues.last! * Double(period - 1) + trs[i]) / Double(period)
            atrValues.append(atr)
        }
        return atrValues
    }
}
