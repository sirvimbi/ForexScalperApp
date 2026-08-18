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

    // Symbol Performance Tracking (Separated by Direction)
    private var symbolPerformance: [String: [SignalType: (wins: Int, losses: Int, pnl: Double)]] = [:]
    private let minTradesForAdaptation = 5
    private let minWinRateForTrading = 0.40

    // Strict Symbol Filter
    private let allowedSymbols = Set([
                                         "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD",
                                         "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "EURGBP", "EURCHF",
                                         "GBPCHF", "CADJPY", "CHFJPY", "AUDCHF", "NZDCAD", "AUDNZD",
                                         "BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "XAUUSD", "XAGUSD",
                                         "USOIL", "UKOIL", "US30", "NAS100", "US500", "GER30"
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

    func updateSymbolPerformance(symbol: String, direction: SignalType, pnl: Double) {
        var symbolStats = symbolPerformance[symbol] ?? [.buy: (0, 0, 0.0), .sell: (0, 0, 0.0)]
        var perf = symbolStats[direction] ?? (wins: 0, losses: 0, pnl: 0.0)
        if pnl > 0 { perf.wins += 1 } else if pnl < 0 { perf.losses += 1 }
        perf.pnl += pnl
        symbolStats[direction] = perf
        symbolPerformance[symbol] = symbolStats
    }

    private func shouldTradeSymbol(_ symbol: String, direction: SignalType) -> Bool {
        guard let symbolStats = symbolPerformance[symbol], let perf = symbolStats[direction] else { return true }
        let totalTrades = perf.wins + perf.losses
        if totalTrades < minTradesForAdaptation { return true }
        let winRate = Double(perf.wins) / Double(totalTrades)
        
        // SYMMETRIC IMPROVEMENT: Instead of blocking completely, we use winRate to adjust confidence later.
        // We only hard-block if win rate is extremely low (< 25%).
        return winRate >= 0.25
    }

    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        let started = Date()
        godLog("🧪 SIGNAL EVAL START | \(symbol) | mode=FULL | requestedTFs=1m,5m,1h,4h,D1,W1", level: .info)

        // WHITELIST CHECK
        guard allowedSymbols.contains(symbol) else {
            godLog("🛑 SIGNAL GATE | \(symbol) | FAIL | symbol not in scalping whitelist", level: .warning)
            return nil
        }

        // PERFORMANCE CHECK (Directional)
        // Note: For initial gate, we check both buy and sell collectively for general symbol health
        let totalWins = (symbolPerformance[symbol]?.values.map(\.wins).reduce(0, +) ?? 0)
        let totalLosses = (symbolPerformance[symbol]?.values.map(\.losses).reduce(0, +) ?? 0)
        let totalTrades = totalWins + totalLosses
        if totalTrades >= minTradesForAdaptation {
            let winRate = Double(totalWins) / Double(totalTrades)
            if winRate < 0.30 {
                godLog("🧠 SIGNAL CONTEXT | \(symbol) | overall historical win rate too low (\(Int(winRate * 100))%)", level: .info)
                // We don't block here anymore to remain symmetric and allow recovery
            }
        }

        // MT5 TRADABLE CHECK
        let tradable = await MT5Service.shared.isSymbolTradable(symbol)
        guard tradable else { return nil }

        // RISK MANAGER CHECK
        let riskAllowed = await riskManager.canOpenTrade(for: symbol)
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
            let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: Int(max(highMin, medMin)))
            if impact == .high {
                godLog("⚠️ \(symbol) skipped: High-impact news detected", level: .info)
                return nil
            }
        }

        // COOLDOWN CHECK
        if let lastSignal = lastSignalTime[symbol], Date().timeIntervalSince(lastSignal) < cooldown {
            return nil
        }

        godLog("📥 SIGNAL FETCH START | \(symbol)", level: .info)
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
            godLog("⚠️ \(symbol) skipped: Spread too high (\(String(format: "%.1f", actualSpread)) > \(spreadTol))", level: .info)
            return nil
        }

        // VOLATILITY CHECK
        let volatilityOK = await validateVolatility(symbol, indicators: indicators)
        guard volatilityOK else { return nil }

        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candlesByTimeframe["1m"]!)

        // V23 signal-accuracy layer
        let accuracy = SignalAccuracyEngine.assess(
            symbol: symbol,
            direction: finalSignal.type,
            candles: candlesByTimeframe["1m"]!
        )
        finalSignal = finalSignal.withSelfLearningInsight(accuracy.insight)
        guard accuracy.approved else {
            godLog("🛑 ACCURACY GATE | \(symbol) | signal held/rejected: \(accuracy.reasons.joined(separator: "; "))", level: .warning)
            return nil
        }

        // PERFORMANCE CHECK (Directional)
        if !shouldTradeSymbol(symbol, direction: finalSignal.type) {
            godLog("🛑 PERFORMANCE GATE | \(symbol) | \(finalSignal.type) blocked due to poor directional win rate", level: .warning)
            return nil
        }

        // CONFIDENCE THRESHOLD CHECK
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        logEvaluation(symbol: symbol, signal: finalSignal, threshold: threshold)

        if finalSignal.type == .none || finalSignal.confidence < threshold {
            return nil
        }

        // --- SELF-LEARNING: Apply historical performance adjustment (Directional) ---
        let adjustedSignal = await applyHistoricalAdjustment(finalSignal)

        // SYMMETRY CHECK: Check for directional bias imbalance
        let symmetry = await validateSignalSymmetry(symbol: symbol)
        let config = await MainActor.run { ScalpingConfig.shared }
        
        if config.enableDirectionalBiasCorrection {
            if symmetry.ratio > config.maxSignalRatio && adjustedSignal.type == .buy {
                godLog("⚖️ SYMMETRY | \(symbol) | Skipping BUY signal to correct balance (Ratio=\(String(format: "%.1f", symmetry.ratio * 100))%)", level: .warning)
                return nil
            } else if symmetry.ratio < config.minSignalRatio && adjustedSignal.type == .sell {
                godLog("⚖️ SYMMETRY | \(symbol) | Skipping SELL signal to correct balance (Ratio=\(String(format: "%.1f", (1 - symmetry.ratio) * 100))%)", level: .warning)
                return nil
            }
        }

        // RISK/REWARD CHECK
        let rrOK = await RRLock.validate(signal: adjustedSignal)
        guard rrOK else { return nil }

        // Track quality for self-learning
        await trackSignalQuality(adjustedSignal)

        lastSignalTime[symbol] = Date()
        godLog("🚀 HYBRID SIGNAL: \(symbol) | Confidence: \(Int(adjustedSignal.confidence))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .success)
        return adjustedSignal
    }

    /// Internal method to log detailed evaluation factors for transparency.
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
    }

    // --- FAST EVALUATION (V10.0 Early Entry) ---
    func evaluateFastSignal(symbol: String, currentPrice: Double) async -> ScalpingSignal? {
        let started = Date()
        guard allowedSymbols.contains(symbol) else { return nil }

        // 1. Quick Checks
        guard shouldTradeSymbol(symbol, direction: .none) else { return nil }
        let riskAllowed = await riskManager.canOpenTrade(for: symbol)
        guard riskAllowed else { return nil }

        // 2. Cached HTF Trend Check
        let h4Trend = await getCachedTrend(symbol: symbol, timeframe: "4h")
        let d1Trend = await getCachedTrend(symbol: symbol, timeframe: "D1")
        let htfAligned = h4Trend != .none && h4Trend == d1Trend
        guard htfAligned else { return nil }

        // 3. Fast Indicators (1m only)
        let candles1m = await marketData.getCandles(symbol: symbol, timeframe: "1m")
        guard candles1m.count >= 100 else { return nil }

        let indicators = await calculateFastIndicators(symbol: symbol, candles1m: candles1m, h4Trend: h4Trend, d1Trend: d1Trend)

        // 4. Generate & Adjust Signal
        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candles1m)
        finalSignal = await applyHistoricalAdjustment(finalSignal)

        // 5. Threshold & R:R Check
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        logEvaluation(symbol: symbol, signal: finalSignal, threshold: threshold)
        guard finalSignal.confidence >= threshold else { return nil }
        let rrOK = await RRLock.validate(signal: finalSignal)
        guard rrOK else { return nil }

        lastSignalTime[symbol] = Date()
        godLog("⚡️ FAST SIGNAL: \(symbol) | Confidence: \(Int(finalSignal.confidence))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .success)
        return finalSignal
    }

    private func getCachedTrend(symbol: String, timeframe: String) async -> SignalType {
        if let cached = cachedHTFTrends[symbol]?[timeframe],
           Date().timeIntervalSince(cached.timestamp) < htfCacheDuration {
            return cached.trend
        }

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
        guard qualityHistory.count >= 5 else { return signal }

        let similarSignals = qualityHistory.filter {
            abs($0.confidence - signal.confidence) < 15 && $0.type == signal.type
        }

        let wins = similarSignals.compactMap { $0.wasWin }.filter { $0 }.count
        let total = similarSignals.compactMap { $0.wasWin }.count

        if total > 0 {
            let winRate = Double(wins) / Double(total)
            // SYMMETRIC FIX: Apply adjustment factor based on directional win rate
            let adjustmentFactor = 0.6 + (winRate * 0.4) // Range 0.6 to 1.0
            let adjustedConfidence = signal.confidence * adjustmentFactor
            return signal.withConfidence(adjustedConfidence)
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
        
        _ = await validateSignalSymmetry(symbol: signal.symbol)
    }

    func validateSignalSymmetry(symbol: String) async -> (buyCount: Int, sellCount: Int, ratio: Double) {
        let history = signalQualityHistory[symbol] ?? []
        let buySignals = history.filter { $0.type == .buy }.count
        let sellSignals = history.filter { $0.type == .sell }.count
        let total = max(1, buySignals + sellSignals)
        let ratio = Double(buySignals) / Double(total)
        
        godLog("⚖️ SIGNAL SYMMETRY | \(symbol) | BUY=\(buySignals) SELL=\(sellSignals) | Ratio=\(String(format: "%.2f", ratio))", 
               level: (ratio > 0.7 || ratio < 0.3) ? .warning : .info)
        
        return (buySignals, sellSignals, ratio)
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
            tracePillar(symbol: symbol, pillar: "HTF Power Alignment", passed: false, detail: "H4=\(indicators.h4Trend) D1=\(indicators.d1Trend) — mixed trend skipped", contribution: 0, buyScore: buyScore, sellScore: sellScore)
            return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice, confidence: 0, score: 0, sellScore: 0, indicators: indicators, confidenceFactors: [:], timestamp: Date())
        }

        // PILLAR 2: Momentum & Exhaustion (RSI + Stoch)
        let momWeight = weights["Momentum"] ?? 15.0
        let dipBuy = indicators.rsi < 32 && indicators.stochasticK < 15
        let rallySell = indicators.rsi > 68 && indicators.stochasticK > 85
        if dipBuy {
            buyScore += momWeight
            factors["Elite Dip Buy"] = momWeight
        } else if rallySell {
            sellScore += momWeight
            factors["Elite Rally Sell"] = momWeight
        }

        // PILLAR 3: Institutional Volume Surge
        let volWeight = weights["Volume"] ?? 12.0
        let volumePass = indicators.volumeRatio >= 1.5
        if volumePass {
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

        // PILLAR 5: Bollinger Rejection (SYMMETRIC)
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

        // PILLAR 6: CCI Cycle Alignment (SYMMETRIC)
        let cciWeight = weights["CCI"] ?? 10.0
        let cciBuy = indicators.cci > 100
        let cciSell = indicators.cci < -100
        if cciBuy {
            buyScore += cciWeight
            factors["CCI Bullish Momentum"] = cciWeight
        } else if cciSell {
            sellScore += cciWeight
            factors["CCI Bearish Momentum"] = cciWeight
        }

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

        // PILLAR 8: Momentum Acceleration (SYMMETRIC FIX)
        let accelWeight = weights["Accel"] ?? 12.0
        let momentumDirection: SignalType =
            indicators.momentumScore > 0.001 ? .buy :
            (indicators.momentumScore < -0.001 ? .sell : .none)
            
        if indicators.isAccelerating {
            if momentumDirection == .buy {
                buyScore += accelWeight
                factors["Momentum Surge Buy"] = accelWeight
            } else if momentumDirection == .sell {
                sellScore += accelWeight
                factors["Momentum Surge Sell"] = accelWeight
            }
        }

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

        // Final Confidence Calculation
        let type: SignalType = buyScore > sellScore ? .buy : (sellScore > buyScore ? .sell : .none)
        let finalScore = type == .buy ? buyScore : sellScore
        var confidence = min(finalScore * 1.1, 98.0)

        // V10.0: ML Prediction Filter
        let (mlDir, mlConf) = await getMLTrendPrediction(symbol: symbol, candles: candles1m)
        let mlWeight = weights["ML"] ?? 10.0

        if mlDir == type && mlConf >= mlThreshold {
            confidence = min(confidence + (mlConf * mlWeight), 99.0)
            factors["ML Confirmed"] = mlConf * mlWeight
        } else if mlDir != .none && mlConf > (mlThreshold + 0.1) {
            confidence *= 0.7
            factors["ML Divergence"] = -30
        }

        // V10.0: FIXED STOP LOSS
        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let slPips = weights["FixedSL"] ?? 30.0
        let sl = type == .buy ? indicators.currentPrice - (slPips * pipSize) : indicators.currentPrice + (slPips * pipSize)

        // Dynamic Take Profit
        let atrPips = indicators.atr / pipSize
        let tpPips = max(8.0, min(25.0, atrPips * 2.5))
        let tp = type == .buy ? indicators.currentPrice + (tpPips * pipSize) : indicators.currentPrice - (tpPips * pipSize)

        // Optimal Entry
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

    private func getMLTrendPrediction(symbol: String, candles: [Kline]) async -> (direction: SignalType, confidence: Double) {
        let features = await mlModel.extractFeatures(symbol: symbol, candles1m: candles, candles5m: [], candles1h: [])
        guard let prediction = await mlModel.predictSignal(features: features) else { return (.none, 0) }
        let direction: SignalType = prediction.signal == .buy ? .buy : (prediction.signal == .sell ? .sell : .none)
        return (direction, prediction.confidence)
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
