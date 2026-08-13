// ScalpingSignalEngine.swift - GOD MODE V7.0 ELITE (Hybrid + Self-Learning)
import Foundation

actor ScalpingSignalEngine {
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol
    private let mlModel: MLModelHandler

    // Multi-timeframe analysis
    private let timeframes = ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"]
    private var lastSignalTime: [String: Date] = [:]

    // --- HTF CACHING (V10.0 Early Entry) ---
    private var cachedHTFTrends: [String: [String: (trend: SignalType, timestamp: Date)]] = [:]
    private let htfCacheDuration: TimeInterval = 300 // 5 minutes

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
         mlModel: MLModelHandler,
         config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
        self.mlModel = mlModel
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
        if totalTrades < minTradesForAdaptation { return true }
        let winRate = Double(perf.wins) / Double(totalTrades)
        return winRate >= minWinRateForTrading
    }

    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        // WHITELIST CHECK
        guard allowedSymbols.contains(symbol) else {
            return nil
        }

        // PERFORMANCE CHECK (Informational only)
        var learningWarning: String? = nil
        if !shouldTradeSymbol(symbol) {
            let perf = symbolPerformance[symbol]!
            let wr = Double(perf.wins) / Double(perf.wins + perf.losses)
            learningWarning = "Historical Win Rate is only \(Int(wr*100))%"
        }

        // MT5 TRADABLE CHECK
        guard await MT5Service.shared.isSymbolTradable(symbol) else {
            return nil
        }

        // RISK MANAGER CHECK
        guard await riskManager.canOpenTrade(for: symbol) else {
            return nil
        }

        let (enabledNews, highMin, medMin, cooldown, spreadTol, rocPeriod) = await MainActor.run {
            let config = ScalpingConfig.shared
            return (config.enableNewsFilter,
                config.pauseBeforeHighImpactMinutes,
                config.pauseBeforeMediumImpactMinutes,
                config.cooldownSeconds,
                config.spreadTolerance,
                config.rocPeriod)
        }

        // NEWS CHECK
        if enabledNews {
            let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: Int(max(highMin, medMin)))
            if impact == .high {
                godLog("⚠️ \(symbol) skipped: High-impact news detected", level: .diagnostic)
                return nil
            }
        }

        // COOLDOWN CHECK
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

        // DATA VALIDATION CHECK
        guard validateData(candlesByTimeframe, symbol: symbol) else {
            godLog("⚠️ \(symbol) skipped: Insufficient history (need 100 1m candles)", level: .diagnostic)
            return nil
        }

        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe, rocPeriod: rocPeriod)

        // SPREAD CHECK
        let pointSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let actualSpread: Double
        if let s = indicators.spread {
            actualSpread = (s * pointSize / indicators.currentPrice) * 10000
        } else {
            actualSpread = (indicators.atr / indicators.currentPrice) * 10000
        }

        if actualSpread > spreadTol {
            godLog("⚠️ \(symbol) skipped: Spread too high (\(String(format: "%.1f", actualSpread)) > \(spreadTol))", level: .diagnostic)
            return nil
        }

        // VOLATILITY CHECK
        let atrPercentage = indicators.atr / indicators.currentPrice * 100
        guard await validateVolatility(symbol, indicators: indicators) else {
            godLog("⚠️ \(symbol) skipped: Volatility outside bounds (\(String(format: "%.3f", atrPercentage))%)", level: .diagnostic)
            return nil
        }

        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candlesByTimeframe["1m"]!)
        if let warning = learningWarning {
            finalSignal = finalSignal.withSelfLearningInsight(warning)
        }

        // CONFIDENCE THRESHOLD CHECK
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }

        // Detailed Logging
        let metPillars = finalSignal.confidenceFactors.keys.sorted()
        let allPillars = ["HTF Power Alignment", "Elite Dip Buy", "Elite Rally Sell", "Smart Money Volume", "Structural Support", "Structural Resistance", "BB Lower Sweep", "BB Upper Sweep", "Cyclical Strength", "SAR Support", "SAR Resistance", "Momentum Surge", "ML Confirmed", "Order Flow Buy", "Order Flow Sell"]
        let failedPillars = allPillars.filter { pillar in
            !metPillars.contains { $0 == pillar }
        }

        let metString = metPillars.map { "✅ \($0)" }.joined(separator: ", ")
        let failedString = failedPillars.map { "❌ \($0)" }.joined(separator: ", ")

        let logMsg = "📊 EVAL: \(symbol) \(finalSignal.type) | Conf: \(Int(finalSignal.confidence))% (Need \(Int(threshold))%) | MET: [\(metString)] | FAILED: [\(failedString)]"

        if finalSignal.type == .none || finalSignal.confidence < threshold {
            godLog(logMsg, level: .diagnostic)
            return nil
        }

        // --- SELF-LEARNING: Apply historical performance adjustment ---
        let adjustedSignal = await applyHistoricalAdjustment(finalSignal)

        if adjustedSignal.confidence < threshold {
            let warning = "Self-Learning adjusted confidence from \(Int(finalSignal.confidence))% to \(Int(adjustedSignal.confidence))% (Win Rate < 50%)"
            // We don't block anymore, but we keep the insight
            return adjustedSignal.withSelfLearningInsight(warning)
        }

        // RISK/REWARD CHECK
        guard await RRLock.validate(signal: adjustedSignal) else {
            godLog("⚠️ \(symbol) skipped: Risk/Reward check failed", level: .diagnostic)
            return nil
        }

        // Track quality for self-learning
        await trackSignalQuality(adjustedSignal)

        lastSignalTime[symbol] = Date()
        godLog("🚀 HYBRID SIGNAL: \(symbol) | Confidence: \(Int(adjustedSignal.confidence))%", level: .success)
        return adjustedSignal
    }

    // --- FAST EVALUATION (V10.0 Early Entry) ---
    func evaluateFastSignal(symbol: String, currentPrice: Double) async -> ScalpingSignal? {
        guard allowedSymbols.contains(symbol) else { return nil }

        // 1. Performance/Tradable/Risk Checks (Quick)
        guard shouldTradeSymbol(symbol) else { return nil }
        guard await riskManager.canOpenTrade(for: symbol) else { return nil }

        // 2. Cached HTF Trend Check
        let h4Trend = await getCachedTrend(symbol: symbol, timeframe: "4h")
        let d1Trend = await getCachedTrend(symbol: symbol, timeframe: "D1")

        guard h4Trend != .none && h4Trend == d1Trend else { return nil }

        // 3. Fast Indicators (1m only)
        let candles1m = await marketData.getCandles(symbol: symbol, timeframe: "1m")
        guard candles1m.count >= 100 else { return nil }

        let indicators = await calculateFastIndicators(symbol: symbol, candles1m: candles1m, h4Trend: h4Trend, d1Trend: d1Trend)

        // 4. Generate & Adjust Signal
        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candles1m)
        finalSignal = await applyHistoricalAdjustment(finalSignal)

        // 5. Threshold & R:R Check
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        guard finalSignal.confidence >= threshold else { return nil }
        guard await RRLock.validate(signal: finalSignal) else { return nil }

        lastSignalTime[symbol] = Date()
        godLog("⚡️ FAST SIGNAL: \(symbol) | Confidence: \(Int(finalSignal.confidence))%", level: .success)
        return finalSignal
    }

    private func getCachedTrend(symbol: String, timeframe: String) async -> SignalType {
        if let cached = cachedHTFTrends[symbol]?[timeframe],
           Date().timeIntervalSince(cached.timestamp) < htfCacheDuration {
            return cached.trend
        }

        // Refresh cache
        let candles = await marketData.getCandles(symbol: symbol, timeframe: timeframe)
        let trend = calculateHTFTrend(candles: candles)

        if cachedHTFTrends[symbol] == nil { cachedHTFTrends[symbol] = [:] }
        cachedHTFTrends[symbol]?[timeframe] = (trend: trend, timestamp: Date())

        return trend
    }

    private func calculateFastIndicators(symbol: String, candles1m: [Kline], h4Trend: SignalType, d1Trend: SignalType) async -> IndicatorSet {
        let closes = candles1m.map { $0.close }
        let currentPrice = closes.last ?? 0

        let rsi = Indicators.rsi(closes, period: 14).last ?? 50
        let atr = AdvancedIndicators.atr(candles1m, period: 14).last ?? 0
        let stoch = AdvancedIndicators.stochastic(candles1m, periodK: 14, periodD: 3)
        let bb = Indicators.bollingerBands(closes, period: 20, stdDev: 2.0)
        let bbPos = (currentPrice - (bb.lower.last ?? 0)) / max((bb.upper.last ?? 1) - (bb.lower.last ?? 0), 0.0001)

        let ema9 = Indicators.ema(closes, period: 9).last ?? 0
        let ema21 = Indicators.ema(closes, period: 21).last ?? 0
        let ema50 = Indicators.ema(closes, period: 50).last ?? 0

        let (momentum, isAccel) = getMomentumScore(candles: candles1m, rocPeriod: 10)
        let gaps = AdvancedIndicators.detectFairValueGaps(candles1m)
        let delta = await MT5WebSocketService.shared.getDeltaVolume(for: symbol)

        return IndicatorSet(
            rsi: rsi, stochasticK: stoch.k.last ?? 50, stochasticD: stoch.d.last ?? 50,
            cci: 0, sar: currentPrice, atr: atr, spread: candles1m.last?.spread,
            ema9: ema9, ema21: ema21, ema50: ema50,
            ema9_5m: ema9, ema21_5m: ema21, ema50_5m: ema50, // Simplified for fast path
            bbPosition: bbPos, volumeRatio: 1.0, volumeProfilePOC: 0,
            support: 0, resistance: 0, sessions: (asiaRange: (0,0), londonRange: (0,0), usRange: (0,0)),
            trendStrength: 0, pricePattern: .none, regime: .ranging,
            currentPrice: currentPrice, h4Trend: h4Trend, d1Trend: d1Trend, w1Trend: .none,
            momentumScore: momentum, isAccelerating: isAccel, fvgGaps: gaps, deltaVolume: delta
        )
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
                return signal.withConfidence(adjustedConfidence)
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

    private func calculateAllIndicators(symbol: String, candlesByTimeframe: [String: [Kline]], rocPeriod: Int) async -> IndicatorSet {
        let c1m = candlesByTimeframe["1m"]!
        let c5m = candlesByTimeframe["5m"]!
        let c4h = candlesByTimeframe["4h"]!
        let cD1 = candlesByTimeframe["D1"]!
        let cW1 = candlesByTimeframe["W1"]!

        let closes = c1m.map { $0.close }
        let currentPrice = closes.last ?? 0

        // Basic RSI & ATR
        let rsi = Indicators.rsi(closes, period: 14).last ?? 50
        let atr = AdvancedIndicators.atr(c1m, period: 14).last ?? 0

        // Stochastic
        let stoch = AdvancedIndicators.stochastic(c1m, periodK: 14, periodD: 3)
        let stochK = stoch.k.last ?? 50
        let stochD = stoch.d.last ?? 50

        // Bollinger Bands
        let bb = Indicators.bollingerBands(closes, period: 20, stdDev: 2.0)
        let bbPosition = (currentPrice - (bb.lower.last ?? 0)) / max((bb.upper.last ?? 1) - (bb.lower.last ?? 0), 0.0001)

        // CCI & SAR
        let cci = AdvancedIndicators.cci(c1m, period: 20).last ?? 0
        let sar = AdvancedIndicators.parabolicSAR(c1m, acceleration: 0.02, maxAcceleration: 0.2).last ?? currentPrice

        // EMA Stack
        let ema9 = Indicators.ema(closes, period: 9).last ?? 0
        let ema21 = Indicators.ema(closes, period: 21).last ?? 0
        let ema50 = Indicators.ema(closes, period: 50).last ?? 0

        let ema9_5m = Indicators.ema(c5m.map { $0.close }, period: 9).last ?? 0
        let ema21_5m = Indicators.ema(c5m.map { $0.close }, period: 21).last ?? 0
        let ema50_5m = Indicators.ema(c5m.map { $0.close }, period: 50).last ?? 0

        // Sessions
        let sessions = AdvancedIndicators.sessionAnalysis(c1m)

        // V10.0 Precision Fields
        let (momentum, isAccel) = getMomentumScore(candles: c1m, rocPeriod: rocPeriod)
        let gaps = AdvancedIndicators.detectFairValueGaps(c1m)
        let delta = await MT5WebSocketService.shared.getDeltaVolume(for: symbol)

        return IndicatorSet(
            rsi: rsi,
            stochasticK: stochK, stochasticD: stochD,
            cci: cci, sar: sar,
            atr: atr,
            spread: c1m.last?.spread,
            ema9: ema9, ema21: ema21, ema50: ema50,
            ema9_5m: ema9_5m, ema21_5m: ema21_5m, ema50_5m: ema50_5m,
            bbPosition: bbPosition,
            volumeRatio: 1.0, volumeProfilePOC: 0,
            support: 0, resistance: 0,
            sessions: sessions,
            trendStrength: 0, pricePattern: .none, regime: .ranging,
            currentPrice: currentPrice,
            h4Trend: calculateHTFTrend(candles: c4h),
            d1Trend: calculateHTFTrend(candles: cD1),
            w1Trend: calculateHTFTrend(candles: cW1),
            momentumScore: momentum,
            isAccelerating: isAccel,
            fvgGaps: gaps,
            deltaVolume: delta
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

    private func generateSignal(symbol: String, indicators: IndicatorSet, candles1m: [Kline]) async -> ScalpingSignal {
        let (deltaThreshold, mlThreshold, newsMultiplierVal, _, pullbackEMAPeriod, weights) = await MainActor.run {
            let config = ScalpingConfig.shared
            let weights = [
                "HTF": config.weightHTFAlignment,
                "Momentum": config.weightMomentumExhaustion,
                "Volume": config.weightVolumeSurge,
                "EMA": config.weightEMAStack,
                "BB": config.weightBollingerRejection,
                "CCI": config.weightCCICycle,
                "SAR": config.weightSARTrend,
                "Accel": config.weightMomentumSurge,
                "OrderFlow": config.weightOrderFlow,
                "ML": config.weightMLConfirmed,
                "FixedSL": config.fixedSLPips
            ]
            return (config.orderFlowThreshold,
                config.mlConfidenceThreshold,
                config.newsSpreadMultiplier,
                config.swingLookback,
                config.pullbackEMAPeriod,
                weights)
        }

        var buyScore: Double = 0
        var sellScore: Double = 0
        var factors: [String: Double] = [:]

        // PILLAR 1: Institutional Trend Alignment (H4 + D1) - STRICT
        let htfWeight = weights["HTF"] ?? 25.0
        if indicators.h4Trend == .buy && indicators.d1Trend == .buy {
            buyScore += htfWeight
            factors["HTF Power Alignment"] = htfWeight
        } else if indicators.h4Trend == .sell && indicators.d1Trend == .sell {
            sellScore += htfWeight
            factors["HTF Power Alignment"] = htfWeight
        } else {
            // SKIP: Trend doesn't align with Higher Timeframe
            return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice, confidence: 0, score: 0, sellScore: 0, indicators: indicators, confidenceFactors: [:], timestamp: Date())
        }

        // PILLAR 2: Momentum & Exhaustion (RSI + Stoch)
        let momWeight = weights["Momentum"] ?? 15.0
        if indicators.rsi < 32 && indicators.stochasticK < 15 {
            buyScore += momWeight
            factors["Elite Dip Buy"] = momWeight
        } else if indicators.rsi > 68 && indicators.stochasticK > 85 {
            sellScore += momWeight
            factors["Elite Rally Sell"] = momWeight
        }

        // PILLAR 3: Institutional Volume Surge
        let volWeight = weights["Volume"] ?? 12.0
        if indicators.volumeRatio >= 1.5 {
            buyScore += volWeight
            sellScore += volWeight
            factors["Smart Money Volume"] = volWeight
        }

        // PILLAR 4: EMA Stack Confluence (M1 + M5)
        let emaWeight = weights["EMA"] ?? 18.0
        let buyStack = indicators.ema9 > indicators.ema21 && indicators.ema21 > indicators.ema50
        let sellStack = indicators.ema9 < indicators.ema21 && indicators.ema21 < indicators.ema50

        if buyStack {
            buyScore += emaWeight
            factors["Structural Support"] = emaWeight
        } else if sellStack {
            sellScore += emaWeight
            factors["Structural Resistance"] = emaWeight
        }

        // PILLAR 5: Bollinger Rejection
        let bbWeight = weights["BB"] ?? 10.0
        if indicators.bbPosition < 0.05 {
            buyScore += bbWeight
            factors["BB Lower Sweep"] = bbWeight
        } else if indicators.bbPosition > 0.95 {
            sellScore += bbWeight
            factors["BB Upper Sweep"] = bbWeight
        }

        // PILLAR 6: CCI Cycle Alignment
        let cciWeight = weights["CCI"] ?? 10.0
        if indicators.cci > 100 {
            buyScore += cciWeight
            factors["Cyclical Strength"] = cciWeight
        } else if indicators.cci < -100 {
            sellScore += cciWeight
            factors["Cyclical Strength"] = cciWeight
        }

        // PILLAR 7: SAR Trend Confirmation
        let sarWeight = weights["SAR"] ?? 10.0
        if indicators.sar < indicators.currentPrice {
            buyScore += sarWeight
            factors["SAR Support"] = sarWeight
        } else if indicators.sar > indicators.currentPrice {
            sellScore += sarWeight
            factors["SAR Resistance"] = sarWeight
        }

        // PILLAR 8: Momentum Acceleration (V10.0)
        let accelWeight = weights["Accel"] ?? 12.0
        if indicators.isAccelerating {
            if buyScore > sellScore { buyScore += accelWeight }
            else if sellScore > buyScore { sellScore += accelWeight }
            factors["Momentum Surge"] = accelWeight
        }

        // PILLAR 9: L2 Order Flow Imbalance (V10.0)
        let flowWeight = weights["OrderFlow"] ?? 15.0
        if indicators.deltaVolume > deltaThreshold {
            buyScore += flowWeight
            factors["Order Flow Buy"] = flowWeight
        } else if indicators.deltaVolume < -deltaThreshold {
            sellScore += flowWeight
            factors["Order Flow Sell"] = flowWeight
        }

        // Final Confidence Calculation
        let type: SignalType = buyScore > sellScore ? .buy : (sellScore > buyScore ? .sell : .none)
        let finalScore = type == .buy ? buyScore : sellScore

        // ELITE: Confidence is a weighted average of pillars
        var confidence = min(finalScore * 1.1, 98.0)

        // V10.0: ML Prediction Filter
        let (mlDir, mlConf) = await getMLTrendPrediction(symbol: symbol, candles: candles1m)
        let mlWeight = weights["ML"] ?? 10.0

        if mlDir == type && mlConf >= mlThreshold {
            confidence = min(confidence + (mlConf * mlWeight), 99.0)
            factors["ML Confirmed"] = mlConf * mlWeight
        } else if mlDir != .none && mlConf > (mlThreshold + 0.1) {
            confidence *= 0.7 // Penalize if ML disagrees
            factors["ML Divergence"] = -30
        }

        // News Multiplier
        let newsMultiplier = await getNewsSpreadMultiplier(symbol: symbol, configMultiplier: newsMultiplierVal)

        // V10.0: FIXED STOP LOSS (30 PIPS)
        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let slPips = weights["FixedSL"] ?? 30.0
        let sl = type == .buy ? indicators.currentPrice - (slPips * pipSize) : indicators.currentPrice + (slPips * pipSize)

        // Dynamic Take Profit (ATR Based with News Adjustment)
        let atrPips = indicators.atr / pipSize
        let tpPips = max(8.0, min(25.0, (atrPips * 2.5) * newsMultiplier))
        let tp = type == .buy ? indicators.currentPrice + (tpPips * pipSize) : indicators.currentPrice - (tpPips * pipSize)

        // V10.0: Find Optimal Entry (Pullback Logic)
        let optimalEntry = findOptimalEntry(symbol: symbol, type: type, basePrice: indicators.currentPrice, candles: candles1m, atr: indicators.atr, fvgGaps: indicators.fvgGaps, emaPeriod: pullbackEMAPeriod)

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
            volume: 0.1,
            optimalEntryPrice: optimalEntry
        )
    }

    private func validateData(_ dict: [String: [Kline]], symbol: String) -> Bool {
        return (dict["1m"]?.count ?? 0) >= 100
    }

    // MARK: - V10.0 Precision Logic

    private func findOptimalEntry(symbol: String, type: SignalType, basePrice: Double,
                                  candles: [Kline], atr: Double, fvgGaps: [FairValueGap], emaPeriod: Int) -> Double? {
        let closes = candles.map { $0.close }
        let emaVal = Indicators.ema(closes, period: emaPeriod).last ?? basePrice

        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001

        if type == .buy {
            let nearestGap = fvgGaps.filter { $0.type == .buy && $0.top < basePrice }.last?.top ?? emaVal
            let idealEntry = min(basePrice, max(emaVal, nearestGap) + (0.2 * pipSize))
            if abs(basePrice - emaVal) < atr * 1.5 { return idealEntry }
        } else if type == .sell {
            let nearestGap = fvgGaps.filter { $0.type == .sell && $0.bottom > basePrice }.last?.bottom ?? emaVal
            let idealEntry = max(basePrice, min(emaVal, nearestGap) - (0.2 * pipSize))
            if abs(basePrice - emaVal) < atr * 1.5 { return idealEntry }
        }
        return nil
    }

    private func getNewsSpreadMultiplier(symbol: String, configMultiplier: Double) async -> Double {
        let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: 30)
        switch impact {
        case .high: return configMultiplier
        case .medium: return 1.0 + ((configMultiplier - 1.0) * 0.5) // Half impact for medium news
        default: return 1.0
        }
    }

    private func getMLTrendPrediction(symbol: String, candles: [Kline]) async -> (direction: SignalType, confidence: Double) {
        let features = await mlModel.extractFeatures(symbol: symbol, candles1m: candles, candles5m: [], candles1h: [])
        guard let prediction = await mlModel.predictSignal(features: features) else {
            return (.none, 0)
        }
        let direction: SignalType = prediction.signal == .buy ? .buy : (prediction.signal == .sell ? .sell : .none)
        return (direction, prediction.confidence)
    }

    private func getSwingSL(symbol: String, type: SignalType, candles: [Kline], lookback: Int) -> Double {
        let swings = AdvancedIndicators.findStructuralSwings(candles, lookback: lookback)
        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let atr = AdvancedIndicators.atr(candles, period: 14).last ?? (15.0 * pipSize)
        let buffer = atr * 0.3

        if type == .buy {
            let low = swings.low ?? (candles.last!.close - (10 * pipSize))
            return low - buffer
        } else {
            let high = swings.high ?? (candles.last!.close + (10 * pipSize))
            return high + buffer
        }
    }

    private func getMomentumScore(candles: [Kline], rocPeriod: Int) -> (momentum: Double, isAccelerating: Bool) {
        let closes = candles.map { $0.close }
        guard closes.count >= 20 else { return (0, false) }
        let roc1 = AdvancedIndicators.calculateROC(closes, period: rocPeriod)
        let roc3 = AdvancedIndicators.calculateROC(closes, period: rocPeriod * 3)
        let roc5 = AdvancedIndicators.calculateROC(closes, period: rocPeriod * 5)
        let isAccelerating = abs(roc1) > abs(roc3) && abs(roc3) > abs(roc5)
        return (roc1, isAccelerating)
    }
}