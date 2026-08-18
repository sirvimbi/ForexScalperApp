// ScalpingSignalEngine.swift - GOD MODE V7.1 ELITE (Symmetric Direction + Full Candle Validation)
import Foundation

actor ScalpingSignalEngine {
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol
    private let mlModel: MLModelHandler

    private let timeframes = ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"]
    private var lastSignalTime: [String: Date] = [:]
    private var cachedHTFTrends: [String: [String: (trend: SignalType, timestamp: Date)]] = [:]
    private let htfCacheDuration: TimeInterval = 300

    private var signalQualityHistory: [String: [SignalQuality]] = [:]
    private let maxQualityHistory = 100
    private var symbolPerformance: [String: [SignalType: (wins: Int, losses: Int, pnl: Double)]] = [:]
    private let minTradesForAdaptation = 5

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
        var stats = symbolPerformance[symbol] ?? [.buy: (0, 0, 0), .sell: (0, 0, 0)]
        var perf = stats[direction] ?? (wins: 0, losses: 0, pnl: 0)
        if pnl > 0 { perf.wins += 1 } else if pnl < 0 { perf.losses += 1 }
        perf.pnl += pnl
        stats[direction] = perf
        symbolPerformance[symbol] = stats
    }

    private func shouldTradeSymbol(_ symbol: String, direction: SignalType) -> Bool {
        guard let perf = symbolPerformance[symbol]?[direction] else { return true }
        let total = perf.wins + perf.losses
        guard total >= minTradesForAdaptation else { return true }
        return Double(perf.wins) / Double(total) >= 0.25
    }

    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        let started = Date()
        godLog("🧪 SIGNAL EVAL START | \(symbol) | mode=FULL-SYMMETRIC", level: .info)

        guard allowedSymbols.contains(symbol) else {
            godLog("🛑 SIGNAL GATE | \(symbol) | symbol not in scalping whitelist", level: .warning)
            return nil
        }

        guard await MT5Service.shared.isSymbolTradable(symbol) else {
            godLog("🛑 SIGNAL GATE | \(symbol) | MT5 symbol not tradable", level: .warning)
            return nil
        }

        // Risk is deliberately not used to choose direction. Execution performs the authoritative risk gate.
        _ = await riskManager.canOpenTrade(for: symbol)

        let (enabledNews, highMin, medMin, cooldown, spreadTol, rocPeriod) = await MainActor.run {
            let config = ScalpingConfig.shared
            return (config.enableNewsFilter, config.pauseBeforeHighImpactMinutes,
                    config.pauseBeforeMediumImpactMinutes, config.cooldownSeconds,
                    config.spreadTolerance, config.rocPeriod)
        }

        if enabledNews {
            let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: Int(max(highMin, medMin)))
            if impact == .high {
                godLog("⚠️ \(symbol) skipped: High-impact news detected", level: .info)
                return nil
            }
        }

        if let lastSignal = lastSignalTime[symbol], Date().timeIntervalSince(lastSignal) < cooldown {
            godLog("⏳ \(symbol) skipped: signal cooldown active", level: .info)
            return nil
        }

        godLog("📥 SIGNAL FETCH START | \(symbol) | timeframes=\(timeframes.joined(separator: ","))", level: .info)
        async let c1m = marketData.getCandles(symbol: symbol, timeframe: "1m")
        async let c5m = marketData.getCandles(symbol: symbol, timeframe: "5m")
        async let c15m = marketData.getCandles(symbol: symbol, timeframe: "15m")
        async let c30m = marketData.getCandles(symbol: symbol, timeframe: "30m")
        async let c1h = marketData.getCandles(symbol: symbol, timeframe: "1h")
        async let c4h = marketData.getCandles(symbol: symbol, timeframe: "4h")
        async let cD1 = marketData.getCandles(symbol: symbol, timeframe: "D1")
        async let cW1 = marketData.getCandles(symbol: symbol, timeframe: "W1")

        let candlesByTimeframe = await [
            "1m": c1m, "5m": c5m, "15m": c15m, "30m": c30m,
            "1h": c1h, "4h": c4h, "D1": cD1, "W1": cW1
        ]

        guard validateData(candlesByTimeframe, symbol: symbol) else { return nil }

        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe, rocPeriod: rocPeriod)
        let pointSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let actualSpread: Double
        if let spread = indicators.spread {
            actualSpread = (spread * pointSize / max(indicators.currentPrice, 0.0000001)) * 10000
        } else {
            actualSpread = (indicators.atr / max(indicators.currentPrice, 0.0000001)) * 10000
        }
        if actualSpread > spreadTol {
            godLog("⚠️ \(symbol) skipped: Spread too high (\(String(format: "%.2f", actualSpread)) > \(spreadTol))", level: .info)
            return nil
        }
        guard await validateVolatility(symbol, indicators: indicators) else { return nil }

        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candlesByTimeframe["1m"]!)

        let accuracy = await SignalAccuracyEngine.assess(symbol: symbol, direction: finalSignal.type, candles: candlesByTimeframe["1m"]!)
        finalSignal = finalSignal.withSelfLearningInsight(accuracy.insight)
        guard accuracy.approved else {
            godLog("🛑 ACCURACY GATE | \(symbol) | \(accuracy.reasons.joined(separator: "; "))", level: .warning)
            return nil
        }

        guard shouldTradeSymbol(symbol, direction: finalSignal.type) else {
            godLog("🛑 PERFORMANCE GATE | \(symbol) | \(finalSignal.type) blocked by poor directional history", level: .warning)
            return nil
        }

        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        logEvaluation(symbol: symbol, signal: finalSignal, threshold: threshold)
        guard finalSignal.type != .none, finalSignal.confidence >= threshold else { return nil }

        let adjustedSignal = await applyHistoricalAdjustment(finalSignal)

        // Do not alter direction to balance historical BUY/SELL counts. Direction must come from market evidence.
        godLog("⚖️ DIRECTIONAL NEUTRALITY | \(symbol) | BUY/SELL balancing filter disabled; market evidence is authoritative", level: .info)

        guard await RRLock.validate(signal: adjustedSignal) else {
            godLog("🛑 RR GATE | \(symbol) | direction=\(adjustedSignal.type)", level: .warning)
            return nil
        }

        await trackSignalQuality(adjustedSignal)
        lastSignalTime[symbol] = Date()
        godLog("🚀 FINAL SIGNAL | \(symbol) | direction=\(adjustedSignal.type) | B=\(adjustedSignal.score) S=\(adjustedSignal.sellScore) | confidence=\(Int(adjustedSignal.confidence))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .success)
        return adjustedSignal
    }

    private func logEvaluation(symbol: String, signal: ScalpingSignal, threshold: Double) {
        let factors = signal.confidenceFactors.keys.sorted()
        let factorText = factors.isEmpty ? "none" : factors.joined(separator: ", ")
        godLog("📊 EVAL | \(symbol) | FINAL=\(signal.type) | B=\(signal.score) S=\(signal.sellScore) | conf=\(Int(signal.confidence))% need=\(Int(threshold))% | factors=[\(factorText)]", level: .info)
        godLog("📐 INDICATORS | \(symbol) | H4=\(signal.indicators.h4Trend) D1=\(signal.indicators.d1Trend) | EMA1m=\(String(format: "%.5f/%.5f/%.5f", signal.indicators.ema9, signal.indicators.ema21, signal.indicators.ema50)) | EMA5m=\(String(format: "%.5f/%.5f/%.5f", signal.indicators.ema9_5m, signal.indicators.ema21_5m, signal.indicators.ema50_5m)) | RSI=\(String(format: "%.1f", signal.indicators.rsi)) | CCI=\(String(format: "%.1f", signal.indicators.cci)) | MOM=\(String(format: "%.6f", signal.indicators.momentumScore)) | Δ=\(String(format: "%.1f", signal.indicators.deltaVolume))", level: .info)
    }

    func evaluateFastSignal(symbol: String, currentPrice: Double) async -> ScalpingSignal? {
        let started = Date()
        guard allowedSymbols.contains(symbol) else { return nil }
        let h4Trend = await getCachedTrend(symbol: symbol, timeframe: "4h")
        let d1Trend = await getCachedTrend(symbol: symbol, timeframe: "D1")
        guard h4Trend != .none || d1Trend != .none else { return nil }

        let candles1m = await marketData.getCandles(symbol: symbol, timeframe: "1m")
        guard candles1m.count >= 100 else { return nil }
        let indicators = await calculateFastIndicators(symbol: symbol, candles1m: candles1m, h4Trend: h4Trend, d1Trend: d1Trend)
        var signal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candles1m)
        signal = await applyHistoricalAdjustment(signal)
        let threshold = await MainActor.run { ScalpingConfig.shared.getConfidenceThreshold(for: symbol) }
        logEvaluation(symbol: symbol, signal: signal, threshold: threshold)
        guard signal.type != .none, signal.confidence >= threshold else { return nil }
        guard await RRLock.validate(signal: signal) else { return nil }
        lastSignalTime[symbol] = Date()
        godLog("⚡️ FAST SIGNAL | \(symbol) | direction=\(signal.type) | confidence=\(Int(signal.confidence))% | elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms", level: .success)
        return signal
    }

    private func getCachedTrend(symbol: String, timeframe: String) async -> SignalType {
        if let cached = cachedHTFTrends[symbol]?[timeframe], Date().timeIntervalSince(cached.timestamp) < htfCacheDuration {
            return cached.trend
        }
        let candles = await marketData.getCandles(symbol: symbol, timeframe: timeframe)
        let trend = calculateHTFTrend(candles: candles)
        if cachedHTFTrends[symbol] == nil { cachedHTFTrends[symbol] = [:] }
        cachedHTFTrends[symbol]?[timeframe] = (trend: trend, timestamp: Date())
        godLog("📐 HTF CACHE | \(symbol) | \(timeframe)=\(trend) | candles=\(candles.count)", level: .info)
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
        return IndicatorSet(rsi: rsi, stochasticK: stoch.k.last ?? 50, stochasticD: stoch.d.last ?? 50,
                            cci: 0, sar: currentPrice, atr: atr, spread: candles1m.last?.spread,
                            ema9: ema9, ema21: ema21, ema50: ema50,
                            ema9_5m: ema9, ema21_5m: ema21, ema50_5m: ema50,
                            bbPosition: bbPos, volumeRatio: 1.0, volumeProfilePOC: 0,
                            support: 0, resistance: 0,
                            sessions: (asiaRange: (0,0), londonRange: (0,0), usRange: (0,0)),
                            trendStrength: 0, pricePattern: .none, regime: .ranging,
                            currentPrice: currentPrice, h4Trend: h4Trend, d1Trend: d1Trend, w1Trend: .none,
                            momentumScore: momentum, isAccelerating: isAccel, fvgGaps: gaps, deltaVolume: delta)
    }

    private func applyHistoricalAdjustment(_ signal: ScalpingSignal) async -> ScalpingSignal {
        let history = signalQualityHistory[signal.symbol] ?? []
        guard history.count >= 5 else { return signal }
        let similar = history.filter { abs($0.confidence - signal.confidence) < 15 && $0.type == signal.type }
        let wins = similar.compactMap { $0.wasWin }.filter { $0 }.count
        let total = similar.compactMap { $0.wasWin }.count
        guard total > 0 else { return signal }
        let winRate = Double(wins) / Double(total)
        return signal.withConfidence(signal.confidence * (0.6 + (winRate * 0.4)))
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
        history.append(SignalQuality(type: signal.type, confidence: signal.confidence, timestamp: signal.timestamp, wasWin: nil))
        if history.count > maxQualityHistory { history.removeFirst() }
        signalQualityHistory[signal.symbol] = history
    }

    func validateSignalSymmetry(symbol: String) async -> (buyCount: Int, sellCount: Int, ratio: Double) {
        let history = signalQualityHistory[symbol] ?? []
        let buys = history.filter { $0.type == .buy }.count
        let sells = history.filter { $0.type == .sell }.count
        let total = max(1, buys + sells)
        let ratio = Double(buys) / Double(total)
        godLog("⚖️ SIGNAL OBSERVATION | \(symbol) | BUY=\(buys) SELL=\(sells) | ratio=\(String(format: "%.2f", ratio)) | informational only", level: .info)
        return (buys, sells, ratio)
    }

    private func validateVolatility(_ symbol: String, indicators: IndicatorSet) async -> Bool {
        guard indicators.currentPrice > 0 else { return false }
        let atrPercentage = indicators.atr / indicators.currentPrice * 100
        let hour = Calendar.current.component(.hour, from: Date())
        var minVol = 0.008
        if hour < 8 { minVol = 0.005 } else if hour >= 16 { minVol = 0.010 }
        let ok = atrPercentage >= minVol && atrPercentage <= 0.50
        if !ok { godLog("🛑 VOLATILITY GATE | \(symbol) | ATR%=\(String(format: "%.4f", atrPercentage)) | range=\(minVol)-0.50", level: .warning) }
        return ok
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
        let h4 = calculateHTFTrend(candles: c4h)
        let d1 = calculateHTFTrend(candles: cD1)
        let w1 = calculateHTFTrend(candles: cW1)
        godLog("📦 CANDLE SNAPSHOT | \(symbol) | 1m=\(c1m.count) 5m=\(c5m.count) 4h=\(c4h.count) D1=\(cD1.count) W1=\(cW1.count) | H4=\(h4) D1=\(d1) W1=\(w1)", level: .info)
        return IndicatorSet(rsi: rsi, stochasticK: stoch.k.last ?? 50, stochasticD: stoch.d.last ?? 50,
                            cci: cci, sar: sar, atr: atr, spread: c1m.last?.spread,
                            ema9: ema9, ema21: ema21, ema50: ema50,
                            ema9_5m: ema9_5m, ema21_5m: ema21_5m, ema50_5m: ema50_5m,
                            bbPosition: bbPosition, volumeRatio: 1.0, volumeProfilePOC: 0,
                            support: 0, resistance: 0, sessions: sessions,
                            trendStrength: 0, pricePattern: .none, regime: .ranging,
                            currentPrice: currentPrice, h4Trend: h4, d1Trend: d1, w1Trend: w1,
                            momentumScore: momentum, isAccelerating: isAccel, fvgGaps: gaps, deltaVolume: delta)
    }

    private func calculateHTFTrend(candles: [Kline]) -> SignalType {
        guard candles.count >= 50 else { return .none }
        let closes = candles.map { $0.close }
        let ema20 = Indicators.ema(closes, period: 20).last ?? 0
        let ema50 = Indicators.ema(closes, period: 50).last ?? 0
        if ema20 > ema50 { return .buy }
        if ema20 < ema50 { return .sell }
        return .none
    }

    private func tracePillar(symbol: String, pillar: String, passed: Bool, detail: String, contribution: Double, buyScore: Double, sellScore: Double) {
        godLog("🔎 SIGNAL PILLAR | \(symbol) | \(passed ? "✅ PASS" : "❌ FAIL") | \(pillar) | \(detail) | +\(String(format: "%.1f", contribution)) | B=\(String(format: "%.1f", buyScore)) S=\(String(format: "%.1f", sellScore))", level: .info)
    }

    private func generateSignal(symbol: String, indicators: IndicatorSet, candles1m: [Kline]) async -> ScalpingSignal {
        let (deltaThreshold, mlThreshold, weights, pullbackEMAPeriod) = await MainActor.run {
            let config = ScalpingConfig.shared
            return (config.orderFlowThreshold,
                    config.mlConfidenceThreshold,
                    ["HTF": config.weightHTFAlignment, "Momentum": config.weightMomentumExhaustion,
                     "Volume": config.weightVolumeSurge, "EMA": config.weightEMAStack,
                     "BB": config.weightBollingerRejection, "CCI": config.weightCCICycle,
                     "SAR": config.weightSARTrend, "Accel": config.weightMomentumSurge,
                     "OrderFlow": config.weightOrderFlow, "ML": config.weightMLConfirmed,
                     "FixedSL": config.fixedSLPips], config.pullbackEMAPeriod)
        }

        var buyScore = 0.0
        var sellScore = 0.0
        var factors: [String: Double] = [:]
        let htfWeight = weights["HTF"] ?? 25

        // HTF is a confirmation pillar, not a hard directional gate. Mixed H4/D1 must not erase a valid LTF direction.
        if indicators.h4Trend == .buy && indicators.d1Trend == .buy {
            buyScore += htfWeight
            factors["Institutional Alignment"] = htfWeight
            tracePillar(symbol: symbol, pillar: "Institutional Alignment", passed: true, detail: "H4=BUY D1=BUY", contribution: htfWeight, buyScore: buyScore, sellScore: sellScore)
        } else if indicators.h4Trend == .sell && indicators.d1Trend == .sell {
            sellScore += htfWeight
            factors["Institutional Alignment"] = htfWeight
            tracePillar(symbol: symbol, pillar: "Institutional Alignment", passed: true, detail: "H4=SELL D1=SELL", contribution: htfWeight, buyScore: buyScore, sellScore: sellScore)
        } else if indicators.h4Trend == .buy || indicators.d1Trend == .buy {
            buyScore += htfWeight * 0.5
            tracePillar(symbol: symbol, pillar: "Institutional Alignment", passed: true, detail: "Partial bullish HTF confirmation; no hard gate", contribution: htfWeight * 0.5, buyScore: buyScore, sellScore: sellScore)
        } else if indicators.h4Trend == .sell || indicators.d1Trend == .sell {
            sellScore += htfWeight * 0.5
            tracePillar(symbol: symbol, pillar: "Institutional Alignment", passed: true, detail: "Partial bearish HTF confirmation; no hard gate", contribution: htfWeight * 0.5, buyScore: buyScore, sellScore: sellScore)
        } else {
            tracePillar(symbol: symbol, pillar: "Institutional Alignment", passed: false, detail: "H4/D1 neutral; LTF remains authoritative", contribution: 0, buyScore: buyScore, sellScore: sellScore)
        }

        let momWeight = weights["Momentum"] ?? 15
        let volatilityRegime = indicators.currentPrice > 0 ? indicators.atr / indicators.currentPrice : 0
        let isHighVol = volatilityRegime > 0.01
        let rsiOversold = isHighVol ? 28.0 : 32.0
        let rsiOverbought = isHighVol ? 72.0 : 68.0
        let stochOversold = isHighVol ? 10.0 : 15.0
        let stochOverbought = isHighVol ? 90.0 : 85.0
        if indicators.rsi < rsiOversold && indicators.stochasticK < stochOversold {
            buyScore += momWeight
            factors["Dip Buy"] = momWeight
            tracePillar(symbol: symbol, pillar: "Momentum / Exhaustion", passed: true, detail: "BUY RSI/Stoch exhaustion", contribution: momWeight, buyScore: buyScore, sellScore: sellScore)
        } else if indicators.rsi > rsiOverbought && indicators.stochasticK > stochOverbought {
            sellScore += momWeight
            factors["Rally Sell"] = momWeight
            tracePillar(symbol: symbol, pillar: "Momentum / Exhaustion", passed: true, detail: "SELL RSI/Stoch exhaustion", contribution: momWeight, buyScore: buyScore, sellScore: sellScore)
        }

        let volWeight = weights["Volume"] ?? 12
        if indicators.volumeRatio >= 1.5 {
            if indicators.currentPrice > indicators.ema21 { buyScore += volWeight; factors["Institutional Volume"] = volWeight }
            else if indicators.currentPrice < indicators.ema21 { sellScore += volWeight; factors["Institutional Volume"] = volWeight }
        }

        let emaWeight = weights["EMA"] ?? 18
        let buyStack = indicators.ema9 > indicators.ema21 && indicators.ema21 > indicators.ema50 && indicators.ema9_5m > indicators.ema21_5m && indicators.ema21_5m > indicators.ema50_5m
        let sellStack = indicators.ema9 < indicators.ema21 && indicators.ema21 < indicators.ema50 && indicators.ema9_5m < indicators.ema21_5m && indicators.ema21_5m < indicators.ema50_5m
        if buyStack { buyScore += emaWeight; factors["Structural Strength"] = emaWeight; tracePillar(symbol: symbol, pillar: "EMA Stack", passed: true, detail: "M1/M5 bullish stack", contribution: emaWeight, buyScore: buyScore, sellScore: sellScore) }
        else if sellStack { sellScore += emaWeight; factors["Structural Strength"] = emaWeight; tracePillar(symbol: symbol, pillar: "EMA Stack", passed: true, detail: "M1/M5 bearish stack", contribution: emaWeight, buyScore: buyScore, sellScore: sellScore) }

        let bbWeight = weights["BB"] ?? 10
        if indicators.bbPosition < 0.05 { buyScore += bbWeight; factors["Bollinger Rejection"] = bbWeight }
        else if indicators.bbPosition > 0.95 { sellScore += bbWeight; factors["Bollinger Rejection"] = bbWeight }

        let cciWeight = weights["CCI"] ?? 10
        if indicators.cci > 100 { buyScore += cciWeight; factors["Cyclical Strength"] = cciWeight }
        else if indicators.cci < -100 { sellScore += cciWeight; factors["Cyclical Strength"] = cciWeight }

        let sarWeight = weights["SAR"] ?? 10
        let sarDistance = abs(indicators.currentPrice - indicators.sar)
        let atrNormalizedDistance = indicators.atr > 0 ? sarDistance / indicators.atr : 0
        if atrNormalizedDistance > 0.4 {
            if indicators.sar < indicators.currentPrice { buyScore += sarWeight; factors["SAR Support"] = sarWeight }
            else if indicators.sar > indicators.currentPrice { sellScore += sarWeight; factors["SAR Resistance"] = sarWeight }
        }

        let accelWeight = weights["Accel"] ?? 12
        let momentumDirection: SignalType = indicators.momentumScore > 0.001 ? .buy : (indicators.momentumScore < -0.001 ? .sell : .none)
        if indicators.isAccelerating {
            if momentumDirection == .buy { buyScore += accelWeight; factors["Momentum Surge"] = accelWeight }
            else if momentumDirection == .sell { sellScore += accelWeight; factors["Momentum Surge"] = accelWeight }
        }

        let flowWeight = weights["OrderFlow"] ?? 15
        if indicators.deltaVolume > deltaThreshold { buyScore += flowWeight; factors["Order Flow Buy"] = flowWeight }
        else if indicators.deltaVolume < -deltaThreshold { sellScore += flowWeight; factors["Order Flow Sell"] = flowWeight }

        let type: SignalType = buyScore > sellScore ? .buy : (sellScore > buyScore ? .sell : .none)
        let finalScore = type == .buy ? buyScore : sellScore
        var confidence = min(finalScore * 1.1, 98)

        let (mlDir, mlConf) = await getMLTrendPrediction(symbol: symbol, candles: candles1m)
        let mlWeight = weights["ML"] ?? 10
        godLog("🤖 ML DIRECTION | \(symbol) | model=\(mlDir) confidence=\(String(format: "%.3f", mlConf)) | ruleEngine=\(type) | B=\(String(format: "%.1f", buyScore)) S=\(String(format: "%.1f", sellScore))", level: .info)
        if mlDir == type && mlConf >= mlThreshold {
            confidence = min(confidence + (mlConf * mlWeight), 99)
            factors["ML Confirmed"] = mlConf * mlWeight
        } else if mlDir != .none && mlConf > (mlThreshold + 0.1) {
            confidence *= 0.7
            factors["ML Divergence"] = -30
            godLog("⚠️ ML DIVERGENCE | \(symbol) | ruleEngine=\(type) model=\(mlDir) | confidence reduced symmetrically", level: .warning)
        }

        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let slPips = weights["FixedSL"] ?? 30
        let sl = type == .buy ? indicators.currentPrice - (slPips * pipSize) : indicators.currentPrice + (slPips * pipSize)
        let atrPips = indicators.atr / pipSize
        let tpPips = max(8, min(25, atrPips * 2.5))
        let tp = type == .buy ? indicators.currentPrice + (tpPips * pipSize) : indicators.currentPrice - (tpPips * pipSize)
        let optimalEntry = findOptimalEntry(symbol: symbol, type: type, basePrice: indicators.currentPrice, candles: candles1m, atr: indicators.atr, fvgGaps: indicators.fvgGaps, emaPeriod: pullbackEMAPeriod)

        return ScalpingSignal(type: type, symbol: symbol, price: indicators.currentPrice, confidence: confidence,
                              score: Int(buyScore), sellScore: Int(sellScore), indicators: indicators,
                              confidenceFactors: factors, timestamp: Date(), stopLoss: sl, takeProfit: tp,
                              volume: 0.1, optimalEntryPrice: optimalEntry)
    }

    private func validateData(_ dict: [String: [Kline]], symbol: String) -> Bool {
        let requirements: [(String, Int)] = [("1m", 100), ("5m", 100), ("15m", 50), ("30m", 50), ("1h", 50), ("4h", 50), ("D1", 50), ("W1", 20)]
        var valid = true
        for (tf, minimum) in requirements {
            let count = dict[tf]?.count ?? 0
            if count < minimum {
                valid = false
                godLog("🛑 CANDLE VALIDATION | \(symbol) | \(tf)=\(count), required>=\(minimum)", level: .warning)
            } else {
                godLog("✅ CANDLE VALIDATION | \(symbol) | \(tf)=\(count)", level: .info)
            }
        }
        return valid
    }

    private func findOptimalEntry(symbol: String, type: SignalType, basePrice: Double, candles: [Kline], atr: Double, fvgGaps: [FairValueGap], emaPeriod: Int) -> Double? {
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
        let roc1 = AdvancedIndicators.calculateROC(closes, period: max(1, rocPeriod))
        let roc3 = AdvancedIndicators.calculateROC(closes, period: max(1, rocPeriod * 3))
        let roc5 = AdvancedIndicators.calculateROC(closes, period: max(1, rocPeriod * 5))
        return (roc1, abs(roc1) > abs(roc3) && abs(roc3) > abs(roc5))
    }
}
