// ScalpingSignalEngine.swift
import Foundation

actor ScalpingSignalEngine {
    private let marketData: MarketDataProvider
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol
    
    // Multi-timeframe analysis
    private let timeframes = ["1m", "5m", "15m", "1h"]
    private var lastSignalTime: [String: Date] = [:]
    
    // Signal quality tracking
    private var signalQualityHistory: [String: [SignalQuality]] = [:]
    private let maxQualityHistory = 100
    
    init(marketData: MarketDataProvider, tradeHistory: RefactoredTradeHistoryManager,
         riskManager: RiskManagerProtocol) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
    }
    
    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        // Check if we can trade based on risk
        guard await riskManager.canOpenTrade(for: symbol) else {
            print("⚠️ Risk manager prevents new trades for \(symbol)")
            return nil
        }
        
        // Get multi-timeframe data
        var candlesByTimeframe: [String: [Kline]] = [:]
        for tf in timeframes {
            candlesByTimeframe[tf] = await marketData.getCandles(symbol: symbol, timeframe: tf)
        }
        
        guard validateData(candlesByTimeframe) else {
            print("📊 Insufficient data for \(symbol)")
            return nil
        }
        
        // Calculate all indicators
        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe)
        
        // Generate signal with multi-indicator confirmation
        let signal = generateSignal(symbol: symbol, indicators: indicators)
        
        // Apply quality filters
        guard let finalSignal = await applyQualityFilters(signal, symbol: symbol) else {
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
    
    private func generateSignal(symbol: String, indicators: IndicatorSet) -> ScalpingSignal {
        var buyScore = 0
        var sellScore = 0
        var confidenceFactors: [String: Double] = [:]
        
        // ===== RSI (Weight: 15) =====
        if indicators.rsi < 30 {
            buyScore += 15
            confidenceFactors["RSI Oversold"] = 0.9
        } else if indicators.rsi < 40 {
            buyScore += 10
            confidenceFactors["RSI Near Oversold"] = 0.7
        } else if indicators.rsi > 70 {
            sellScore += 15
            confidenceFactors["RSI Overbought"] = 0.9
        } else if indicators.rsi > 60 {
            sellScore += 10
            confidenceFactors["RSI Near Overbought"] = 0.7
        }
        
        // ===== Stochastic (Weight: 15) =====
        if indicators.stochasticK < 20 && indicators.stochasticD < 20 {
            buyScore += 15
            confidenceFactors["Stochastic Oversold"] = 0.9
        } else if indicators.stochasticK < 30 {
            buyScore += 8
            confidenceFactors["Stochastic Near Oversold"] = 0.6
        } else if indicators.stochasticK > 80 && indicators.stochasticD > 80 {
            sellScore += 15
            confidenceFactors["Stochastic Overbought"] = 0.9
        } else if indicators.stochasticK > 70 {
            sellScore += 8
            confidenceFactors["Stochastic Near Overbought"] = 0.6
        }
        
        // ===== CCI (Weight: 10) =====
        if indicators.cci < -100 {
            buyScore += 10
            confidenceFactors["CCI Extreme Oversold"] = 0.85
        } else if indicators.cci < -50 {
            buyScore += 5
            confidenceFactors["CCI Oversold"] = 0.6
        } else if indicators.cci > 100 {
            sellScore += 10
            confidenceFactors["CCI Extreme Overbought"] = 0.85
        } else if indicators.cci > 50 {
            sellScore += 5
            confidenceFactors["CCI Overbought"] = 0.6
        }
        
        // ===== Parabolic SAR (Weight: 10) =====
        if indicators.sar < indicators.currentPrice {
            buyScore += 10
            confidenceFactors["SAR Bullish"] = 0.8
        } else {
            sellScore += 10
            confidenceFactors["SAR Bearish"] = 0.8
        }
        
        // ===== Moving Average Alignment (Weight: 20) =====
        // Primary timeframe (1m)
        if indicators.ema9 > indicators.ema21 && indicators.ema21 > indicators.ema50 {
            buyScore += 10
            confidenceFactors["MA Bullish 1m"] = 0.8
        } else if indicators.ema9 < indicators.ema21 && indicators.ema21 < indicators.ema50 {
            sellScore += 10
            confidenceFactors["MA Bearish 1m"] = 0.8
        }
        
        // Multi-timeframe alignment
        if indicators.ema9_5m > indicators.ema21_5m {
            buyScore += 5
            confidenceFactors["MA Bullish 5m"] = 0.7
        } else {
            sellScore += 5
            confidenceFactors["MA Bearish 5m"] = 0.7
        }
        
        // ===== Bollinger Bands (Weight: 10) =====
        if indicators.bbPosition < 0.2 {
            buyScore += 10
            confidenceFactors["BB Lower Touch"] = 0.85
        } else if indicators.bbPosition < 0.4 {
            buyScore += 5
            confidenceFactors["BB Near Lower"] = 0.6
        } else if indicators.bbPosition > 0.8 {
            sellScore += 10
            confidenceFactors["BB Upper Touch"] = 0.85
        } else if indicators.bbPosition > 0.6 {
            sellScore += 5
            confidenceFactors["BB Near Upper"] = 0.6
        }
        
        // ===== Volume Confirmation (Weight: 10) =====
        if indicators.volumeRatio > 1.5 {
            if buyScore > sellScore {
                buyScore += 10
                confidenceFactors["Strong Volume Bullish"] = 0.9
            } else if sellScore > buyScore {
                sellScore += 10
                confidenceFactors["Strong Volume Bearish"] = 0.9
            }
        } else if indicators.volumeRatio > 1.2 {
            if buyScore > sellScore {
                buyScore += 5
                confidenceFactors["Above Avg Volume Bullish"] = 0.7
            } else if sellScore > buyScore {
                sellScore += 5
                confidenceFactors["Above Avg Volume Bearish"] = 0.7
            }
        }
        
        // ===== Support/Resistance (Weight: 5) =====
        let distanceToSupport = abs(indicators.currentPrice - indicators.support) / indicators.currentPrice * 100
        let distanceToResistance = abs(indicators.currentPrice - indicators.resistance) / indicators.currentPrice * 100
        
        if distanceToSupport < 0.1 { // Within 0.1% of support
            buyScore += 5
            confidenceFactors["At Support"] = 0.85
        } else if distanceToResistance < 0.1 { // Within 0.1% of resistance
            sellScore += 5
            confidenceFactors["At Resistance"] = 0.85
        }
        
        // ===== Price Pattern (Weight: 5) =====
        switch indicators.pricePattern {
        case .bullishEngulfing, .hammer, .morningStar:
            buyScore += 5
            confidenceFactors["Bullish Pattern"] = 0.8
        case .bearishEngulfing, .shootingStar, .eveningStar:
            sellScore += 5
            confidenceFactors["Bearish Pattern"] = 0.8
        default:
            break
        }
        
        // ===== Session Analysis (Weight: 5) =====
        let session = indicators.sessions
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
        // Trade during active sessions for better liquidity
        if hour >= 8 && hour <= 16 { // London session
            confidenceFactors["London Session"] = 1.1
        } else if hour >= 13 && hour <= 21 { // Overlap London/US
            confidenceFactors["Session Overlap"] = 1.2
        } else if hour >= 21 || hour <= 2 { // Asia session
            confidenceFactors["Asia Session"] = 0.9
        }
        
        // ===== Trend Strength (Weight: 5) =====
        if indicators.trendStrength > 25 { // Strong trend
            if buyScore > sellScore {
                buyScore += 5
                confidenceFactors["Strong Uptrend"] = 0.9
            } else if sellScore > buyScore {
                sellScore += 5
                confidenceFactors["Strong Downtrend"] = 0.9
            }
        }
        
        // ===== Market Regime Adjustment =====
        var regimeMultiplier = 1.0
        switch indicators.regime {
        case .trending:
            regimeMultiplier = 1.2
            confidenceFactors["Trending Market"] = 1.2
        case .ranging:
            regimeMultiplier = 0.8
            confidenceFactors["Ranging Market"] = 0.8
        case .volatile:
            regimeMultiplier = 0.7
            confidenceFactors["Volatile Market"] = 0.7
        }
        
        // Determine signal
        let totalScore = max(buyScore, sellScore)
        let confidence = min(Double(totalScore) / 70.0 * 100 * regimeMultiplier, 100)
        
        // Calculate average confidence factor
        let avgFactor = confidenceFactors.values.reduce(1.0, *)
        let adjustedConfidence = min(confidence * avgFactor, 100)
        
        if buyScore > sellScore && buyScore >= 15 {
            return ScalpingSignal(
                type: .buy,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence,
                score: buyScore,
                sellScore: sellScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date()
            )
        } else if sellScore > buyScore && sellScore >= 15 {
            return ScalpingSignal(
                type: .sell,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence,
                score: sellScore,
                sellScore: buyScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date()
            )
        }
        
        return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice,
                               confidence: 0, score: 0, sellScore: 0, indicators: indicators,
                               confidenceFactors: [:], timestamp: Date())
    }
    
    private func applyQualityFilters(_ signal: ScalpingSignal, symbol: String) async -> ScalpingSignal? {
        guard signal.type != .none else { return nil }
        
        // Filter 1: Minimum confidence threshold
        guard signal.confidence >= 20 else { // Lowered from 40 to 20
            print("📊 Signal rejected: Confidence too low (\(String(format: "%.1f", signal.confidence))%)")
            return nil
        }
        
        // Filter 2: Check cooldown period (avoid overtrading)
        if let lastSignal = lastSignalTime[symbol],
           Date().timeIntervalSince(lastSignal) < 180 { // 3 minutes cooldown
            print("📊 Signal rejected: Cooldown period active for \(symbol)")
            return nil
        }
        
        // Filter 3: Historical performance of similar signals
        let qualityHistory = signalQualityHistory[symbol] ?? []
        if qualityHistory.count >= 10 {
            let similarSignals = qualityHistory.filter {
                abs($0.confidence - signal.confidence) < 10 && $0.type == signal.type
            }
            
            if !similarSignals.isEmpty {
                // FIX: Properly handle optional wasWin by filtering out nil values
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
        
        // Filter 4: Spread check (for forex pairs)
        if symbol.contains("USDT") {
            // For crypto, check if price is within reasonable range
            let spread = signal.indicators.atr / signal.price * 10000 // Spread in basis points
            if spread > 10 { // More than 10 basis points spread
                print("📊 Signal rejected: Spread too high (\(String(format: "%.1f", spread)) bps)")
                return nil
            }
        }
        
        // Filter 5: Check for conflicting signals in last 5 minutes
        let recentSignals = signalQualityHistory[symbol]?.filter {
            Date().timeIntervalSince($0.timestamp) < 300
        } ?? []
        
        let conflictingSignals = recentSignals.filter { $0.type != signal.type }
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
            wasWin: nil // Will be updated when trade closes
        )
        history.append(quality)
        if history.count > maxQualityHistory {
            history.removeFirst()
        }
        signalQualityHistory[signal.symbol] = history
    }
    
    func updateSignalQuality(symbol: String, type: SignalType, confidence: Double, wasWin: Bool) async {
        var history = signalQualityHistory[symbol] ?? []
        if let index = history.lastIndex(where: { $0.type == type &&
                                                  abs($0.confidence - confidence) < 5 &&
                                                  $0.wasWin == nil }) {
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
        guard candles.count >= 5 else { return .none }
        
        let last5 = Array(candles.suffix(5))
        
        // Bullish Engulfing
        if last5.count >= 2 {
            let prev = last5[last5.count - 2]
            let curr = last5.last!
            
            if prev.close < prev.open && // Previous red candle
               curr.close > curr.open && // Current green candle
               curr.open < prev.close && // Opens below previous close
               curr.close > prev.open {  // Closes above previous open
                return .bullishEngulfing
            }
            
            // Bearish Engulfing
            if prev.close > prev.open && // Previous green candle
               curr.close < curr.open && // Current red candle
               curr.open > prev.close && // Opens above previous close
               curr.close < prev.open {  // Closes below previous open
                return .bearishEngulfing
            }
        }
        
        // Hammer
        if last5.count >= 1 {
            let curr = last5.last!
            let body = abs(curr.close - curr.open)
            let lowerWick = min(curr.open, curr.close) - curr.low
            let upperWick = curr.high - max(curr.open, curr.close)
            
            if lowerWick > body * 2 && upperWick < body * 0.3 {
                return curr.close > curr.open ? .hammer : .invertedHammer
            }
        }
        
        return .none
    }
    
    private func detectMarketRegime(_ candles1m: [Kline], _ candles5m: [Kline], _ candles1h: [Kline]) async -> MarketRegime {
        let atr1m = AdvancedIndicators.atr(candles1m, period: 20).last ?? 0
        let atr5m = AdvancedIndicators.atr(candles5m, period: 20).last ?? 0
        let price1m = candles1m.last?.close ?? 0
        
        let volatility1m = atr1m / price1m * 100 // ATR%
        let volatility5m = atr5m / price1m * 100
        
        // Check if trending
        let closes1h = candles1h.map { $0.close }
        let sma20_1h = closes1h.suffix(20).reduce(0, +) / 20
        let sma50_1h = closes1h.suffix(50).reduce(0, +) / 50
        let trendStrength = abs(sma20_1h - sma50_1h) / sma50_1h * 100
        
        if volatility1m > 0.5 || volatility5m > 0.8 {
            return .volatile
        } else if trendStrength > 0.5 {
            return .trending
        } else {
            return .ranging
        }
    }
}

// MARK: - Supporting Types

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
    let type: SignalType
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
    let type: SignalType
    let confidence: Double
    let timestamp: Date
    var wasWin: Bool?
}

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
