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

    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        // 1. SYMBOL WHITELIST CHECK (NEW)
        guard allowedSymbols.contains(symbol) else {
            // print("📊 \(symbol) rejected: Not in allowed symbols list")
            return nil
        }

        // 2. TRADABILITY CHECK
        guard await MT5Service.shared.isSymbolTradable(symbol) else {
            return nil
        }

        // 3. RISK CHECK
        guard await riskManager.canOpenTrade(for: symbol) else {
            return nil
        }

        // 4. COOLDOWN CHECK (FIXED: 5 minutes between signals)
        if let lastSignal = lastSignalTime[symbol],
           Date().timeIntervalSince(lastSignal) < 300 { // FIXED: 5 minute cooldown
            return nil
        }

        // 5. INTELLIGENT DATA FETCHING
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

        guard validateData(candlesByTimeframe, symbol: symbol) else { return nil }

        // 6. INDICATOR ENGINE
        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe)

        // 7. FIXED: SPREAD GUARD (3 bps = 30 pips max)
        let spreadBps = (indicators.atr / indicators.currentPrice) * 10000
        if spreadBps > 3.0 { // FIXED: 12 -> 3 bps
            print("📊 \(symbol) Rejected: Spread too high (\(String(format: "%.1f", spreadBps)) bps)")
            return nil
        }

        // 8. ELITE SIGNAL GENERATION
        let signal = await generateSignal(symbol: symbol, indicators: indicators)

        if signal.type == .none { return nil }

        // 9. FINAL QUALITY FILTERS (The 80% Filter)
        guard let finalSignal = await applyQualityFilters(signal, symbol: symbol) else {
            return nil
        }

        // 10. R:R VALIDATION (NEW)
        guard validateRiskReward(finalSignal) else {
            print("📊 \(symbol) Rejected: Poor risk/reward ratio")
            return nil
        }

        print("🚀 GOD MODE 2.0: Elite Signal for \(symbol) | Confidence: \(Int(finalSignal.confidence))%")
        await trackSignalQuality(finalSignal)

        return finalSignal
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
            sar: sar1m, atr: atr1m,
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
        var activePillarsBuy = 0
        var activePillarsSell = 0
        var confidenceFactors: [String: Double] = [:]

        // 1. HTF TREND ANCHORS (H4 & D1)
        if indicators.h4Trend == .buy { activePillarsBuy += 1 }
        if indicators.h4Trend == .sell { activePillarsSell += 1 }
        if indicators.d1Trend == .buy { activePillarsBuy += 1 }
        if indicators.d1Trend == .sell { activePillarsSell += 1 }

        // 2. MOMENTUM CLOUD (MA Alignment 1m + 5m)
        if indicators.ema9 > indicators.ema21 && indicators.ema9_5m > indicators.ema21_5m {
            activePillarsBuy += 1
            confidenceFactors["MA Stacked"] = 1.1
        } else if indicators.ema9 < indicators.ema21 && indicators.ema9_5m < indicators.ema21_5m {
            activePillarsSell += 1
            confidenceFactors["MA Stacked"] = 1.1
        }

        // 3. OSCILLATOR EXHAUSTION (RSI + Stoch)
        if indicators.rsi < 35 && indicators.stochasticK < 25 {
            activePillarsBuy += 1
            confidenceFactors["Exhaustion"] = 1.2
        } else if indicators.rsi > 65 && indicators.stochasticK > 75 {
            activePillarsSell += 1
            confidenceFactors["Exhaustion"] = 1.2
        }

        // 4. VOLATILITY REJECTION (Bollinger Bands)
        if indicators.bbPosition < 0.1 {
            activePillarsBuy += 1
            confidenceFactors["BB Reject"] = 1.15
        } else if indicators.bbPosition > 0.9 {
            activePillarsSell += 1
            confidenceFactors["BB Reject"] = 1.15
        }

        // 5. PRICE ACTION TRIGGER
        if indicators.pricePattern != .none {
            if indicators.pricePattern == .bullishEngulfing || indicators.pricePattern == .hammer {
                activePillarsBuy += 1
                confidenceFactors["PA Trigger"] = 1.1
            } else if indicators.pricePattern == .bearishEngulfing || indicators.pricePattern == .shootingStar {
                activePillarsSell += 1
                confidenceFactors["PA Trigger"] = 1.1
            }
        }

        // FIXED: VOLUME IS NOW A FILTER, NOT A PILLAR
        // Volume must be above 1.3x to even consider the signal, but doesn't add to pillars
        let hasVolume = indicators.volumeRatio > 1.3

        // FIXED: Minimum pillars required is 3 (was 2)
        let minPillars = 3
        let currentPillars = activePillarsBuy > activePillarsSell ? activePillarsBuy : activePillarsSell

        // FIXED: Must have volume confirmation AND enough pillars
        if activePillarsBuy > activePillarsSell && currentPillars >= minPillars && hasVolume {
            let baseConfidence = Double(currentPillars) / 6.0 * 100
            let adjustedConfidence = min(baseConfidence * confidenceFactors.values.reduce(1.0, *), 100)

            // Use fixed pip values for SL/TP (will be overridden by RiskManager)
            let sl = indicators.currentPrice - (indicators.atr * 1.0)
            let tp = indicators.currentPrice + (indicators.atr * 2.0)

            return ScalpingSignal(
                type: .buy, symbol: symbol, price: indicators.currentPrice,
                confidence: adjustedConfidence, score: currentPillars, sellScore: 0,
                indicators: indicators, confidenceFactors: confidenceFactors, timestamp: Date(),
                stopLoss: sl, takeProfit: tp
            )
        } else if activePillarsSell > activePillarsBuy && currentPillars >= minPillars && hasVolume {
            let baseConfidence = Double(currentPillars) / 6.0 * 100
            let adjustedConfidence = min(baseConfidence * confidenceFactors.values.reduce(1.0, *), 100)

            let sl = indicators.currentPrice + (indicators.atr * 1.0)
            let tp = indicators.currentPrice - (indicators.atr * 2.0)

            return ScalpingSignal(
                type: .sell, symbol: symbol, price: indicators.currentPrice,
                confidence: adjustedConfidence, score: currentPillars, sellScore: 0,
                indicators: indicators, confidenceFactors: confidenceFactors, timestamp: Date(),
                stopLoss: sl, takeProfit: tp
            )
        }

        return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice, confidence: 0, score: 0, sellScore: 0, indicators: indicators, confidenceFactors: [:], timestamp: Date())
    }

    private func applyQualityFilters(_ signal: ScalpingSignal, symbol: String) async -> ScalpingSignal? {
        guard signal.type != .none && signal.confidence >= 75 else { return nil }

        // FIXED: 5 minute cooldown between signals per symbol
        if let last = lastSignalTime[symbol], Date().timeIntervalSince(last) < 300 {
            return nil
        }

        lastSignalTime[symbol] = Date()
        return signal
    }

    // FIXED: NEW R:R VALIDATION
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
        let prev2 = candles[candles.count-3]

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