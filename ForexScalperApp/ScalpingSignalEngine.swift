// ScalpingSignalEngine.swift - GOD MODE V7.0 ELITE
import Foundation

actor ScalpingSignalEngine {
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol

    // Multi-timeframe analysis
    private let timeframes = ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"]
    private var lastSignalTime: [String: Date] = [:]
    
    // --- SELF-LEARNING QUALITY TRACKING ---
    private var signalQualityHistory: [String: [SignalQuality]] = [:]
    private let maxQualityHistory = 100
    
    // Symbol Performance Tracking
    private var symbolPerformance: [String: (wins: Int, losses: Int, pnl: Double)] = [:]
    private let minTradesForAdaptation = 5
    private let minWinRateForTrading = 0.40

    // Strict Symbol Filter
    private let allowedSymbols = Set([
        "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD",
        "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "EURGBP", "EURCHF",
        "GBPCHF", "CADJPY", "CHFJPY", "AUDCHF", "NZDCAD", "AUDNZD",
        "BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT"
    ])

    init(marketData: MarketDataProvider, 
         tradeHistory: RefactoredTradeHistoryManager, 
         riskManager: RiskManagerProtocol,
         config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
    }

    func updateSymbolPerformance(symbol: String, pnl: Double) {
        var perf = symbolPerformance[symbol] ?? (wins: 0, losses: 0, pnl: 0.0)
        if pnl > 0 { perf.wins += 1 } else if pnl < 0 { perf.losses += 1 }
        perf.pnl += pnl
        symbolPerformance[symbol] = perf
    }

    private func shouldTradeSymbol(_ symbol: String) -> Bool {
        guard let perf = symbolPerformance[symbol] else { return true }
        let totalTrades = perf.wins + perf.losses
        guard totalTrades >= minTradesForAdaptation else { return true }
        return Double(perf.wins) / Double(totalTrades) >= minWinRateForTrading
    }

    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        guard allowedSymbols.contains(symbol) else { return nil }
        guard shouldTradeSymbol(symbol) else { return nil }
        guard await MT5Service.shared.isSymbolTradable(symbol) else { return nil }
        guard await riskManager.canOpenTrade(for: symbol) else { return nil }

        let (enabledNews, highMin, medMin, cooldown, spreadTol) = await MainActor.run {
            (ScalpingConfig.shared.enableNewsFilter, 
             ScalpingConfig.shared.pauseBeforeHighImpactMinutes, 
             ScalpingConfig.shared.pauseBeforeMediumImpactMinutes,
             ScalpingConfig.shared.cooldownSeconds,
             ScalpingConfig.shared.spreadTolerance)
        }

        if enabledNews {
            let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: Int(max(highMin, medMin)))
            if impact == .high { return nil }
        }

        if let lastSignal = lastSignalTime[symbol], Date().timeIntervalSince(lastSignal) < cooldown {
            return nil
        }

        async let c1m = marketData.getCandles(symbol: symbol, timeframe: "1m")
        async let c5m = marketData.getCandles(symbol: symbol, timeframe: "5m")
        async let c1h = marketData.getCandles(symbol: symbol, timeframe: "1h")
        async let c4h = marketData.getCandles(symbol: symbol, timeframe: "4h")
        async let cD1 = marketData.getCandles(symbol: symbol, timeframe: "D1")
        async let cW1 = marketData.getCandles(symbol: symbol, timeframe: "W1")

        let candlesByTimeframe = await [
            "1m": c1m, "5m": c5m, "1h": c1h,
            "4h": c4h, "D1": cD1, "W1": cW1
        ]

        guard validateData(candlesByTimeframe, symbol: symbol) else { return nil }
        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe)

        let pointSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let actualSpread: Double
        if let s = indicators.spread {
            actualSpread = (s * pointSize / indicators.currentPrice) * 10000
        } else {
            actualSpread = (indicators.atr / indicators.currentPrice) * 10000
        }
        
        let atrPercentage = indicators.atr / indicators.currentPrice * 100
        godLog("🔍 EVAL: \(symbol) | Price: \(String(format: "%.5f", indicators.currentPrice)) | Spread: \(String(format: "%.1f", actualSpread)) pips | Vol: \(String(format: "%.3f", atrPercentage))%", level: .diagnostic)

        if actualSpread > spreadTol { 
            // godLog("⚠️ \(symbol) blocked: Spread too high (\(String(format: "%.1f", actualSpread)) > \(spreadTol))", level: .diagnostic)
            return nil 
        }
        guard await validateVolatility(symbol, indicators: indicators) else { 
            // godLog("⚠️ \(symbol) blocked: Volatility outside bounds (\(String(format: "%.3f", atrPercentage))%)", level: .diagnostic)
            return nil 
        }

        let signal = await generateSignal(symbol: symbol, indicators: indicators)
        if signal.type == .none { return nil }

        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        
        // Log Pillar Details
        let pillarDetails = signal.confidenceFactors.map { "\($0.key): \(Int($0.value))" }.joined(separator: ", ")
        godLog("📊 SCORE: \(symbol) \(signal.type) | Total Score: \(signal.score) | Confidence: \(Int(signal.confidence))% | Pillars: [\(pillarDetails)]", level: .diagnostic)

        guard signal.confidence >= threshold else { return nil }
        
        // --- SELF-LEARNING: Apply historical performance adjustment ---
        let adjustedSignal = await applyHistoricalAdjustment(signal)
        guard adjustedSignal.confidence >= threshold else { return nil }
        
        guard validateRiskReward(adjustedSignal) else { return nil }

        // Track quality for self-learning
        await trackSignalQuality(adjustedSignal)

        lastSignalTime[symbol] = Date()
        godLog("🚀 HYBRID SIGNAL: \(symbol) | Confidence: \(Int(adjustedSignal.confidence))%", level: .success)
        return adjustedSignal
    }

    private func applyHistoricalAdjustment(_ signal: ScalpingSignal) async -> ScalpingSignal {
        let qualityHistory = signalQualityHistory[signal.symbol] ?? []
        guard qualityHistory.count >= 10 else { return signal }
        
        let similarSignals = qualityHistory.filter {
            abs($0.confidence - signal.confidence) < 10 && $0.type == signal.type
        }
        
        let wins = similarSignals.compactMap { $0.wasWin }.filter { $0 }.count
        let total = similarSignals.compactMap { $0.wasWin }.count
        
        if total > 0 {
            let winRate = Double(wins) / Double(total)
            // ELITE: If historical win rate for this confidence bucket is poor, penalize confidence
            if winRate < 0.5 && signal.confidence > 80 {
                let adjustedConfidence = signal.confidence * 0.8
                return await signal.withConfidence(adjustedConfidence)
            }
        }
        return signal
    }

    func updateSignalQuality(symbol: String, type: SignalType, confidence: Double, wasWin: Bool) async {
        var history = signalQualityHistory[symbol] ?? []
        if let index = history.lastIndex(where: { $0.type == type && abs($0.confidence - confidence) < 5 && $0.wasWin == nil }) {
            history[index].wasWin = wasWin
        }
        signalQualityHistory[symbol] = history
    }

    private func trackSignalQuality(_ signal: ScalpingSignal) async {
        var history = signalQualityHistory[signal.symbol] ?? []
        let quality = SignalQuality(type: signal.type, confidence: signal.confidence, timestamp: signal.timestamp, wasWin: nil)
        history.append(quality)
        if history.count > maxQualityHistory { history.removeFirst() }
        signalQualityHistory[signal.symbol] = history
    }

    private func validateVolatility(_ symbol: String, indicators: IndicatorSet) async -> Bool {
        let atrPercentage = indicators.atr / indicators.currentPrice * 100
        let hour = Calendar.current.component(.hour, from: Date())
        
        var minVol: Double = 0.008
        if hour >= 0 && hour < 8 { minVol = 0.005 } // Asian
        else if hour >= 16 { minVol = 0.010 } // US
        
        return atrPercentage >= minVol && atrPercentage <= 0.50
    }

    private func calculateAllIndicators(symbol: String, candlesByTimeframe: [String: [Kline]]) async -> IndicatorSet {
        let c1m = candlesByTimeframe["1m"]!
        let c5m = candlesByTimeframe["5m"]!
        let _ = candlesByTimeframe["1h"]!
        let c4h = candlesByTimeframe["4h"]!
        let cD1 = candlesByTimeframe["D1"]!
        let cW1 = candlesByTimeframe["W1"]!
        
        let closes = c1m.map { $0.close }
        let currentPrice = closes.last ?? 0
        
        let asiaRange: (high: Double, low: Double) = (0, 0)
        let londonRange: (high: Double, low: Double) = (0, 0)
        let usRange: (high: Double, low: Double) = (0, 0)
        
        return IndicatorSet(
            rsi: Indicators.rsi(closes, period: 14).last ?? 50,
            stochasticK: 50, stochasticD: 50, cci: 0, sar: 0,
            atr: Indicators.atr(c1m, period: 14).last ?? 0,
            spread: c1m.last?.spread, 
            ema9: Indicators.ema(closes, period: 9).last ?? 0,
            ema21: Indicators.ema(closes, period: 21).last ?? 0,
            ema50: Indicators.ema(closes, period: 50).last ?? 0,
            ema9_5m: Indicators.ema(c5m.map { $0.close }, period: 9).last ?? 0,
            ema21_5m: Indicators.ema(c5m.map { $0.close }, period: 21).last ?? 0,
            ema50_5m: Indicators.ema(c5m.map { $0.close }, period: 50).last ?? 0,
            bbPosition: 0.5, volumeRatio: 1.0, volumeProfilePOC: 0, 
            support: 0, resistance: 0,
            sessions: (asiaRange: asiaRange, londonRange: londonRange, usRange: usRange),
            trendStrength: 0, pricePattern: .none, regime: .ranging,
            currentPrice: currentPrice, 
            h4Trend: calculateHTFTrend(candles: c4h), 
            d1Trend: calculateHTFTrend(candles: cD1), 
            w1Trend: calculateHTFTrend(candles: cW1)
        )
    }

    private func calculateHTFTrend(candles: [Kline]) -> SignalType {
        guard candles.count >= 20 else { return .none }
        let closes = candles.map { $0.close }
        let ema20 = Indicators.ema(closes, period: 20).last ?? 0
        let ema50 = Indicators.ema(closes, period: 50).last ?? 0
        if ema20 > ema50 { return .buy }
        if ema20 < ema50 { return .sell }
        return .none
    }

    private func generateSignal(symbol: String, indicators: IndicatorSet) async -> ScalpingSignal {
        var buyScore: Double = 0
        var sellScore: Double = 0
        var factors: [String: Double] = [:]

        // PILLAR 1: Institutional Trend Alignment (H4 + D1)
        if indicators.h4Trend == .buy && indicators.d1Trend == .buy {
            buyScore += 25
            factors["HTF Power Alignment"] = 25
        } else if indicators.h4Trend == .sell && indicators.d1Trend == .sell {
            sellScore += 25
            factors["HTF Power Alignment"] = 25
        }

        // PILLAR 2: Momentum & Exhaustion (RSI + Stoch)
        if indicators.rsi < 32 && indicators.stochasticK < 15 {
            buyScore += 15
            factors["Elite Dip Buy"] = 15
        } else if indicators.rsi > 68 && indicators.stochasticK > 85 {
            sellScore += 15
            factors["Elite Rally Sell"] = 15
        }

        // PILLAR 3: Institutional Volume Surge
        if indicators.volumeRatio >= 1.5 {
            buyScore += 12
            sellScore += 12
            factors["Smart Money Volume"] = 12
        }

        // PILLAR 4: EMA Stack Confluence (M1 + M5)
        let buyStack = indicators.ema9 > indicators.ema21 && indicators.ema21 > indicators.ema50
        let sellStack = indicators.ema9 < indicators.ema21 && indicators.ema21 < indicators.ema50
        
        if buyStack {
            buyScore += 18
            factors["Structural Support"] = 18
        } else if sellStack {
            sellScore += 18
            factors["Structural Resistance"] = 18
        }

        // PILLAR 5: Bollinger Rejection
        if indicators.bbPosition < 0.05 {
            buyScore += 10
            factors["BB Lower Sweep"] = 10
        } else if indicators.bbPosition > 0.95 {
            sellScore += 10
            factors["BB Upper Sweep"] = 10
        }
        
        // PILLAR 6: CCI Cycle Alignment
        if indicators.cci > 100 {
            buyScore += 10
            factors["Cyclical Strength"] = 10
        } else if indicators.cci < -100 {
            sellScore += 10
            factors["Cyclical Strength"] = 10
        }

        // PILLAR 7: SAR Trend Confirmation
        if indicators.sar < indicators.currentPrice {
            buyScore += 10
            factors["SAR Support"] = 10
        } else if indicators.sar > indicators.currentPrice {
            sellScore += 10
            factors["SAR Resistance"] = 10
        }

        // Final Confidence Calculation
        let type: SignalType = buyScore > sellScore ? .buy : (sellScore > buyScore ? .sell : .none)
        let finalScore = type == .buy ? buyScore : sellScore
        
        // ELITE: Confidence is a weighted average of pillars
        let confidence = min(finalScore * 1.1, 98.0) 

        // Dynamic Stop Loss & Take Profit (ATR Based)
        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let atrPips = indicators.atr / pipSize
        
        // ELITE MATH: SL is 1.5x ATR (min 6, max 15 pips)
        let slPips = max(6.0, min(15.0, atrPips * 1.5))
        // ELITE MATH: TP is 2.0x ATR (min 8, max 25 pips)
        let tpPips = max(8.0, min(25.0, atrPips * 2.0))
        
        let sl = type == .buy ? indicators.currentPrice - (slPips * pipSize) : indicators.currentPrice + (slPips * pipSize)
        let tp = type == .buy ? indicators.currentPrice + (tpPips * pipSize) : indicators.currentPrice - (tpPips * pipSize)

        return ScalpingSignal(
            type: type,
            symbol: symbol,
            price: indicators.currentPrice,
            confidence: confidence,
            score: Int(finalScore),
            sellScore: Int(sellScore),
            indicators: indicators,
            confidenceFactors: factors,
            timestamp: Date(),
            stopLoss: sl,
            takeProfit: tp,
            volume: 0.1
        )
    }

    private func validateRiskReward(_ signal: ScalpingSignal) -> Bool {
        guard let sl = signal.stopLoss, let tp = signal.takeProfit else { return false }
        return abs(tp - signal.price) / max(abs(signal.price - sl), 0.00001) >= 1.2
    }

    private func validateData(_ dict: [String: [Kline]], symbol: String) -> Bool {
        return (dict["1m"]?.count ?? 0) >= 100
    }
}
