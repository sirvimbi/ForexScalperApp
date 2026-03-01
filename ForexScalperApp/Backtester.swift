import Foundation

typealias MarketDataActor = RefactoredMarketDataActor

actor Backtester {
    private let marketData: MarketDataActor
    private let mlModel: MLModelHandler
    
    init(marketData: MarketDataActor, mlModel: MLModelHandler) {
        self.marketData = marketData
        self.mlModel = mlModel
    }
    
    func backtest(symbol: String, days: Int = 30) async -> BacktestResultData? {
        let candles = await marketData.getCandles(symbol: symbol, timeframe: "1h")
        guard candles.count > 100 else { return nil }
        
        var trades: [(entry: Kline, exit: Kline, pnl: Double)] = []
        var equity: [Double] = [10000] // Starting equity
        var drawdowns: [Double] = []
        
        // Sliding window backtest
        for i in 100..<(candles.count - 24) { // Leave room for exit
            let windowCandles = Array(candles[i-100...i])
            
            // Extract features
            let closes = windowCandles.map { $0.close }
            let features = await extractFeatures(candles: windowCandles)
            
            // Get ML prediction
            guard let (signal, confidence) = await mlModel.predictSignal(features: features),
                  signal != .neutral,
                  confidence > 0.7 else { continue }
            
            // Simulate trade
            let entry = candles[i]
            var exit: Kline?
            var pnl: Double = 0
            
            // Look for exit after 5-20 candles
            for j in (i+1)...min(i+20, candles.count-1) {
                let current = candles[j]
                
                // Exit conditions
                if signal == .buy {
                    if current.high >= entry.close * 1.002 { // 0.2% profit
                        exit = current
                        pnl = (min(current.high, entry.close * 1.002) - entry.close) / entry.close * 10000
                        break
                    } else if current.low <= entry.close * 0.998 { // 0.2% loss
                        exit = current
                        pnl = (max(current.low, entry.close * 0.998) - entry.close) / entry.close * 10000
                        break
                    }
                } else { // sell
                    if current.low <= entry.close * 0.998 {
                        exit = current
                        pnl = (entry.close - max(current.low, entry.close * 0.998)) / entry.close * 10000
                        break
                    } else if current.high >= entry.close * 1.002 {
                        exit = current
                        pnl = (entry.close - min(current.high, entry.close * 1.002)) / entry.close * 10000
                        break
                    }
                }
            }
            
            if let exit = exit {
                trades.append((entry, exit, pnl))
                let newEquity = equity.last! + pnl
                equity.append(newEquity)
                
                // Calculate drawdown
                let peak = equity.max() ?? newEquity
                let drawdown = (peak - newEquity) / peak * 100
                drawdowns.append(drawdown)
            }
        }
        
        // Calculate metrics
        let wins = trades.filter { $0.pnl > 0 }.count
        let losses = trades.filter { $0.pnl < 0 }.count
        let totalPnL = trades.reduce(0) { $0 + $1.pnl }
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100
        let maxDrawdown = drawdowns.max() ?? 0
        let profitFactor = losses > 0 ?
            abs(trades.filter { $0.pnl > 0 }.reduce(0) { $0 + $1.pnl } /
                trades.filter { $0.pnl < 0 }.reduce(0) { $0 + $1.pnl }) : 0
        
        // Sharpe ratio (simplified)
        let returns = trades.map { $0.pnl / 10000 }
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - avgReturn, 2) }.reduce(0, +) / Double(returns.count)
        let stdDev = sqrt(variance)
        let sharpeRatio = stdDev > 0 ? avgReturn / stdDev * sqrt(252) : 0
        
        return BacktestResultData(
            symbol: symbol,
            totalTrades: trades.count,
            wins: wins,
            losses: losses,
            winRate: winRate,
            totalPnL: totalPnL,
            maxDrawdown: maxDrawdown,
            sharpeRatio: sharpeRatio,
            profitFactor: profitFactor
        )
    }
    
    private func extractFeatures(candles: [Kline]) async -> [String: Double] {
        // Simplified feature extraction for backtesting
        guard let lastClose = candles.last?.close,
              let lastOpen = candles.last?.open,
              let lastHigh = candles.last?.high,
              let lastLow = candles.last?.low else {
            return [:]
        }
        
        let closes = candles.map { $0.close }
        let volumes = candles.map { $0.volume }
        
        return [
            "returns": closes.count > 1 ? (lastClose - closes[closes.count-2]) / closes[closes.count-2] : 0,
            "high_low_pct": (lastHigh - lastLow) / lastClose,
            "close_open_pct": (lastClose - lastOpen) / lastOpen,
            "sma_10": closes.suffix(10).reduce(0, +) / 10,
            "sma_20": closes.suffix(20).reduce(0, +) / 20,
            "sma_50": closes.suffix(50).reduce(0, +) / Double(min(50, closes.count)),
            "ema_12": Indicators.ema(closes, period: 12).last ?? lastClose,
            "ema_26": Indicators.ema(closes, period: 26).last ?? lastClose,
            "rsi": Indicators.rsi(closes, period: 14).last ?? 50,
            "macd": 0, "macd_signal": 0, "macd_hist": 0,
            "bb_width": 0, "bb_position": 0.5,
            "atr_pct": Indicators.atr(candles, period: 14).last ?? 0 / lastClose,
            "volume_ratio": volumes.suffix(20).reduce(0, +) / 20 > 0 ?
                (volumes.last ?? 1) / (volumes.suffix(20).reduce(0, +) / 20) : 1
        ]
    }
}
