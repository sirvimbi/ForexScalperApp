// ScalpingSignalEngine.swift
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
         riskManager: RiskManagerProtocol, config: ScalpingConfig) {
        self.marketData = marketData
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
        self.config = config
    }
    
    func evaluateScalpingSignal(symbol: String) async -> ScalpingSignal? {
        print("🔍 EVALUATING \(symbol) for scalping signal...")
        
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
        
        if !validateData(candlesByTimeframe, symbol: symbol) {
            return nil
        }
        
        // Calculate all indicators
        let indicators = await calculateAllIndicators(symbol: symbol, candlesByTimeframe: candlesByTimeframe)
        
        // Generate signal with multi-indicator confirmation
        let signal = await generateSignal(symbol: symbol, indicators: indicators)
        
        if signal.type == .none {
            print("❌ No signal for \(symbol). Scores - Buy: \(signal.score), Sell: \(signal.sellScore)")
            return nil
        }
        
        // Apply quality filters
        guard let finalSignal = await applyQualityFilters(signal, symbol: symbol) else {
            return nil
        }
        
        print("✅ SUCCESS: Generated \(finalSignal.type) signal for \(symbol) with \(Int(finalSignal.confidence))% confidence")
        
        // Track signal quality for adaptive learning
        await trackSignalQuality(finalSignal)
        
        return finalSignal
    }
    
    private func calculateAllIndicators(symbol: String, candlesByTimeframe: [String: [Kline]]) async -> IndicatorSet {
        let candles1m = candlesByTimeframe["1m"] ?? []
        let candles5m = candlesByTimeframe["5m"] ?? []
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
        
        // Get weights from config for "God Mode" precision
        let weights = await MainActor.run {
            (rsi: config.rsiWeight, stoch: config.stochasticWeight, cci: config.cciWeight,
             ma: config.maWeight, bb: config.bbWeight, vol: config.volumeWeight,
             pat: config.patternWeight)
        }
        
        // ===== RSI (Weight: Dynamic) =====
        if indicators.rsi < 30 {
            buyScore += Int(weights.rsi)
            confidenceFactors["RSI Oversold"] = 1.0 // Increased from 0.9
        } else if indicators.rsi < 40 {
            buyScore += Int(weights.rsi * 0.6)
            confidenceFactors["RSI Near Oversold"] = 0.8
        } else if indicators.rsi > 70 {
            sellScore += Int(weights.rsi)
            confidenceFactors["RSI Overbought"] = 1.0
        } else if indicators.rsi > 60 {
            sellScore += Int(weights.rsi * 0.6)
            confidenceFactors["RSI Near Overbought"] = 0.8
        }
        
        // ===== Stochastic (Weight: Dynamic) =====
        if indicators.stochasticK < 20 && indicators.stochasticD < 20 {
            buyScore += Int(weights.stoch)
            confidenceFactors["Stochastic Oversold"] = 1.0
        } else if indicators.stochasticK < 30 {
            buyScore += Int(weights.stoch * 0.5)
            confidenceFactors["Stochastic Near Oversold"] = 0.7
        } else if indicators.stochasticK > 80 && indicators.stochasticD > 80 {
            sellScore += Int(weights.stoch)
            confidenceFactors["Stochastic Overbought"] = 1.0
        } else if indicators.stochasticK > 70 {
            sellScore += Int(weights.stoch * 0.5)
            confidenceFactors["Stochastic Near Overbought"] = 0.7
        }
        
        // ===== CCI (Weight: Dynamic) =====
        if indicators.cci < -100 {
            buyScore += Int(weights.cci)
            confidenceFactors["CCI Extreme Oversold"] = 0.95
        } else if indicators.cci < -50 {
            buyScore += Int(weights.cci * 0.5)
            confidenceFactors["CCI Oversold"] = 0.7
        } else if indicators.cci > 100 {
            sellScore += Int(weights.cci)
            confidenceFactors["CCI Extreme Overbought"] = 0.95
        } else if indicators.cci > 50 {
            sellScore += Int(weights.cci * 0.5)
            confidenceFactors["CCI Overbought"] = 0.7
        }
        
        // ===== Parabolic SAR (Weight: 10) =====
        if indicators.sar < indicators.currentPrice {
            buyScore += 10
            confidenceFactors["SAR Bullish"] = 0.85
        } else {
            sellScore += 10
            confidenceFactors["SAR Bearish"] = 0.85
        }
        
        // ===== Moving Average Alignment (Weight: Dynamic) =====
        // Primary timeframe (1m)
        if indicators.ema9 > indicators.ema21 && indicators.ema21 > indicators.ema50 {
            buyScore += Int(weights.ma * 0.6)
            confidenceFactors["MA Bullish 1m"] = 0.9
        } else if indicators.ema9 < indicators.ema21 && indicators.ema21 < indicators.ema50 {
            sellScore += Int(weights.ma * 0.6)
            confidenceFactors["MA Bearish 1m"] = 0.9
        }
        
        // Multi-timeframe alignment
        if indicators.ema9_5m > indicators.ema21_5m {
            buyScore += Int(weights.ma * 0.4)
            confidenceFactors["MA Bullish 5m"] = 0.8
        } else {
            sellScore += Int(weights.ma * 0.4)
            confidenceFactors["MA Bearish 5m"] = 0.8
        }
        
        // ===== Bollinger Bands (Weight: Dynamic) =====
        if indicators.bbPosition < 0.15 {
            buyScore += Int(weights.bb)
            confidenceFactors["BB Lower Breakout"] = 0.95
        } else if indicators.bbPosition < 0.3 {
            buyScore += Int(weights.bb * 0.6)
            confidenceFactors["BB Near Lower"] = 0.75
        } else if indicators.bbPosition > 0.85 {
            sellScore += Int(weights.bb)
            confidenceFactors["BB Upper Breakout"] = 0.95
        } else if indicators.bbPosition > 0.7 {
            sellScore += Int(weights.bb * 0.6)
            confidenceFactors["BB Near Upper"] = 0.75
        }
        
        // ===== Volume Confirmation (Weight: Dynamic) =====
        if indicators.volumeRatio > 1.3 { // Lowered from 1.5
            if buyScore > sellScore {
                buyScore += Int(weights.vol)
                confidenceFactors["Strong Volume Bullish"] = 1.0
            } else if sellScore > buyScore {
                sellScore += Int(weights.vol)
                confidenceFactors["Strong Volume Bearish"] = 1.0
            }
        }
        
        // ===== Support/Resistance (Weight: 10) =====
        let distanceToSupport = abs(indicators.currentPrice - indicators.support) / indicators.currentPrice * 100
        let distanceToResistance = abs(indicators.currentPrice - indicators.resistance) / indicators.currentPrice * 100
        
        if distanceToSupport < 0.05 { // Within 0.05%
            buyScore += 10
            confidenceFactors["Major Support Bounce"] = 1.0
        } else if distanceToResistance < 0.05 {
            sellScore += 10
            confidenceFactors["Major Resistance Reject"] = 1.0
        }
        
        // ===== Price Pattern (Weight: Dynamic) =====
        switch indicators.pricePattern {
        case .bullishEngulfing, .hammer, .morningStar:
            buyScore += Int(weights.pat)
            confidenceFactors["Bullish Pattern Confirmation"] = 1.0
        case .bearishEngulfing, .shootingStar, .eveningStar:
            sellScore += Int(weights.pat)
            confidenceFactors["Bearish Pattern Confirmation"] = 1.0
        default:
            break
        }
        
        // ===== Session Analysis (Multiplier) =====
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
        if (hour >= 8 && hour <= 12) || (hour >= 13 && hour <= 17) { // London or US Prime
            confidenceFactors["Prime Session"] = 1.2
        }
        
        // ===== Trend Strength (Weight: 10) =====
        if indicators.trendStrength > 20 {
            if buyScore > sellScore {
                buyScore += 10
                confidenceFactors["Strong Trend Bullish"] = 1.1
            } else if sellScore > buyScore {
                sellScore += 10
                confidenceFactors["Strong Trend Bearish"] = 1.1
            }
        }
        
        // Determine signal
        let minScore = await MainActor.run { config.minScore }
        
        let totalScore = max(buyScore, sellScore)
        // Normalize score to 100 based on possible max (around 120-130 now)
        let baseConfidence = min(Double(totalScore) / 90.0 * 100, 100)
        
        // Calculate combined confidence factor (capped to avoid insane values)
        let combinedFactor = min(confidenceFactors.values.reduce(1.0, *), 1.5)
        let adjustedConfidence = min(baseConfidence * combinedFactor, 100)
        
        if buyScore > sellScore && Double(buyScore) >= minScore {
            // God Mode ATR-based SL/TP
            let sl = indicators.currentPrice - (indicators.atr * 2.0)
            let tp = indicators.currentPrice + (indicators.atr * 4.0)
            
            return ScalpingSignal(
                type: .buy,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence,
                score: buyScore,
                sellScore: sellScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date(),
                stopLoss: sl,
                takeProfit: tp,
                volume: 0.1, // Default elite volume, will be refined by risk manager
                orderType: .buy,
                fillingType: .ioc,
                executionMode: .market
            )
        } else if sellScore > buyScore && Double(sellScore) >= minScore {
            let sl = indicators.currentPrice + (indicators.atr * 1.5)
            let tp = indicators.currentPrice - (indicators.atr * 3.0)
            
            return ScalpingSignal(
                type: .sell,
                symbol: symbol,
                price: indicators.currentPrice,
                confidence: adjustedConfidence,
                score: sellScore,
                sellScore: buyScore,
                indicators: indicators,
                confidenceFactors: confidenceFactors,
                timestamp: Date(),
                stopLoss: sl,
                takeProfit: tp,
                volume: 0.1,
                orderType: .sell,
                fillingType: .ioc,
                executionMode: .market
            )
        }
        
        return ScalpingSignal(type: .none, symbol: symbol, price: indicators.currentPrice,
                               confidence: 0, score: buyScore, sellScore: sellScore, indicators: indicators,
                               confidenceFactors: [:], timestamp: Date())
    }
    
    private func applyQualityFilters(_ signal: ScalpingSignal, symbol: String) async -> ScalpingSignal? {
        guard signal.type != .none else { return nil }
        
        // Filter 1: Minimum confidence threshold (from Config)
        let threshold = await MainActor.run { config.confidenceThreshold }
        guard signal.confidence >= threshold else {
            print("📊 Signal rejected for \(symbol): Confidence too low (\(String(format: "%.1f", signal.confidence))% < \(Int(threshold))%)")
            return nil
        }
        
        // Filter 2: Check cooldown period (avoid overtrading)
        let cooldown = await MainActor.run { UserDefaults.standard.double(forKey: "signalCooldownSeconds") }
        let actualCooldown = cooldown > 0 ? cooldown : 120.0
        
        if let lastSignal = lastSignalTime[symbol],
           Date().timeIntervalSince(lastSignal) < actualCooldown {
            print("📊 Signal rejected: Cooldown active for \(symbol)")
            return nil
        }
        
        // Filter 3: Check for conflicting signals in last 5 minutes
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
    
    private func validateData(_ candlesByTimeframe: [String: [Kline]], symbol: String) -> Bool {
        // Reduced requirements for immediate signals
        let has1m = (candlesByTimeframe["1m"]?.count ?? 0) >= 10
        let has5m = (candlesByTimeframe["5m"]?.count ?? 0) >= 5
        let has15m = (candlesByTimeframe["15m"]?.count ?? 0) >= 2
        let has1h = (candlesByTimeframe["1h"]?.count ?? 0) >= 1
        
        if !has1m {
            print("📊 Insufficient 1m data for \(symbol): \(candlesByTimeframe["1m"]?.count ?? 0)/10")
            return false
        }
        
        // If higher timeframes are missing, we'll still try to evaluate but with a warning
        if !has5m || !has15m || !has1h {
            print("📊 Warning: Some higher timeframe data missing for \(symbol). Evaluating anyway.")
        }

        return true
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
    
    // God Mode Fields
    var stopLoss: Double?
    var takeProfit: Double?
    var volume: Double?
    var orderType: MT5OrderType?
    var fillingType: MT5FillingType?
    var executionMode: MT5ExecutionMode?
    
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
            timestamp: timestamp,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            volume: volume,
            orderType: orderType,
            fillingType: fillingType,
            executionMode: executionMode
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
