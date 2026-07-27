// ScalpingSignalEngine.swift - GOD MODE 2.0 (FIXED - 80%+ Target)
import Foundation

actor ScalpingSignalEngine {
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol
    private let config: ScalpingConfig

    // Multi-timeframe analysis
    private let timeframes = ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"]
    private var lastSignalTime: [String: Date] = [:]

    // Signal quality tracking for adaptive learning
    private var signalQualityHistory: [String: [SignalQuality]] = [:]
    private let maxQualityHistory = 100

    // MARK: - Symbol Performance Tracking (NEW)
    private var symbolPerformance: [String: (wins: Int, losses: Int, pnl: Double)] = [:]
    private let minTradesForAdaptation = 5
    private let minWinRateForTrading = 0.40  // 40% minimum win rate

    // FIXED: Whitelist of tradable symbols (majors + tight-spread minors only)
    private let allowedSymbols = Set([
                                         "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD",  // Majors
                                         "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "EURGBP", "EURCHF",  // Minors
                                         "GBPCHF", "CADJPY", "CHFJPY", "AUDCHF", "NZDCAD", "AUDNZD"   // Additional tight spreads
                                     ])

    init(marketData: MarketDataProvider, tradeHistory: RefactoredTradeHistoryManager,
         riskManager: RiskManagerProtocol, config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
        self.config = config
    }

    // MARK: - Symbol Performance Tracking Methods (NEW)
    func updateSymbolPerformance(symbol: String, pnl: Double) async {
        var stats = symbolPerformance[symbol] ?? (wins: 0, losses: 0, pnl: 0.0)
        if pnl > 0 {
            stats.wins += 1
        } else if pnl < 0 {
            stats.losses += 1
        }
        stats.pnl += pnl
        symbolPerformance[symbol] = stats
    }

    func shouldTradeSymbol(_ symbol: String) -> Bool {
        guard let stats = symbolPerformance[symbol],
              stats.wins + stats.losses >= minTradesForAdaptation else {
            return true  // Not enough data, allow trading
        }

        let winRate = Double(stats.wins) / Double(stats.wins + stats.losses)
        return winRate >= minWinRateForTrading
    }

    func getSymbolConfidenceMultiplier(_ symbol: String) -> Double {
        guard let stats = symbolPerformance[symbol],
              stats.wins + stats.losses >= minTradesForAdaptation else {
            return 1.0  // Not enough data, no adjustment
        }

        let winRate = Double(stats.wins) / Double(stats.wins + stats.losses)
        if winRate >= 0.60 {
            return 1.2  // Boost confidence for high-performing symbols
        } else if winRate >= 0.50 {
            return 1.1  // Slight boost
        } else if winRate >= 0.40 {
            return 1.0  // Neutral
        } else {
            return 0.8  // Reduce confidence for poorly performing symbols
        }
    }

    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        // 1. SYMBOL WHITELIST CHECK
        guard allowedSymbols.contains(symbol) else {
            return nil
        }

        // 2. PERFORMANCE CHECK (NEW)
        guard shouldTradeSymbol(symbol) else {
            let perf = symbolPerformance[symbol]
            let total = Double((perf?.wins ?? 0) + (perf?.losses ?? 0))
            let winRate = total > 0 ? (Double(perf?.wins ?? 0) / total) * 100 : 0
            godLog("📊 \(symbol) Rejected: Poor historical performance (\(String(format: "%.1f", winRate))% win rate)")
            return nil
        }

        // 3. TRADABILITY CHECK
        guard await MT5Service.shared.isSymbolTradable(symbol) else {
            return nil
        }

        // 4. RISK CHECK
        guard await riskManager.canOpenTrade(for: symbol) else {
            return nil
        }

        // 4.1 NEWS FILTER (NEW: God Mode Autonomous News Protection)
        let newsCheck = await MainActor.run {
            (enabled: config.enableNewsFilter, highMin: config.pauseBeforeHighImpactMinutes, medMin: config.pauseBeforeMediumImpactMinutes)
        }
        
        if newsCheck.enabled {
            let (impact, event) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: Int(max(newsCheck.highMin, newsCheck.medMin)))
            
            if impact == .high {
                godLog("🌍 \(symbol) PAUSED: High Impact News Incoming - \(event ?? "Unknown Event")", level: .warning)
                return nil
            } else if impact == .medium && newsCheck.medMin > 0 {
                // For medium, we could also pause or just log
                godLog("🌍 \(symbol) CAUTION: Medium Impact News Incoming - \(event ?? "Unknown Event")", level: .warning)
                // Optional: Decide whether to pause or just proceed with higher caution
            }
        }

        // 5. COOLDOWN CHECK
        let cooldown = await MainActor.run { config.cooldownSeconds }
        if let lastSignal = lastSignalTime[symbol],
           Date().timeIntervalSince(lastSignal) < cooldown {
            // print("📊 \(symbol) ignored: Cooldown active")
            return nil
        }

        // 6. INTELLIGENT DATA FETCHING
        async let c1m = fetchIfStale(symbol, "1m", 1000)
        async let c5m = fetchIfStale(symbol, "5m", 500)
        async let c15m = fetchIfStale(symbol, "15m", 300)
        async let c1h = fetchIfStale(symbol, "1h", 300)
        async let c4h = fetchIfStale(symbol, "4h", 300)
        async let cD1 = fetchIfStale(symbol, "D1", 200)
        async let cW1 = fetchIfStale(symbol, "W1", 100)

        let candlesByTimeframe = await [
            "1m": c1m, "5m": c5m, "15m": c15m, "1h": c1h,
            "4h": c4h, "D1": cD1, "W1": cW1
        ]

        guard validateData(candlesByTimeframe, symbol: symbol) else { 
            godLog("📊 \(symbol) Rejected: Insufficient MT5 candle data for analysis", level: .warning)
            return nil 
        }

        // 7. INDICATOR ENGINE
        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe)

        // 8. SPREAD GUARD (DYNAMIC)
        let spreadSettings = await MainActor.run { 
            (tolerance: config.spreadTolerance, autoRaise: config.autoRaiseSpreadDuringNews, multiplier: config.newsSpreadMultiplier)
        }
        
        var effectiveTolerance = spreadSettings.tolerance
        
        // Adjust tolerance if news is active (allowing wider spreads if preferred, or tightening if safer)
        let (impact, _) = await NewsService.shared.getImpactForSymbol(symbol, timeframeMinutes: 30)
        if impact != .none && spreadSettings.autoRaise {
            effectiveTolerance *= spreadSettings.multiplier
            print("🌍 \(symbol) News Active: Increasing spread tolerance to \(String(format: "%.1f", effectiveTolerance)) bps")
        }
        
        let actualSpread: Double
        if let s = indicators.spread {
            let pointSize = symbol.contains("JPY") ? 0.01 : 0.0001
            actualSpread = (s * pointSize / indicators.currentPrice) * 10000
        } else {
            actualSpread = (indicators.atr / indicators.currentPrice) * 10000
        }
        
        if actualSpread > effectiveTolerance {
            godLog("📊 \(symbol) Rejected: Spread too high (\(String(format: "%.1f", actualSpread)) bps) - Limit: \(effectiveTolerance) bps", level: .warning)
            return nil
        }

        // 9. VOLATILITY FILTER (NEW)
        guard await validateVolatility(symbol, indicators: indicators) else {
            return nil
        }

        // 10. ELITE SIGNAL GENERATION
        let signal = await generateSignal(symbol: symbol, indicators: indicators)

        if signal.type == .none { 
            return nil 
        }

        // 11. FINAL QUALITY FILTERS
        guard let finalSignal = await applyQualityFilters(signal, symbol: symbol) else {
            return nil
        }

        // 12. R:R VALIDATION
        guard validateRiskReward(finalSignal) else {
            godLog("📊 \(symbol) Rejected: Poor risk/reward ratio", level: .warning)
            return nil
        }

        // 13. SYMBOL-SPECIFIC CONFIDENCE ADJUSTMENT (NEW)
        let confidenceMultiplier = getSymbolConfidenceMultiplier(symbol)
        var adjustedSignal = finalSignal
        adjustedSignal.confidence = min(finalSignal.confidence * confidenceMultiplier, 100)

        godLog("🚀 GOD MODE 2.0: Elite Signal for \(symbol) | Confidence: \(Int(adjustedSignal.confidence))%", level: .success)
        await trackSignalQuality(adjustedSignal)

        return adjustedSignal
    }

    // MARK: - Volatility Filter (NEW)
    private func validateVolatility(_ symbol: String, indicators: IndicatorSet) async -> Bool {
        let atrPercentage = indicators.atr / indicators.currentPrice * 100
        
        // 🎯 DYNAMIC THRESHOLD based on time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let isAsianSession = hour >= 0 && hour < 8
        let isLondonSession = hour >= 8 && hour < 16
        let isUSSession = hour >= 16 && hour < 24
        
        var minVol: Double
        var maxVol: Double
        
        switch (isAsianSession, isLondonSession, isUSSession) {
        case (true, false, false):  // Asian - low volatility is NORMAL
            minVol = 0.005  // 0.5% - Much lower threshold
            maxVol = 0.30   // 30% - High threshold
            godLog("🌏 Asian Session: Using wider volatility range", level: .diagnostic)
        case (false, true, false):  // London - medium
            minVol = 0.008
            maxVol = 0.50
        case (false, false, true):  // US - medium-high
            minVol = 0.010
            maxVol = 0.60
        default:
            minVol = 0.008
            maxVol = 0.50
        }
        
        // Skip if volatility too low (no movement)
        if atrPercentage < minVol {
            godLog("📊 \(symbol) Rejected: Low volatility (\(String(format: "%.3f", atrPercentage))%) - Session min: \(minVol)%", level: .warning)
            return false
        }
        
        // Skip if volatility too high (unsafe)
        if atrPercentage > maxVol {
            godLog("📊 \(symbol) Rejected: High volatility (\(String(format: "%.2f", atrPercentage))%) - Session max: \(maxVol)%", level: .warning)
            return false
        }
        
        godLog("✅ Volatility check PASSED: \(String(format: "%.3f", atrPercentage))% (Session range: \(minVol)-\(maxVol)%)", level: .diagnostic)
        return true
    }

    private func fetchIfStale(_ symbol: String, _ timeframe: String, _ count: Int) async -> [Kline] {
        let existing = await marketData.getCandles(symbol: symbol, timeframe: timeframe)
        let threshold: TimeInterval = (timeframe == "1m" || timeframe == "5m") ? 60 : 1800

        if let lastTime = existing.last?.closeTime,
           Date().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(lastTime))) < threshold {
            return existing
        }

        return (try? await MT5Service.shared.getCandles(symbol: symbol, timeframe: timeframe, count: count)) ?? existing
    }

    private func calculateAllIndicators(symbol: String, candlesByTimeframe: [String: [Kline]]) async -> IndicatorSet {
        let c1m = candlesByTimeframe["1m"]!
        let c5m = candlesByTimeframe["5m"]!
        let c1h = candlesByTimeframe["1h"]!
        let c4h = candlesByTimeframe["4h"]!
        let cD1 = candlesByTimeframe["D1"]!
        let cW1 = candlesByTimeframe["W1"]!

        let currentPrice = c1m.last?.close ?? 0
        let rsi1m = Indicators.rsi(c1m.map { $0.close }, period: 14).last ?? 50
        let stoch1m = AdvancedIndicators.stochastic(c1m, periodK: 14, periodD: 3)
        let sar1m = AdvancedIndicators.parabolicSAR(c1m).last ?? currentPrice
        let atr1m = AdvancedIndicators.atr(c1m, period: 14).last ?? 0

        let ema9_1m = Indicators.ema(c1m.map { $0.close }, period: 9).last ?? currentPrice
        let ema21_1m = Indicators.ema(c1m.map { $0.close }, period: 21).last ?? currentPrice
        let ema50_1m = Indicators.ema(c1m.map { $0.close }, period: 50).last ?? currentPrice

        let ema9_5m = Indicators.ema(c5m.map { $0.close }, period: 9).last ?? currentPrice
        let ema21_5m = Indicators.ema(c5m.map { $0.close }, period: 21).last ?? currentPrice

        let bb1m = Indicators.bollingerBands(c1m.map { $0.close }, period: 20, stdDev: 2.0)
        let bbPosition = (currentPrice - (bb1m.lower.last ?? 0)) / max((bb1m.upper.last ?? 1) - (bb1m.lower.last ?? 0), 0.0001)

        let avgVol = c1m.suffix(20).map { $0.volume }.reduce(0, +) / 20
        let volRatio = (c1m.last?.volume ?? 0) / max(avgVol, 0.01)

        let srLevels = AdvancedIndicators.supportResistance(c1h, lookback: 100)

        return IndicatorSet(
            rsi: rsi1m, stochasticK: stoch1m.k.last ?? 50, stochasticD: stoch1m.d.last ?? 50,
            cci: AdvancedIndicators.cci(c1m, period: 20).last ?? 0,
            sar: sar1m, atr: atr1m, spread: c1m.last?.spread,
            ema9: ema9_1m, ema21: ema21_1m, ema50: ema50_1m,
            ema9_5m: ema9_5m, ema21_5m: ema21_5m, ema50_5m: 0,
            bbPosition: bbPosition, volumeRatio: volRatio, volumeProfilePOC: 0,
            support: srLevels.support, resistance: srLevels.resistance,
            sessions: AdvancedIndicators.sessionAnalysis(c1m),
            trendStrength: calculateTrendStrength(c1m),
            pricePattern: detectPricePattern(c1m),
            regime: await detectMarketRegime(c1m, c5m, c1h),
            currentPrice: currentPrice,
            h4Trend: calculateHTFTrend(candles: c4h),
            d1Trend: calculateHTFTrend(candles: cD1),
            w1Trend: calculateHTFTrend(candles: cW1)
        )
    }

    private func calculateHTFTrend(candles: [Kline]) -> SignalType {
        guard candles.count >= 50 else { return .none }
        let closes = candles.map { $0.close }
        let ema20 = Indicators.ema(closes, period: 20).last ?? 0
        let ema50 = Indicators.ema(closes, period: 50).last ?? 0
        if ema20 > ema50 && closes.last! > ema20 { return .buy }
        if ema20 < ema50 && closes.last! < ema20 { return .sell }
        return .none
    }

    private func generateSignal(symbol: String, indicators: IndicatorSet) async -> ScalpingSignal {
        var buyScore = 0.0
        var sellScore = 0.0
        var activePillarsBuy = 0
        var activePillarsSell = 0
        var confidenceFactors: [String: Double] = [:]

        // Load dynamic configuration from MainActor
        let (_, minReqScore, minPillars, weights) = await MainActor.run {
            (
                config.mandatoryConfluenceLevel,
                config.minScore,
                config.minConfluencePillars,
                (rsi: config.rsiWeight, stoch: config.stochasticWeight, cci: config.cciWeight,
                 ma: config.maWeight, bb: config.bbWeight, vol: config.volumeWeight,
                 pat: config.patternWeight)
            )
        }

        // 1. HTF TREND ANCHORS (H4 & D1)
        if indicators.h4Trend == .buy { activePillarsBuy += 1; buyScore += weights.ma * 0.5 }
        if indicators.h4Trend == .sell { activePillarsSell += 1; sellScore += weights.ma * 0.5 }
        if indicators.d1Trend == .buy { activePillarsBuy += 1; buyScore += weights.ma * 0.5 }
        if indicators.d1Trend == .sell { activePillarsSell += 1; sellScore += weights.ma * 0.5 }

        // 2. MOMENTUM CLOUD (MA Alignment 1m + 5m)
        if indicators.ema9 > indicators.ema21 && indicators.ema9_5m > indicators.ema21_5m {
            activePillarsBuy += 1
            buyScore += weights.ma
            confidenceFactors["MA Stacked"] = 1.1
        } else if indicators.ema9 < indicators.ema21 && indicators.ema9_5m < indicators.ema21_5m {
            activePillarsSell += 1
            sellScore += weights.ma
            confidenceFactors["MA Stacked"] = 1.1
        }

        // 3. OSCILLATOR EXHAUSTION (RSI + Stoch)
        if indicators.rsi < 35 && indicators.stochasticK < 25 {
            activePillarsBuy += 1
            buyScore += (weights.rsi + weights.stoch)
            confidenceFactors["Exhaustion"] = 1.2
        } else if indicators.rsi > 65 && indicators.stochasticK > 75 {
            activePillarsSell += 1
            sellScore += (weights.rsi + weights.stoch)
            confidenceFactors["Exhaustion"] = 1.2
        }

        // 4. VOLATILITY REJECTION (Bollinger Bands)
        if indicators.bbPosition < 0.1 {
            activePillarsBuy += 1
            buyScore += weights.bb
            confidenceFactors["BB Reject"] = 1.15
        } else if indicators.bbPosition > 0.9 {
            activePillarsSell += 1
            sellScore += weights.bb
            confidenceFactors["BB Reject"] = 1.15
        }

        // 5. PRICE ACTION TRIGGER
        if indicators.pricePattern != .none {
            if indicators.pricePattern == .bullishEngulfing || indicators.pricePattern == .hammer {
                activePillarsBuy += 1
                buyScore += weights.pat
                confidenceFactors["PA Trigger"] = 1.1
            } else if indicators.pricePattern == .bearishEngulfing || indicators.pricePattern == .shootingStar {
                activePillarsSell += 1
                sellScore += weights.pat
                confidenceFactors["PA Trigger"] = 1.1
            }
        }

        // 6. VOLUME SURGE
        let minVolRatio = await MainActor.run { config.minVolumeRatio }
        let hasVolume = indicators.volumeRatio > minVolRatio
        if hasVolume {
            activePillarsBuy += 1; activePillarsSell += 1
            buyScore += weights.vol; sellScore += weights.vol
            confidenceFactors["Institutional Volume"] = 1.2
        }

        let currentPillars = buyScore > sellScore ? activePillarsBuy : activePillarsSell

        if buyScore > sellScore && currentPillars >= minPillars && buyScore >= minReqScore {
            let baseConfidence = min(buyScore / 80.0 * 100, 100)
            let adjustedConfidence = min(baseConfidence * confidenceFactors.values.reduce(1.0, *), 100)

            let sl = indicators.currentPrice - (indicators.atr * 0.8)
            let tp = indicators.currentPrice + (indicators.atr * 4.0)

            let signal = ScalpingSignal(
                type: .buy, symbol: symbol, price: indicators.currentPrice,
                confidence: adjustedConfidence, score: Int(buyScore), sellScore: 0,
                indicators: indicators, confidenceFactors: confidenceFactors, timestamp: Date(),
                stopLoss: sl, takeProfit: tp
            )

            // 🎯 HIGH CONFIDENCE = TIGHTER TP (lock in profits faster)
            if adjustedConfidence >= 80 {
                let tighterTP = signal.type == .buy ? 
                    indicators.currentPrice + (indicators.atr * 2.5) :  // Reduce TP distance
                    indicators.currentPrice - (indicators.atr * 2.5)
                return ScalpingSignal(
                    type: signal.type,
                    symbol: symbol,
                    price: indicators.currentPrice,
                    confidence: adjustedConfidence,
                    score: Int(buyScore),
                    sellScore: 0,
                    indicators: indicators,
                    confidenceFactors: confidenceFactors,
                    timestamp: Date(),
                    stopLoss: signal.stopLoss,
                    takeProfit: tighterTP
                )
            }
            return signal
        } else if sellScore > buyScore && currentPillars >= minPillars && sellScore >= minReqScore {
            let baseConfidence = min(sellScore / 80.0 * 100, 100)
            let adjustedConfidence = min(baseConfidence * confidenceFactors.values.reduce(1.0, *), 100)

            let sl = indicators.currentPrice + (indicators.atr * 0.8)
            let tp = indicators.currentPrice - (indicators.atr * 4.0)

            let signal = ScalpingSignal(
                type: .sell, symbol: symbol, price: indicators.currentPrice,
                confidence: adjustedConfidence, score: Int(sellScore), sellScore: 0,
                indicators: indicators, confidenceFactors: confidenceFactors, timestamp: Date(),
                stopLoss: sl, takeProfit: tp
            )

            // 🎯 HIGH CONFIDENCE = TIGHTER TP (lock in profits faster)
            if adjustedConfidence >= 80 {
                let tighterTP = signal.type == .buy ? 
                    indicators.currentPrice + (indicators.atr * 2.5) :  // Reduce TP distance
                    indicators.currentPrice - (indicators.atr * 2.5)
                return ScalpingSignal(
                    type: signal.type,
                    symbol: symbol,
                    price: indicators.currentPrice,
                    confidence: adjustedConfidence,
                    score: Int(buyScore),
                    sellScore: 0,
                    indicators: indicators,
                    confidenceFactors: confidenceFactors,
                    timestamp: Date(),
                    stopLoss: signal.stopLoss,
                    takeProfit: tighterTP
                )
            }
            return signal
        }
        
        // ADD DIAGNOSTIC LOG FOR PILLAR FAILURE
        let finalScore = max(buyScore, sellScore)
        let side = buyScore > sellScore ? "BUY" : "SELL"
        
        if finalScore < minReqScore || currentPillars < minPillars {
            godLog("📊 \(symbol) Pillar Check: \(currentPillars)/\(minPillars) Pillars aligned (\(side)). Score: \(Int(finalScore))/\(Int(minReqScore))", level: .diagnostic)
            if !hasVolume {
                godLog("   └─ Note: Institutional Volume also missing (\(String(format: "%.1f", indicators.volumeRatio))x)", level: .diagnostic)
            }
        }

        return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice, confidence: 0, score: 0, sellScore: 0, indicators: indicators, confidenceFactors: [:], timestamp: Date())
    }

    private func applyQualityFilters(_ signal: ScalpingSignal, symbol: String) async -> ScalpingSignal? {
        let (minConf, cooldown) = await MainActor.run {
            (config.getConfidenceThreshold(for: symbol), config.cooldownSeconds)
        }

        guard signal.type != .none && signal.confidence >= minConf else {
            if signal.type != .none {
                print("📊 \(symbol) Rejected: Confidence too low (\(Int(signal.confidence))% < \(Int(minConf))%)")
            }
            return nil
        }

        // Cooldown between signals per symbol
        if let last = lastSignalTime[symbol], Date().timeIntervalSince(last) < cooldown {
            return nil
        }

        lastSignalTime[symbol] = Date()
        return signal
    }

    private func validateRiskReward(_ signal: ScalpingSignal) -> Bool {
        guard let sl = signal.stopLoss, let tp = signal.takeProfit else { return false }

        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let ratio = reward / max(risk, 0.00001)

        if ratio < 1.5 {
            print("📊 \(signal.symbol) Rejected: R:R ratio \(String(format: "%.2f", ratio)) < 1.5")
            return false
        }

        return true
    }

    private func trackSignalQuality(_ signal: ScalpingSignal) async {
        var history = signalQualityHistory[signal.symbol] ?? []
        history.append(SignalQuality(type: signal.type, confidence: signal.confidence, timestamp: signal.timestamp))
        if history.count > maxQualityHistory { history.removeFirst() }
        signalQualityHistory[signal.symbol] = history
    }

    func updateSignalQuality(symbol: String, type: SignalType, confidence: Double, wasWin: Bool) async {
        var history = signalQualityHistory[symbol] ?? []
        if let idx = history.lastIndex(where: { $0.type == type && $0.wasWin == nil }) {
            history[idx].wasWin = wasWin
        }
        signalQualityHistory[symbol] = history
    }

    private func validateData(_ dict: [String: [Kline]], symbol: String) -> Bool {
        return (dict["1m"]?.count ?? 0) >= 100 && (dict["5m"]?.count ?? 0) >= 50 && (dict["4h"]?.count ?? 0) >= 50
    }

    private func calculateTrendStrength(_ candles: [Kline]) -> Double {
        guard candles.count >= 50 else { return 0 }
        let closes = candles.map { $0.close }
        let sma20 = closes.suffix(20).reduce(0, +) / 20
        let sma50 = closes.suffix(50).reduce(0, +) / 50
        return abs(sma20 - sma50) / sma50 * 1000
    }

    private func detectPricePattern(_ candles: [Kline]) -> PricePattern {
        guard candles.count >= 3 else { return .none }
        let last = candles.last!
        let prev = candles[candles.count-2]
        _ = candles[candles.count-3]

        // Bullish Engulfing
        if last.close > last.open && prev.close < prev.open &&
               last.close > prev.open && last.open < prev.close {
            return .bullishEngulfing
        }

        // Bearish Engulfing
        if last.close < last.open && prev.close > prev.open &&
               last.close < prev.open && last.open > prev.close {
            return .bearishEngulfing
        }

        // Hammer (bullish reversal)
        let body = abs(last.close - last.open)
        let lowerWick = min(last.open, last.close) - last.low
        if lowerWick > body * 2 && last.close > last.open {
            return .hammer
        }

        // Shooting Star (bearish reversal)
        let upperWick = last.high - max(last.open, last.close)
        if upperWick > body * 2 && last.close < last.open {
            return .shootingStar
        }

        return .none
    }

    private func detectMarketRegime(_ c1m: [Kline], _ c5m: [Kline], _ c1h: [Kline]) async -> MarketRegime {
        let atr = AdvancedIndicators.atr(c1m, period: 20).last ?? 0
        let vol = atr / (c1m.last?.close ?? 1) * 100
        return vol > 0.4 ? .volatile : (vol > 0.1 ? .trending : .ranging)
    }
}
