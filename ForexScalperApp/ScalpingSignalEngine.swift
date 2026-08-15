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
        let started = Date()
        godLog("🧪 SIGNAL EVAL START | \(symbol) | mode=FULL | requestedTFs=1m,5m,1h,4h,D1,W1", level: .info)

        // WHITELIST CHECK
        guard allowedSymbols.contains(symbol) else {
            godLog("🛑 SIGNAL GATE | \(symbol) | FAIL | symbol not in scalping whitelist", level: .warning)
            return nil
        }

        // PERFORMANCE CHECK (Informational only)
        var learningWarning: String? = nil
        if !shouldTradeSymbol(symbol) {
            let perf = symbolPerformance[symbol]!
            let wr = Double(perf.wins) / Double(perf.wins + perf.losses)
            learningWarning = "Historical Win Rate is only \(Int(wr*100))%"
            godLog("🧠 SIGNAL CONTEXT | \(symbol) | historical win rate=\(Int(wr * 100))% | warning only", level: .info)
        }

        // MT5 TRADABLE CHECK
        let tradable = await MT5Service.shared.isSymbolTradable(symbol)
        godLog("🧱 SIGNAL GATE | \(symbol) | MT5 tradable=\(tradable)", level: .info)
        guard tradable else { return nil }

        // RISK MANAGER CHECK
        let riskAllowed = await riskManager.canOpenTrade(for: symbol)
        godLog("🧱 SIGNAL GATE | \(symbol) | riskManager.canOpenTrade=\(riskAllowed)", level: .info)
        guard riskAllowed else { return nil }

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
            godLog("📡 SIGNAL FETCH | \(symbol) | news impact request started", level: .info)
            let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: Int(max(highMin, medMin)))
            godLog("📡 SIGNAL FETCH | \(symbol) | news impact=\(impact)", level: .info)
            if impact == .high {
                godLog("⚠️ \(symbol) skipped: High-impact news detected", level: .info)
                return nil
            }
        } else {
            godLog("📡 SIGNAL FETCH | \(symbol) | news filter disabled", level: .info)
        }

        // COOLDOWN CHECK
        if let lastSignal = lastSignalTime[symbol], Date().timeIntervalSince(lastSignal) < cooldown {
            let remaining = Int(ceil(cooldown - Date().timeIntervalSince(lastSignal)))
            godLog("⏱ SIGNAL GATE | \(symbol) | FAIL | cooldown active | remaining=\(remaining)s", level: .info)
            return nil
        }

        godLog("📥 SIGNAL FETCH START | \(symbol) | parallel candle tasks=1m,5m,1h,4h,D1,W1", level: .info)
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
        godLog("📥 SIGNAL FETCH DONE | \(symbol) | counts=1m:\(candlesByTimeframe["1m"]?.count ?? 0),5m:\(candlesByTimeframe["5m"]?.count ?? 0),1h:\(candlesByTimeframe["1h"]?.count ?? 0),4h:\(candlesByTimeframe["4h"]?.count ?? 0),D1:\(candlesByTimeframe["D1"]?.count ?? 0),W1:\(candlesByTimeframe["W1"]?.count ?? 0)", level: .info)

        // DATA VALIDATION CHECK
        guard validateData(candlesByTimeframe, symbol: symbol) else {
            godLog("⚠️ \(symbol) skipped: Insufficient history (need 100 1m candles)", level: .info)
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

        godLog("📏 SIGNAL PILLAR | \(symbol) | Spread | \(String(format: "%.2f", actualSpread)) <= \(String(format: "%.2f", spreadTol))", level: .info)
        if actualSpread > spreadTol {
            godLog("⚠️ \(symbol) skipped: Spread too high (\(String(format: "%.1f", actualSpread)) > \(spreadTol))", level: .info)
            return nil
        }

        // VOLATILITY CHECK
        let atrPercentage = indicators.atr / indicators.currentPrice * 100
        let volatilityOK = await validateVolatility(symbol, indicators: indicators)
        godLog("📏 SIGNAL PILLAR | \(symbol) | Volatility | ATR=\(String(format: "%.3f", atrPercentage))% | \(volatilityOK ? "PASS" : "FAIL")", level: .info)
        guard volatilityOK else {
            godLog("⚠️ \(symbol) skipped: Volatility outside bounds (\(String(format: "%.3f", atrPercentage))%)", level: .info)
            return nil
        }

        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candlesByTimeframe["1m"]!)

        // V23 signal-accuracy layer: regime, divergence and micro-reversal confirmation.
        // This remains on the engine's isolation domain; it does not cross an actor boundary.
        let accuracy = SignalAccuracyEngine.assess(
            symbol: symbol,
            direction: finalSignal.type,
            candles: candlesByTimeframe["1m"]!
        )
        godLog("🧠 ACCURACY CHECK | \(symbol) | approved=\(accuracy.approved) | regime=\(accuracy.regime) | H=\(String(format: "%.2f", accuracy.hurst)) | chop=\(String(format: "%.1f", accuracy.choppiness)) | \(accuracy.reasons.joined(separator: "; "))", level: accuracy.approved ? .info : .warning)
        finalSignal = finalSignal.withSelfLearningInsight(accuracy.insight)
        guard accuracy.approved else {
            godLog("🛑 ACCURACY GATE | \(symbol) | signal held/rejected pending better price action", level: .warning)
            return nil
        }
        if let warning = learningWarning {
            finalSignal = finalSignal.withSelfLearningInsight(warning)
        }

        // CONFIDENCE THRESHOLD CHECK
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        logEvaluation(symbol: symbol, signal: finalSignal, threshold: threshold)

        if finalSignal.type == .none || finalSignal.confidence < threshold {
            godLog("🛑 SIGNAL DECISION | \(symbol) | REJECTED | type=\(finalSignal.type) | confidence=\(Int(finalSignal.confidence))% | threshold=\(Int(threshold))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .warning)
            return nil
        }

        // --- SELF-LEARNING: Apply historical performance adjustment ---
        let adjustedSignal = await applyHistoricalAdjustment(finalSignal)

        if adjustedSignal.confidence < threshold {
            let warning = "Self-Learning adjusted confidence from \(Int(finalSignal.confidence))% to \(Int(adjustedSignal.confidence))% (Win Rate < 50%)"
            godLog("🧠 SIGNAL ADJUSTMENT | \(symbol) | \(warning)", level: .info)
            // We don't block anymore, but we keep the insight
            return adjustedSignal.withSelfLearningInsight(warning)
        }

        // RISK/REWARD CHECK
        let rrOK = await RRLock.validate(signal: adjustedSignal)
        godLog("⚖️ SIGNAL GATE | \(symbol) | R:R=\(rrOK ? "PASS" : "FAIL")", level: .info)
        guard rrOK else {
            godLog("⚠️ \(symbol) skipped: Risk/Reward check failed", level: .info)
            return nil
        }

        // Track quality for self-learning
        await trackSignalQuality(adjustedSignal)

        lastSignalTime[symbol] = Date()
        godLog("🚀 HYBRID SIGNAL: \(symbol) | Confidence: \(Int(adjustedSignal.confidence))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .success)
        return adjustedSignal
    }

    /// Internal method to log detailed evaluation factors for transparency.
    /// This is observational only; it does not alter scoring or decision rules.
    private func logEvaluation(symbol: String, signal: ScalpingSignal, threshold: Double) {
        let metPillars = signal.confidenceFactors.keys.sorted()
        let allPillars = [
            "HTF Power Alignment", "Elite Dip Buy", "Elite Rally Sell", "Smart Money Volume",
            "Structural Support", "Structural Resistance", "BB Lower Sweep", "BB Upper Sweep",
            "Cyclical Strength", "SAR Support", "SAR Resistance", "Momentum Surge",
            "ML Confirmed", "ML Divergence", "Order Flow Buy", "Order Flow Sell"
        ]

        let metString = metPillars.isEmpty ? "none" : metPillars.map { "✅ \($0)" }.joined(separator: ", ")
        let failedString = allPillars.filter { !metPillars.contains($0) }.map { "❌ \($0)" }.joined(separator: ", ")

        let logMsg = "📊 EVAL: \(symbol) \(signal.type) | Conf: \(Int(signal.confidence))% (Need \(Int(threshold))%) | Score: B=\(signal.score) S=\(signal.sellScore) | MET: [\(metString)] | FAILED: [\(failedString)]"
        godLog(logMsg, level: .info)
        godLog("🧭 SIGNAL DECISION TRACE | \(symbol) | direction=\(signal.type) | confidence=\(String(format: "%.1f", signal.confidence))% | threshold=\(String(format: "%.1f", threshold))% | pillarsPassed=\(metPillars.count)/\(allPillars.count)", level: .info)
    }

    // --- FAST EVALUATION (V10.0 Early Entry) ---
    func evaluateFastSignal(symbol: String, currentPrice: Double) async -> ScalpingSignal? {
        let started = Date()
        godLog("⚡ FAST SIGNAL START | \(symbol) | price=\(String(format: "%.5f", currentPrice))", level: .info)
        guard allowedSymbols.contains(symbol) else {
            godLog("🛑 FAST SIGNAL GATE | \(symbol) | FAIL | not in whitelist", level: .warning)
            return nil
        }

        // 1. Performance/Tradable/Risk Checks (Quick)
        let learningAllowed = shouldTradeSymbol(symbol)
        godLog("🧱 FAST GATE | \(symbol) | historical-performance=\(learningAllowed ? "PASS" : "WARN")", level: .info)
        guard learningAllowed else { return nil }
        let riskAllowed = await riskManager.canOpenTrade(for: symbol)
        godLog("🧱 FAST GATE | \(symbol) | riskManager=\(riskAllowed ? "PASS" : "FAIL")", level: .info)
        guard riskAllowed else { return nil }

        // 2. Cached HTF Trend Check
        let h4Trend = await getCachedTrend(symbol: symbol, timeframe: "4h")
        let d1Trend = await getCachedTrend(symbol: symbol, timeframe: "D1")
        let htfAligned = h4Trend != .none && h4Trend == d1Trend
        godLog("🔎 FAST PILLAR | \(symbol) | HTF Alignment | H4=\(h4Trend) D1=\(d1Trend) | \(htfAligned ? "PASS" : "FAIL")", level: .info)
        guard htfAligned else { return nil }

        // 3. Fast Indicators (1m only)
        godLog("📥 FAST FETCH | \(symbol) | 1m candles", level: .info)
        let candles1m = await marketData.getCandles(symbol: symbol, timeframe: "1m")
        godLog("📥 FAST FETCH DONE | \(symbol) | 1m count=\(candles1m.count)", level: .info)
        guard candles1m.count >= 100 else {
            godLog("🛑 FAST GATE | \(symbol) | FAIL | need 100 1m candles", level: .warning)
            return nil
        }

        let indicators = await calculateFastIndicators(symbol: symbol, candles1m: candles1m, h4Trend: h4Trend, d1Trend: d1Trend)

        // 4. Generate & Adjust Signal
        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candles1m)
        finalSignal = await applyHistoricalAdjustment(finalSignal)

        // 5. Threshold & R:R Check
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        logEvaluation(symbol: symbol, signal: finalSignal, threshold: threshold)
        guard finalSignal.confidence >= threshold else {
            godLog("🛑 FAST SIGNAL DECISION | \(symbol) | REJECTED | confidence=\(Int(finalSignal.confidence))% < \(Int(threshold))%", level: .warning)
            return nil
        }
        let rrOK = await RRLock.validate(signal: finalSignal)
        godLog("⚖️ FAST GATE | \(symbol) | R:R=\(rrOK ? "PASS" : "FAIL")", level: .info)
        guard rrOK else { return nil }

        lastSignalTime[symbol] = Date()
        godLog("⚡️ FAST SIGNAL: \(symbol) | Confidence: \(Int(finalSignal.confidence))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .success)
        return finalSignal
    }

    private func getCachedTrend(symbol: String, timeframe: String) async -> SignalType {
        if let cached = cachedHTFTrends[symbol]?[timeframe],
           Date().timeIntervalSince(cached.timestamp) < htfCacheDuration {
            godLog("🗃 HTF CACHE | \(symbol) | \(timeframe) | trend=\(cached.trend) | age=\(Int(Date().timeIntervalSince(cached.timestamp)))s", level: .info)
            return cached.trend
        }

        // Refresh cache
        godLog("📥 HTF FETCH | \(symbol) | \(timeframe) | cache miss", level: .info)
        let candles = await marketData.getCandles(symbol: symbol, timeframe: timeframe)
        let trend = calculateHTFTrend(candles: candles)

        if cachedHTFTrends[symbol] == nil { cachedHTFTrends[symbol] = [:] }
        cachedHTFTrends[symbol]?[timeframe] = (trend: trend, timestamp: Date())
        godLog("🗃 HTF CACHE WRITE | \(symbol) | \(timeframe) | candles=\(candles.count) | trend=\(trend)", level: .info)

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

        godLog("📊 FAST INDICATORS | \(symbol) | RSI=\(String(format: "%.1f", rsi)) Stoch=\(String(format: "%.1f", stoch.k.last ?? 50)) BB=\(String(format: "%.3f", bbPos)) ATR=\(String(format: "%.5f", atr)) ΔVol=\(String(format: "%.2f", delta))", level: .info)

        return IndicatorSet(
            rsi: rsi, stochasticK: stoch.k.last ?? 50, stochasticD: stoch.d.last ?? 50,
            cci: 0, sar: currentPrice, atr: atr, spread: candles1m.last?.spread,
            ema9: ema9, ema21: ema21, ema50: ema50,
            ema9_5m: ema9, ema21_5m: ema21, ema50_5m: ema50,
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
        if hour >= 0 && hour < 8 { minVol = 0.005 }
        else if hour >= 16 { minVol = 0.010 }

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

        let rsi = Indicators.rsi(closes, period: 14).last ?? 50
        let atr = AdvancedIndicators.atr(c1m, period: 14).last ?? 0
        let stoch = AdvancedIndicators.stochastic(c1m, periodK: 14, periodD: 3)
        let stochK = stoch.k.last ?? 50
        let stochD = stoch.d.last ?? 50
        let bb = Indicators.bollingerBands(closes, period: 20, stdDev: 2.0)
        let bbPosition = (currentPrice - (bb.lower.last ?? 0)) / max((bb.upper.last ?? 1) - (bb.lower.last ?? 0), 0.0001)
        let cci = AdvancedIndicators.cci(c1m, period: 20).last ?? 0
        let sar = AdvancedIndicators.parabolicSAR(c1m, acceleration: 0.02, maxAcceleration: 0.2).last ?? currentPrice
        let ema9 = Indicators.ema(closes, period: 9).last ?? 0
        let ema21 = Indicators.ema(closes, period: 21).last ?? 0
        let ema50 = Indicators.ema(closes, period: 50).last ?? 0
        let ema9_5m = Indicators.ema(c5m.map { $0.close }, period: 9).last ?? 0
        let ema21_5m = Indicators.ema(c5m.map { $0.close }, period: 21).last ?? 0
        let ema50_5m = Indicators.ema(c5m.map { $0.close }, period: 50).last ?? 0
        let sessions = AdvancedIndicators.sessionAnalysis(c1m)
        let (momentum, isAccel) = getMomentumScore(candles: c1m, rocPeriod: rocPeriod)
        let gaps = AdvancedIndicators.detectFairValueGaps(c1m)
        let delta = await MT5WebSocketService.shared.getDeltaVolume(for: symbol)

        godLog("📊 INDICATORS | \(symbol) | price=\(String(format: "%.5f", currentPrice)) RSI=\(String(format: "%.1f", rsi)) StochK=\(String(format: "%.1f", stochK)) CCI=\(String(format: "%.1f", cci)) BB=\(String(format: "%.3f", bbPosition)) SAR=\(String(format: "%.5f", sar)) ATR=\(String(format: "%.5f", atr)) EMA=\(String(format: "%.5f", ema9))/\(String(format: "%.5f", ema21))/\(String(format: "%.5f", ema50)) ΔVol=\(String(format: "%.2f", delta))", level: .info)

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

    private func tracePillar(symbol: String, pillar: String, passed: Bool, detail: String, contribution: Double, buyScore: Double, sellScore: Double) {
        let status = passed ? "✅ PASS" : "❌ FAIL"
        godLog("🔎 SIGNAL PILLAR | \(symbol) | \(status) | \(pillar) | \(detail) | +\(String(format: "%.1f", contribution)) | scores B=\(String(format: "%.1f", buyScore)) S=\(String(format: "%.1f", sellScore))", level: .info)
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
            tracePillar(symbol: symbol, pillar: "HTF Power Alignment", passed: true, detail: "H4=BUY D1=BUY", contribution: htfWeight, buyScore: buyScore, sellScore: sellScore)
        } else if indicators.h4Trend == .sell && indicators.d1Trend == .sell {
            sellScore += htfWeight
            factors["HTF Power Alignment"] = htfWeight
            tracePillar(symbol: symbol, pillar: "HTF Power Alignment", passed: true, detail: "H4=SELL D1=SELL", contribution: htfWeight, buyScore: buyScore, sellScore: sellScore)
        } else {
            tracePillar(symbol: symbol, pillar: "HTF Power Alignment", passed: false, detail: "H4=\(indicators.h4Trend) D1=\(indicators.d1Trend) — strict alignment required", contribution: 0, buyScore: buyScore, sellScore: sellScore)
            return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice, confidence: 0, score: 0, sellScore: 0, indicators: indicators, confidenceFactors: [:], timestamp: Date())
        }

        // PILLAR 2: Momentum & Exhaustion (RSI + Stoch)
        let momWeight = weights["Momentum"] ?? 15.0
        let dipBuy = indicators.rsi < 32 && indicators.stochasticK < 15
        let rallySell = indicators.rsi > 68 && indicators.stochasticK > 85
        if dipBuy {
            buyScore += momWeight
            factors["Elite Dip Buy"] = momWeight
            tracePillar(symbol: symbol, pillar: "Momentum / Exhaustion", passed: true, detail: "Elite Dip Buy RSI=\(String(format: "%.1f", indicators.rsi)) StochK=\(String(format: "%.1f", indicators.stochasticK))", contribution: momWeight, buyScore: buyScore, sellScore: sellScore)
        } else if rallySell {
            sellScore += momWeight
            factors["Elite Rally Sell"] = momWeight
            tracePillar(symbol: symbol, pillar: "Momentum / Exhaustion", passed: true, detail: "Elite Rally Sell RSI=\(String(format: "%.1f", indicators.rsi)) StochK=\(String(format: "%.1f", indicators.stochasticK))", contribution: momWeight, buyScore: buyScore, sellScore: sellScore)
        } else {
            tracePillar(symbol: symbol, pillar: "Momentum / Exhaustion", passed: false, detail: "RSI=\(String(format: "%.1f", indicators.rsi)) StochK=\(String(format: "%.1f", indicators.stochasticK)) — neither extreme matched", contribution: 0, buyScore: buyScore, sellScore: sellScore)
        }

        // PILLAR 3: Institutional Volume Surge
        let volWeight = weights["Volume"] ?? 12.0
        let volumePass = indicators.volumeRatio >= 1.5
        if volumePass {
            buyScore += volWeight
            sellScore += volWeight
            factors["Smart Money Volume"] = volWeight
        }
        tracePillar(symbol: symbol, pillar: "Smart Money Volume", passed: volumePass, detail: "ratio=\(String(format: "%.2f", indicators.volumeRatio)) threshold=1.50", contribution: volumePass ? volWeight : 0, buyScore: buyScore, sellScore: sellScore)

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
        tracePillar(symbol: symbol, pillar: "EMA Stack Confluence", passed: buyStack || sellStack, detail: "M1 EMA9/21/50=\(String(format: "%.5f", indicators.ema9))/\(String(format: "%.5f", indicators.ema21))/\(String(format: "%.5f", indicators.ema50)) | direction=\(buyStack ? "BUY" : sellStack ? "SELL" : "NONE")", contribution: (buyStack || sellStack) ? emaWeight : 0, buyScore: buyScore, sellScore: sellScore)

        // PILLAR 5: Bollinger Rejection
        let bbWeight = weights["BB"] ?? 10.0
        let bbBuy = indicators.bbPosition < 0.05
        let bbSell = indicators.bbPosition > 0.95
        if bbBuy {
            buyScore += bbWeight
            factors["BB Lower Sweep"] = bbWeight
        } else if bbSell {
            sellScore += bbWeight
            factors["BB Upper Sweep"] = bbWeight
        }
        tracePillar(symbol: symbol, pillar: "Bollinger Rejection", passed: bbBuy || bbSell, detail: "position=\(String(format: "%.3f", indicators.bbPosition))", contribution: (bbBuy || bbSell) ? bbWeight : 0, buyScore: buyScore, sellScore: sellScore)

        // PILLAR 6: CCI Cycle Alignment
        let cciWeight = weights["CCI"] ?? 10.0
        let cciBuy = indicators.cci > 100
        let cciSell = indicators.cci < -100
        if cciBuy {
            buyScore += cciWeight
            factors["Cyclical Strength"] = cciWeight
        } else if cciSell {
            sellScore += cciWeight
            factors["Cyclical Strength"] = cciWeight
        }
        tracePillar(symbol: symbol, pillar: "CCI Cycle Alignment", passed: cciBuy || cciSell, detail: "CCI=\(String(format: "%.1f", indicators.cci))", contribution: (cciBuy || cciSell) ? cciWeight : 0, buyScore: buyScore, sellScore: sellScore)

        // PILLAR 7: SAR Trend Confirmation
        let sarWeight = weights["SAR"] ?? 10.0
        let sarBuy = indicators.sar < indicators.currentPrice
        let sarSell = indicators.sar > indicators.currentPrice
        if sarBuy {
            buyScore += sarWeight
            factors["SAR Support"] = sarWeight
        } else if sarSell {
            sellScore += sarWeight
            factors["SAR Resistance"] = sarWeight
        }
        tracePillar(symbol: symbol, pillar: "SAR Trend Confirmation", passed: sarBuy || sarSell, detail: "SAR=\(String(format: "%.5f", indicators.sar)) price=\(String(format: "%.5f", indicators.currentPrice))", contribution: (sarBuy || sarSell) ? sarWeight : 0, buyScore: buyScore, sellScore: sellScore)

        // PILLAR 8: Momentum Acceleration (V10.0)
        let accelWeight = weights["Accel"] ?? 12.0
        if indicators.isAccelerating {
            if buyScore > sellScore { buyScore += accelWeight }
            else if sellScore > buyScore { sellScore += accelWeight }
            factors["Momentum Surge"] = accelWeight
        }
        tracePillar(symbol: symbol, pillar: "Momentum Surge", passed: indicators.isAccelerating, detail: "accelerating=\(indicators.isAccelerating) ROC=\(String(format: "%.4f", indicators.momentumScore))", contribution: indicators.isAccelerating ? accelWeight : 0, buyScore: buyScore, sellScore: sellScore)

        // PILLAR 9: L2 Order Flow Imbalance (V10.0)
        let flowWeight = weights["OrderFlow"] ?? 15.0
        let flowBuy = indicators.deltaVolume > deltaThreshold
        let flowSell = indicators.deltaVolume < -deltaThreshold
        if flowBuy {
            buyScore += flowWeight
            factors["Order Flow Buy"] = flowWeight
        } else if flowSell {
            sellScore += flowWeight
            factors["Order Flow Sell"] = flowWeight
        }
        tracePillar(symbol: symbol, pillar: "L2 Order Flow", passed: flowBuy || flowSell, detail: "ΔVol=\(String(format: "%.2f", indicators.deltaVolume)) threshold=±\(String(format: "%.2f", deltaThreshold))", contribution: (flowBuy || flowSell) ? flowWeight : 0, buyScore: buyScore, sellScore: sellScore)

        // Final Confidence Calculation
        let type: SignalType = buyScore > sellScore ? .buy : (sellScore > buyScore ? .sell : .none)
        let finalScore = type == .buy ? buyScore : sellScore
        var confidence = min(finalScore * 1.1, 98.0)
        godLog("🎯 SIGNAL SCORE | \(symbol) | direction=\(type) | buyScore=\(String(format: "%.1f", buyScore)) | sellScore=\(String(format: "%.1f", sellScore)) | baseConfidence=\(String(format: "%.1f", confidence))%", level: .info)

        // V10.0: ML Prediction Filter
        godLog("🤖 ML REQUEST | \(symbol) | feature extraction + prediction", level: .info)
        let (mlDir, mlConf) = await getMLTrendPrediction(symbol: symbol, candles: candles1m)
        let mlWeight = weights["ML"] ?? 10.0

        if mlDir == type && mlConf >= mlThreshold {
            confidence = min(confidence + (mlConf * mlWeight), 99.0)
            factors["ML Confirmed"] = mlConf * mlWeight
            tracePillar(symbol: symbol, pillar: "ML Confirmation", passed: true, detail: "direction=\(mlDir) confidence=\(String(format: "%.1f", mlConf))% threshold=\(String(format: "%.1f", mlThreshold))%", contribution: mlConf * mlWeight, buyScore: buyScore, sellScore: sellScore)
        } else if mlDir != .none && mlConf > (mlThreshold + 0.1) {
            confidence *= 0.7
            factors["ML Divergence"] = -30
            tracePillar(symbol: symbol, pillar: "ML Confirmation", passed: false, detail: "direction=\(mlDir) confidence=\(String(format: "%.1f", mlConf))% disagrees with engine=\(type)", contribution: -30, buyScore: buyScore, sellScore: sellScore)
        } else {
            tracePillar(symbol: symbol, pillar: "ML Confirmation", passed: false, detail: "direction=\(mlDir) confidence=\(String(format: "%.1f", mlConf))% below/absent threshold=\(String(format: "%.1f", mlThreshold))%", contribution: 0, buyScore: buyScore, sellScore: sellScore)
        }

        // News Multiplier
        godLog("📡 NEWS MULTIPLIER REQUEST | \(symbol)", level: .info)
        let newsMultiplier = await getNewsSpreadMultiplier(symbol: symbol, configMultiplier: newsMultiplierVal)
        godLog("📡 NEWS MULTIPLIER RESULT | \(symbol) | multiplier=\(String(format: "%.2f", newsMultiplier))", level: .info)

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

        godLog("🧮 SIGNAL OUTPUT | \(symbol) | type=\(type) confidence=\(String(format: "%.1f", confidence))% SL=\(String(format: "%.5f", sl)) TP=\(String(format: "%.5f", tp)) entry=\(optimalEntry.map { String(format: "%.5f", $0) } ?? "market")", level: .info)

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
        case .medium: return 1.0 + ((configMultiplier - 1.0) * 0.5)
        default: return 1.0
        }
    }

    private func getMLTrendPrediction(symbol: String, candles: [Kline]) async -> (direction: SignalType, confidence: Double) {
        let features = await mlModel.extractFeatures(symbol: symbol, candles1m: candles, candles5m: [], candles1h: [])
        guard let prediction = await mlModel.predictSignal(features: features) else {
            godLog("🤖 ML RESULT | \(symbol) | no prediction returned", level: .warning)
            return (.none, 0)
        }
        let direction: SignalType = prediction.signal == .buy ? .buy : (prediction.signal == .sell ? .sell : .none)
        godLog("🤖 ML RESULT | \(symbol) | direction=\(direction) confidence=\(String(format: "%.1f", prediction.confidence))%", level: .info)
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
