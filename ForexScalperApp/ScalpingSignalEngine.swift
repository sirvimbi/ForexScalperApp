// ScalpingSignalEngine.swift - FULLY FIXED VERSION
import Foundation

actor ScalpingSignalEngine {
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol
    private let config: ScalpingConfig
    
    // Multi-timeframe analysis
    private let timeframes = ["1m", "5m", "15m", "1h"]
    private var lastSignalTime: [String: Date] = [:]
    
    // Signal quality tracking
    private var signalQualityHistory: [String: [SignalQuality]] = [:]
    private let maxQualityHistory = 100
    
    init(marketData: MarketDataProvider, tradeHistory: RefactoredTradeHistoryManager,
         riskManager: RiskManagerProtocol, config: ScalpingConfig = .shared) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
        self.config = config
    }
    
    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        print("🔍 EVALUATING \(symbol) for signals")
        
        // Check if we can trade based on risk
        guard await riskManager.canOpenTrade(for: symbol) else {
            print("⚠️ Risk manager prevents new trades for \(symbol)")
            return nil
        }
        
        // Get multi-timeframe data
        var candlesByTimeframe: [String: [Kline]] = [:]
        for tf in timeframes {
            candlesByTimeframe[tf] = await marketData.getCandles(symbol: symbol, timeframe: tf)
            print("📊 \(symbol) \(tf) candles: \(candlesByTimeframe[tf]?.count ?? 0)")
        }
        
        guard validateData(candlesByTimeframe) else {
            print("📊 Insufficient data for \(symbol)")
            return nil
        }
        
        // Calculate all indicators
        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe)
        
        // Print key indicators for debugging
        print("📊 Indicators for \(symbol): RSI=\(String(format: "%.1f", indicators.rsi)), Price=\(indicators.currentPrice)")
        print("📊 MA Status: EMA9=\(indicators.ema9), EMA21=\(indicators.ema21), EMA50=\(indicators.ema50)")
        print("📊 BB Position: \(String(format: "%.2f", indicators.bbPosition))")
        print("📊 Volume Ratio: \(String(format: "%.2f", indicators.volumeRatio))")
        
        // Generate signal with multi-indicator confirmation
        let signal = await generateSignal(symbol: symbol, indicators: indicators)
        
        // Print signal result
        if signal.type != ScalpingSignalType.none {
            print("✅ SIGNAL GENERATED: \(symbol) \(signal.type) with confidence \(String(format: "%.1f", signal.confidence))% (Score: \(signal.score))")
        } else {
            print("❌ No signal generated for \(symbol)")
            return nil
        }
        
        // Apply quality filters
        guard let finalSignal = await applyQualityFilters(signal, symbol: symbol) else {
            print("📊 Signal rejected by quality filters for \(symbol)")
            return nil
        }
        
        // Track signal quality for adaptive learning
        await trackSignalQuality(finalSignal)
        
        return finalSignal
    }
    
    private func calculateAllIndicators(symbol: String, candlesByTimeframe: [String: [Kline]]) async -> IndicatorSet {
        let candles1m = candlesByTimeframe["1m"] ?? []
        let candles5m = candlesByTimeframe["5m"] ?? []
        let candles15m = candlesByTimeframe["15m"] ?? []
        let candles1h = candlesByTimeframe["1h"] ?? []
        
        // Calculate indicators for primary timeframe (1m)
        let rsi1m = Indicators.rsi(candles1m.map { $0.close }, period: 14).last ?? 50
        let stoch1m = AdvancedIndicators.stochastic(candles1m, periodK: 14, periodD: 3)
        let cci1m = AdvancedIndicators.cci(candles1m, period: 20).last ?? 0
        let sar1m = AdvancedIndicators.parabolicSAR(candles1m).last ?? candles1m.last?.close ?? 0
        let atr1m = AdvancedIndicators.atr(candles1m, period: 14).last ?? 0
        let currentPrice = candles1m.last?.close ?? 0
        
        // Moving averages for multiple timeframes
        let ema9_1m = Indicators.ema(candles1m.map { $0.close }, period: 9).last ?? currentPrice
        let ema21_1m = Indicators.ema(candles1m.map { $0.close }, period: 21).last ?? currentPrice
        let ema50_1m = Indicators.ema(candles1m.map { $0.close }, period: 50).last ?? currentPrice
        
        let ema9_5m = Indicators.ema(candles5m.map { $0.close }, period: 9).last ?? currentPrice
        let ema21_5m = Indicators.ema(candles5m.map { $0.close }, period: 21).last ?? currentPrice
        let ema50_5m = Indicators.ema(candles5m.map { $0.close }, period: 50).last ?? currentPrice
        
        // Bollinger Bands
        let bb1m = Indicators.bollingerBands(candles1m.map { $0.close }, period: 20, stdDev: 2.0)
        let bbPosition = (currentPrice - (bb1m.lower.last ?? 0)) /
                         max((bb1m.upper.last ?? 1) - (bb1m.lower.last ?? 0), 0.0001)
        
        // Volume analysis
        let volumeProfile = AdvancedIndicators.volumeProfile(Array(candles1m.suffix(50)))
        let avgVolume = candles1m.suffix(20).map { $0.volume }.reduce(0, +) / 20
        let volumeRatio = (candles1m.last?.volume ?? 0) / max(avgVolume, 0.01)
        
        // Support/Resistance
        let srLevels = AdvancedIndicators.supportResistance(candles1h, lookback: 100)
        
        // Session analysis
        let sessions = AdvancedIndicators.sessionAnalysis(candles1m)
        
        // Trend strength (ADX approximation)
        let trendStrength = calculateTrendStrength(candles1m)
        
        // Price action patterns
        let pattern = detectPricePattern(candles1m)
        
        // Market regime
        let regime = await detectMarketRegime(candles1m, candles5m, candles1h)
        
        return IndicatorSet(
            rsi: rsi1m,
            stochasticK: stoch1m.k.last ?? 50,
            stochasticD: stoch1m.d.last ?? 50,
            cci: cci1m,
            sar: sar1m,
            atr: atr1m,
            ema9: ema9_1m,
            ema21: ema21_1m,
            ema50: ema50_1m,
            ema9_5m: ema9_5m,
            ema21_5m: ema21_5m,
            ema50_5m: ema50_5m,
            bbPosition: bbPosition,
            volumeRatio: volumeRatio,
            volumeProfilePOC: volumeProfile.poc,
            support: srLevels.support,
            resistance: srLevels.resistance,
            sessions: sessions,
            trendStrength: trendStrength,
            pricePattern: pattern,
            regime: regime,
            currentPrice: currentPrice
        )
    }
    
    private func generateSignal(symbol: String, indicators: IndicatorSet) async -> ScalpingSignal {
        var buyScore = 0
        var sellScore = 0
        var confidenceFactors: [String: Double] = [:]
        
        // Get current config values from the shared instance
        let config = await self.config
        let rsiWeight = await Int(config.rsiWeight)
        let stochasticWeight = await Int(config.stochasticWeight)
        let cciWeight = await Int(config.cciWeight)
        let maWeight = await Int(config.maWeight)
        let bbWeight = await Int(config.bbWeight)
        let volumeWeight = await Int(config.volumeWeight)
        let patternWeight = await Int(config.patternWeight)
        let minScore = await Int(config.minScore)
        
        let halfRsiWeight = max(1, Int(Double(rsiWeight) * 0.67))
        let halfStochWeight = max(1, Int(Double(stochasticWeight) * 0.67))
        let halfCCIWeight = max(1, Int(Double(cciWeight) * 0.67))
        let halfBBWeight = max(1, Int(Double(bbWeight) * 0.67))
        let halfVolumeWeight = max(1, Int(Double(volumeWeight) * 0.67))
        let halfPatternWeight = max(1, Int(Double(patternWeight) * 0.67))
        
        // ===== RSI =====
        if indicators.rsi < 30 {
            buyScore += rsiWeight
            confidenceFactors["RSI Oversold"] = 0.9
            print("📊 RSI: Oversold (+\(rsiWeight) buy)")
        } else if indicators.rsi < 40 {
            buyScore += halfRsiWeight
            confidenceFactors["RSI Near Oversold"] = 0.7
            print("📊 RSI: Near Oversold (+\(halfRsiWeight) buy)")
        } else if indicators.rsi > 70 {
            sellScore += rsiWeight
            confidenceFactors["RSI Overbought"] = 0.9
            print("📊 RSI: Overbought (+\(rsiWeight) sell)")
        } else if indicators.rsi > 60 {
            sellScore += halfRsiWeight
            confidenceFactors["RSI Near Overbought"] = 0.7
            print("📊 RSI: Near Overbought (+\(halfRsiWeight) sell)")
        }
        
        // ===== Stochastic =====
        if indicators.stochasticK < 20 && indicators.stochasticD < 20 {
            buyScore += stochasticWeight
            confidenceFactors["Stochastic Oversold"] = 0.9
            print("📊 Stochastic: Oversold (+\(stochasticWeight) buy)")
        } else if indicators.stochasticK < 30 {
            buyScore += halfStochWeight
            confidenceFactors["Stochastic Near Oversold"] = 0.6
            print("📊 Stochastic: Near Oversold (+\(halfStochWeight) buy)")
        } else if indicators.stochasticK > 80 && indicators.stochasticD > 80 {
            sellScore += stochasticWeight
            confidenceFactors["Stochastic Overbought"] = 0.9
            print("📊 Stochastic: Overbought (+\(stochasticWeight) sell)")
        } else if indicators.stochasticK > 70 {
            sellScore += halfStochWeight
            confidenceFactors["Stochastic Near Overbought"] = 0.6
            print("📊 Stochastic: Near Overbought (+\(halfStochWeight) sell)")
        }
        
        // ===== CCI =====
        if indicators.cci < -100 {
            buyScore += cciWeight
            confidenceFactors["CCI Extreme Oversold"] = 0.85
            print("📊 CCI: Extreme Oversold (+\(cciWeight) buy)")
        } else if indicators.cci < -50 {
            buyScore += halfCCIWeight
            confidenceFactors["CCI Oversold"] = 0.6
            print("📊 CCI: Oversold (+\(halfCCIWeight) buy)")
        } else if indicators.cci > 100 {
            sellScore += cciWeight
            confidenceFactors["CCI Extreme Overbought"] = 0.85
            print("📊 CCI: Extreme Overbought (+\(cciWeight) sell)")
        } else if indicators.cci > 50 {
            sellScore += halfCCIWeight
            confidenceFactors["CCI Overbought"] = 0.6
            print("📊 CCI: Overbought (+\(halfCCIWeight) sell)")
        }
        
        // ===== Parabolic SAR =====
        if indicators.sar < indicators.currentPrice {
            buyScore += maWeight / 2
            confidenceFactors["SAR Bullish"] = 0.8
            print("📊 SAR: Bullish (+\(maWeight/2) buy)")
        } else {
            sellScore += maWeight / 2
            confidenceFactors["SAR Bearish"] = 0.8
            print("📊 SAR: Bearish (+\(maWeight/2) sell)")
        }
        
        // ===== Moving Average Alignment =====
        if indicators.ema9 > indicators.ema21 && indicators.ema21 > indicators.ema50 {
            buyScore += maWeight / 2
            confidenceFactors["MA Bullish 1m"] = 0.8
            print("📊 MA 1m: Bullish alignment (+\(maWeight/2) buy)")
        } else if indicators.ema9 < indicators.ema21 && indicators.ema21 < indicators.ema50 {
            sellScore += maWeight / 2
            confidenceFactors["MA Bearish 1m"] = 0.8
            print("📊 MA 1m: Bearish alignment (+\(maWeight/2) sell)")
        }
        
        if indicators.ema9_5m > indicators.ema21_5m {
            buyScore += maWeight / 4
            confidenceFactors["MA Bullish 5m"] = 0.7
            print("📊 MA 5m: Bullish (+\(maWeight/4) buy)")
        } else {
            sellScore += maWeight / 4
            confidenceFactors["MA Bearish 5m"] = 0.7
            print("📊 MA 5m: Bearish (+\(maWeight/4) sell)")
        }
        
        // ===== Bollinger Bands =====
        if indicators.bbPosition < 0.2 {
            buyScore += bbWeight
            confidenceFactors["BB Lower Touch"] = 0.85
            print("📊 BB: Lower touch (+\(bbWeight) buy)")
        } else if indicators.bbPosition < 0.4 {
            buyScore += halfBBWeight
            confidenceFactors["BB Near Lower"] = 0.6
            print("📊 BB: Near lower (+\(halfBBWeight) buy)")
        } else if indicators.bbPosition > 0.8 {
            sellScore += bbWeight
            confidenceFactors["BB Upper Touch"] = 0.85
            print("📊 BB: Upper touch (+\(bbWeight) sell)")
        } else if indicators.bbPosition > 0.6 {
            sellScore += halfBBWeight
            confidenceFactors["BB Near Upper"] = 0.6
            print("📊 BB: Near upper (+\(halfBBWeight) sell)")
        }
        
        // ===== Volume Confirmation =====
        if indicators.volumeRatio > 1.5 {
            if buyScore > sellScore {
                buyScore += volumeWeight
                confidenceFactors["Strong Volume Bullish"] = 0.9
                print("📊 Volume: Strong bullish (+\(volumeWeight) buy)")
            } else if sellScore > buyScore {
                sellScore += volumeWeight
                confidenceFactors["Strong Volume Bearish"] = 0.9
                print("📊 Volume: Strong bearish (+\(volumeWeight) sell)")
            }
        } else if indicators.volumeRatio > 1.2 {
            if buyScore > sellScore {
                buyScore += halfVolumeWeight
                confidenceFactors["Above Avg Volume Bullish"] = 0.7
                print("📊 Volume: Above avg bullish (+\(halfVolumeWeight) buy)")
            } else if sellScore > buyScore {
                sellScore += halfVolumeWeight
                confidenceFactors["Above Avg Volume Bearish"] = 0.7
                print("📊 Volume: Above avg bearish (+\(halfVolumeWeight) sell)")
            }
        }
        
        // ===== Support/Resistance =====
        let distanceToSupport = abs(indicators.currentPrice - indicators.support) / indicators.currentPrice * 100
        let distanceToResistance = abs(indicators.currentPrice - indicators.resistance) / indicators.currentPrice * 100
        
        if distanceToSupport < 0.1 {
            buyScore += patternWeight
            confidenceFactors["At Support"] = 0.85
            print("📊 S/R: At support (+\(patternWeight) buy)")
        } else if distanceToResistance < 0.1 {
            sellScore += patternWeight
            confidenceFactors["At Resistance"] = 0.85
            print("📊 S/R: At resistance (+\(patternWeight) sell)")
        }
        
        // ===== Price Pattern =====
        switch indicators.pricePattern {
        case PricePattern.bullishEngulfing, PricePattern.hammer, PricePattern.morningStar:
            buyScore += patternWeight
            confidenceFactors["Bullish Pattern"] = 0.8
            print("📊 Pattern: Bullish (+\(patternWeight) buy)")
        case PricePattern.bearishEngulfing, PricePattern.shootingStar, PricePattern.eveningStar:
            sellScore += patternWeight
            confidenceFactors["Bearish Pattern"] = 0.8
            print("📊 Pattern: Bearish (+\(patternWeight) sell)")
        default:
            break
        }
        
        // ===== Session Analysis =====
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
        if hour >= 8 && hour <= 16 {
            confidenceFactors["London Session"] = 1.1
        } else if hour >= 13 && hour <= 21 {
            confidenceFactors["Session Overlap"] = 1.2
        } else if hour >= 21 || hour <= 2 {
            confidenceFactors["Asia Session"] = 0.9
        }
        
        // ===== Trend Strength =====
        if indicators.trendStrength > 25 {
            if buyScore > sellScore {
                buyScore += halfPatternWeight
                confidenceFactors["Strong Uptrend"] = 0.9
                print("📊 Trend: Strong uptrend (+\(halfPatternWeight) buy)")
            } else if sellScore > buyScore {
                sellScore += halfPatternWeight
                confidenceFactors["Strong Downtrend"] = 0.9
                print("📊 Trend: Strong downtrend (+\(halfPatternWeight) sell)")
            }
        }
        
        // ===== Market Regime Adjustment =====
        var regimeMultiplier = 1.0
        switch indicators.regime {
        case MarketRegime.trending:
            regimeMultiplier = 1.2
            confidenceFactors["Trending Market"] = 1.2
        case MarketRegime.ranging:
            regimeMultiplier = 0.8
            confidenceFactors["Ranging Market"] = 0.8
        case MarketRegime.volatile:
            regimeMultiplier = 0.7
            confidenceFactors["Volatile Market"] = 0.7
        }
        
        // Print scores
        print("📊 Final scores - Buy: \(buyScore), Sell: \(sellScore), Min required: \(minScore)")
        
        // Determine signal
        let totalScore = max(buyScore, sellScore)
        let confidence = min(Double(totalScore) / 70.0 * 100 * regimeMultiplier, 100)
        
        // Calculate average confidence factor
        let avgFactor = confidenceFactors.values.reduce(1.0, *)
        let adjustedConfidence = min(confidence * avgFactor, 100)
        
        if buyScore > sellScore && buyScore >= minScore {
            print("✅ BUY signal generated with score \(buyScore)")
            return ScalpingSignal(
                type: ScalpingSignalType.buy,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence,
                score: buyScore,
                sellScore: sellScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date()
            )
        } else if sellScore > buyScore && sellScore >= minScore {
            print("✅ SELL signal generated with score \(sellScore)")
            return ScalpingSignal(
                type: ScalpingSignalType.sell,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence,
                score: sellScore,
                sellScore: buyScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date()
            )
        } else if buyScore == sellScore && buyScore >= minScore {
            // If tied, random choice
            let randomType: ScalpingSignalType = Bool.random() ? .buy : .sell
            print("✅ Tied scores, random \(randomType) signal generated")
            return ScalpingSignal(
                type: randomType,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence * 0.8,
                score: buyScore,
                sellScore: sellScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date()
            )
        }
        
        return ScalpingSignal(
            type: ScalpingSignalType.none,
            symbol: symbol,
            price: indicators.currentPrice,
            confidence: 0,
            score: 0,
            sellScore: 0,
            indicators: indicators,
            confidenceFactors: [:],
            timestamp: Date()
        )
    }
    
    private func applyQualityFilters(_ signal: ScalpingSignal, symbol: String) async -> ScalpingSignal? {
        guard signal.type != ScalpingSignalType.none else { return nil }
        
        // Get current config values
        let confidenceThreshold = await config.confidenceThreshold
        let spreadTolerance = await config.spreadTolerance
        let cooldownSeconds = await config.cooldownSeconds
        
        // Filter 1: Minimum confidence threshold (configurable)
        guard signal.confidence >= confidenceThreshold else {
            print("📊 Signal rejected: Confidence too low (\(String(format: "%.1f", signal.confidence))% / threshold: \(String(format: "%.1f", confidenceThreshold))%)")
            return nil
        }
        
        // Filter 2: Check cooldown period (avoid overtrading)
        if let lastSignal = lastSignalTime[symbol],
           Date().timeIntervalSince(lastSignal) < cooldownSeconds {
            print("📊 Signal rejected: Cooldown period active for \(symbol) (\(Int(Date().timeIntervalSince(lastSignal)))s/\(Int(cooldownSeconds))s)")
            return nil
        }
        
        // Filter 3: Historical performance of similar signals
        let qualityHistory = signalQualityHistory[symbol] ?? []
        if qualityHistory.count >= 10 {
            // FIXED: Explicit parameter name in filter closure
            let similarSignals = qualityHistory.filter { quality in
                abs(quality.confidence - signal.confidence) < 10 && quality.type == signal.type
            }
            
            if !similarSignals.isEmpty {
                let wins = similarSignals.compactMap { $0.wasWin }.filter { $0 }.count
                let total = similarSignals.compactMap { $0.wasWin }.count
                
                if total > 0 {
                    let winRate = Double(wins) / Double(total)
                    
                    // If similar signals have poor performance, reduce confidence
                    if winRate < 0.5 && signal.confidence > 80 {
                        let adjustedSignal = signal.withConfidence(signal.confidence * 0.8)
                        print("📊 Signal confidence adjusted: \(String(format: "%.1f", signal.confidence))% -> \(String(format: "%.1f", adjustedSignal.confidence))% based on historical performance")
                        return adjustedSignal
                    }
                }
            }
        }
        
        // Filter 4: Spread check (configurable)
        if symbol.contains("USDT") {
            let spread = signal.indicators.atr / signal.price * 10000
            if spread > spreadTolerance {
                print("📊 Signal rejected: Spread too high (\(String(format: "%.1f", spread)) bps / tolerance: \(String(format: "%.1f", spreadTolerance)) bps)")
                return nil
            }
        }
        
        // Filter 5: Check for conflicting signals in last 5 minutes
        // FIXED: Explicit parameter name in filter closure
        let recentSignals = signalQualityHistory[symbol]?.filter { quality in
            Date().timeIntervalSince(quality.timestamp) < 300
        } ?? []
        
        let conflictingSignals = recentSignals.filter { quality in
            quality.type != signal.type
        }
        if !conflictingSignals.isEmpty {
            print("📊 Signal rejected: Conflicting signals in last 5 minutes for \(symbol)")
            return nil
        }
        
        lastSignalTime[symbol] = Date()
        return signal
    }
    
    private func trackSignalQuality(_ signal: ScalpingSignal) async {
        var history = signalQualityHistory[signal.symbol] ?? []
        let quality = SignalQuality(
            type: signal.type,
            confidence: signal.confidence,
            timestamp: signal.timestamp,
            wasWin: nil as Bool?
        )
        history.append(quality)
        if history.count > maxQualityHistory {
            history.removeFirst()
        }
        signalQualityHistory[signal.symbol] = history
    }
    
    func updateSignalQuality(symbol: String, type: ScalpingSignalType, confidence: Double, wasWin: Bool) async {
        var history = signalQualityHistory[symbol] ?? []
        // FIXED: Explicit parameter name in lastIndex where closure
        if let index = history.lastIndex(where: { quality in
            quality.type == type &&
            abs(quality.confidence - confidence) < 5 &&
            quality.wasWin == nil
        }) {
            history[index].wasWin = wasWin
        }
        signalQualityHistory[symbol] = history
    }
    
    private func validateData(_ candlesByTimeframe: [String: [Kline]]) -> Bool {
        return candlesByTimeframe["1m"]?.count ?? 0 >= 100 &&
               candlesByTimeframe["5m"]?.count ?? 0 >= 50 &&
               candlesByTimeframe["15m"]?.count ?? 0 >= 30 &&
               candlesByTimeframe["1h"]?.count ?? 0 >= 20
    }
    
    private func calculateTrendStrength(_ candles: [Kline]) -> Double {
        guard candles.count >= 50 else { return 0 }
        
        let closes = candles.map { $0.close }
        let sma20 = closes.suffix(20).reduce(0, +) / 20
        let sma50 = closes.suffix(50).reduce(0, +) / 50
        
        let atr = AdvancedIndicators.atr(candles, period: 14).last ?? 0
        let slope = (sma20 - sma50) / sma50 * 100
        
        return abs(slope) / max(atr / sma20 * 100, 0.1) * 10
    }
    
    private func detectPricePattern(_ candles: [Kline]) -> PricePattern {
        guard candles.count >= 5 else { return PricePattern.none }
        
        let last5 = Array(candles.suffix(5))
        
        if last5.count >= 2 {
            let prev = last5[last5.count - 2]
            let curr = last5.last!
            
            if prev.close < prev.open &&
               curr.close > curr.open &&
               curr.open < prev.close &&
               curr.close > prev.open {
                return PricePattern.bullishEngulfing
            }
            
            if prev.close > prev.open &&
               curr.close < curr.open &&
               curr.open > prev.close &&
               curr.close < prev.open {
                return PricePattern.bearishEngulfing
            }
        }
        
        if last5.count >= 1 {
            let curr = last5.last!
            let body = abs(curr.close - curr.open)
            let lowerWick = min(curr.open, curr.close) - curr.low
            let upperWick = curr.high - max(curr.open, curr.close)
            
            if lowerWick > body * 2 && upperWick < body * 0.3 {
                return curr.close > curr.open ? PricePattern.hammer : PricePattern.invertedHammer
            }
        }
        
        return PricePattern.none
    }
    
    private func detectMarketRegime(_ candles1m: [Kline], _ candles5m: [Kline], _ candles1h: [Kline]) async -> MarketRegime {
        let atr1m = AdvancedIndicators.atr(candles1m, period: 20).last ?? 0
        let atr5m = AdvancedIndicators.atr(candles5m, period: 20).last ?? 0
        let price1m = candles1m.last?.close ?? 0
        
        let volatility1m = atr1m / price1m * 100
        let volatility5m = atr5m / price1m * 100
        
        let closes1h = candles1h.map { $0.close }
        let sma20_1h = closes1h.suffix(20).reduce(0, +) / 20
        let sma50_1h = closes1h.suffix(50).reduce(0, +) / 50
        let trendStrength = abs(sma20_1h - sma50_1h) / sma50_1h * 100
        
        if volatility1m > 0.5 || volatility5m > 0.8 {
            return MarketRegime.volatile
        } else if trendStrength > 0.5 {
            return MarketRegime.trending
        } else {
            return MarketRegime.ranging
        }
    }
}

// MARK: - Supporting Types (DEFINED ONCE - NO DUPLICATES)
struct IndicatorSet {
    let rsi: Double
    let stochasticK: Double
    let stochasticD: Double
    let cci: Double
    let sar: Double
    let atr: Double
    let ema9: Double
    let ema21: Double
    let ema50: Double
    let ema9_5m: Double
    let ema21_5m: Double
    let ema50_5m: Double
    let bbPosition: Double
    let volumeRatio: Double
    let volumeProfilePOC: Double
    let support: Double
    let resistance: Double
    let sessions: (asiaRange: (high: Double, low: Double),
                   londonRange: (high: Double, low: Double),
                   usRange: (high: Double, low: Double))
    let trendStrength: Double
    let pricePattern: PricePattern
    let regime: MarketRegime
    let currentPrice: Double
}

struct ScalpingSignal {
    let type: ScalpingSignalType
    let symbol: String
    let price: Double
    let confidence: Double
    let score: Int
    let sellScore: Int
    let indicators: IndicatorSet
    let confidenceFactors: [String: Double]
    let timestamp: Date
    
    func withConfidence(_ newConfidence: Double) -> ScalpingSignal {
        ScalpingSignal(
            type: type,
            symbol: symbol,
            price: price,
            confidence: newConfidence,
            score: score,
            sellScore: sellScore,
            indicators: indicators,
            confidenceFactors: confidenceFactors,
            timestamp: timestamp
        )
    }
}

struct SignalQuality {
    let type: ScalpingSignalType
    let confidence: Double
    let timestamp: Date
    var wasWin: Bool?
}

// ENUMS - DEFINED ONLY ONCE AT END OF FILE
enum PricePattern {
    case none
    case bullishEngulfing
    case bearishEngulfing
    case hammer
    case invertedHammer
    case morningStar
    case eveningStar
    case shootingStar
}

enum MarketRegime {
    case trending
    case ranging
    case volatile
}

enum ScalpingSignalType {
    case buy
    case sell
    case none
}
