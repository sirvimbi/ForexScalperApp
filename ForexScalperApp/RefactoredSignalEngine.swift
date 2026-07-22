// MARK: - Enhanced Signal Engine with Diversity
import Foundation

actor RefactoredSignalEngine {
    private let marketData: MarketDataProvider
    private let regimeDetector: Core.RegimeDetector
    private let mlModel: MLModelHandler
    private let tradeHistory: RefactoredTradeHistoryManager
    private let riskManager: RiskManagerProtocol
    
    // Improved cooldown with adaptive timing
    private var lastSignalTime: [String: Date] = [:]
    private var signalQuality: [String: [Double]] = [:] // Track signal quality per symbol
    
    // Signal diversity tracking
    private var lastSignalTypes: [String: [SignalType]] = [:]
    private let maxSignalHistory = 5
    
    init(marketData: MarketDataProvider, regimeDetector: Core.RegimeDetector,
         mlModel: MLModelHandler, tradeHistory: RefactoredTradeHistoryManager,
         riskManager: RiskManagerProtocol) {
        self.marketData = marketData
        self.regimeDetector = regimeDetector
        self.mlModel = mlModel
        self.tradeHistory = tradeHistory
        self.riskManager = riskManager
    }
    
    func evaluateSymbol(_ symbol: String) async -> Signal? {
        // 1. Check if we can trade based on risk
        guard await riskManager.canOpenTrade(for: symbol) else {
            print("⚠️ Risk manager prevents new trades for \(symbol)")
            return nil
        }
        
        // 2. Adaptive cooldown based on market volatility
        let regime = await regimeDetector.currentRegime(symbol: symbol)
        let cooldownPeriod = getAdaptiveCooldown(for: regime)
        
        if let lastSignal = lastSignalTime[symbol],
           Date().timeIntervalSince(lastSignal) < cooldownPeriod {
            return nil
        }
        
        // 3. Get market data
        let candles1m = await marketData.getCandles(symbol: symbol, timeframe: "1m")
        let candles5m = await marketData.getCandles(symbol: symbol, timeframe: "5m")
        let candles1h = await marketData.getCandles(symbol: symbol, timeframe: "1h")
        
        guard validateData(candles1m: candles1m, candles5m: candles5m, candles1h: candles1h) else {
            return nil
        }
        
        // 4. Extract features and get prediction
        let features = await mlModel.extractFeatures(
            symbol: symbol,
            candles1m: candles1m,
            candles5m: candles5m,
            candles1h: candles1h
        )
        
        guard let (mlSignal, rawConfidence) = await mlModel.predictSignal(features: features),
              rawConfidence >= getMinimumConfidence(for: regime) else {
            return nil
        }
        
        // Convert TradeSignal to SignalType
        let signalType: SignalType
        switch mlSignal {
        case .buy:
            signalType = .buy
        case .sell:
            signalType = .sell
        case .neutral:
            return nil
        }
        
        // 5. Apply signal diversity check
        guard isSignalDiverse(symbol: symbol, newType: signalType) else {
            print("📊 Skipping repetitive signal for \(symbol)")
            return nil
        }
        
        // 6. Calculate adaptive confidence based on multiple factors
        let adjustedConfidence = await calculateAdaptiveConfidence(
            symbol: symbol,
            baseConfidence: rawConfidence,
            regime: regime,
            features: features,
            candles1m: candles1m
        )
        
        // 7. Create signal with proper expiry based on timeframe
        let signal = createSignal(
            symbol: symbol,
            type: signalType,
            price: candles1m.last?.close ?? 0,
            confidence: adjustedConfidence,
            timeframe: getOptimalTimeframe(for: regime),
            source: symbol.hasSuffix("USDT") ? .binance : .ig,
            volume: candles1m.last?.volume ?? 0
        )
        
        // 8. Update tracking
        await updateTracking(symbol: symbol, signal: signal)
        
        return signal
    }
    
    private func getAdaptiveCooldown(for regime: Core.MarketRegime) -> TimeInterval {
        switch regime {
        case .volatile:
            return 180 // 3 minutes - wait for volatility to settle
        case .strongUptrend, .strongDowntrend:
            return 120 // 2 minutes
        case .ranging:
            return 60 // 1 minute
        case .quiet:
            return 300 // 5 minutes - less frequent in quiet markets
        }
    }
    
    private func getMinimumConfidence(for regime: Core.MarketRegime) -> Double {
        switch regime {
        case .volatile:
            return 0.75 // Higher confidence needed in volatile markets
        case .strongUptrend, .strongDowntrend:
            return 0.65
        case .ranging:
            return 0.70
        case .quiet:
            return 0.80 // Very confident needed in quiet markets
        }
    }
    
    private func getOptimalTimeframe(for regime: Core.MarketRegime) -> String {
        switch regime {
        case .volatile:
            return "1m" // Faster trading in volatile markets
        case .strongUptrend, .strongDowntrend:
            return "5m" // Medium timeframe in trends
        case .ranging, .quiet:
            return "15m" // Longer timeframe in ranging/quiet markets
        }
    }
    
    private func isSignalDiverse(symbol: String, newType: SignalType) -> Bool {
        let history = lastSignalTypes[symbol] ?? []
        
        // If we have no history, it's diverse
        guard !history.isEmpty else { return true }
        
        // Check if we've seen this signal type too frequently
        let recentTypes = history.suffix(3)
        let sameTypeCount = recentTypes.filter { $0 == newType }.count
        
        // Allow if not more than 2 of last 3 are the same type
        return sameTypeCount < 2
    }
    
    private func calculateAdaptiveConfidence(
        symbol: String,
        baseConfidence: Double,
        regime: Core.MarketRegime,
        features: [String: Double],
        candles1m: [Kline]
    ) async -> Double {
        var confidence = baseConfidence * 100 // Convert to percentage
        
        // 1. Adjust based on regime
        switch regime {
        case .volatile:
            confidence *= 0.9 // Reduce confidence in volatile markets
        case .strongUptrend, .strongDowntrend:
            confidence *= 1.1 // Increase confidence in strong trends
        case .ranging:
            confidence *= 0.95 // Slight reduction in ranging markets
        case .quiet:
            confidence *= 1.15 // Higher confidence in quiet markets
        }
        
        // 2. Volume confirmation
        if let volumeRatio = features["volume_ratio"], volumeRatio > 1.5 {
            confidence *= 1.1 // Volume confirms
        } else if let volumeRatio = features["volume_ratio"], volumeRatio < 0.8 {
            confidence *= 0.9 // Low volume reduces confidence
        }
        
        // 3. Multiple timeframe confirmation
        let hasConfirmation = await hasMultiTimeframeConfirmation(symbol: symbol)
        confidence *= hasConfirmation ? 1.2 : 0.85
        
        // 4. Historical performance of similar signals
        let performanceMultiplier = await getHistoricalPerformanceMultiplier(symbol: symbol)
        confidence *= performanceMultiplier
        
        return min(max(confidence, 0), 100) // Clamp between 0-100
    }
    
    private func hasMultiTimeframeConfirmation(symbol: String) async -> Bool {
        let candles5m = await marketData.getCandles(symbol: symbol, timeframe: "5m")
        let candles1h = await marketData.getCandles(symbol: symbol, timeframe: "1h")
        
        guard candles5m.count >= 20, candles1h.count >= 10 else { return false }
        
        // Check if trend aligns across timeframes
        let trend5m = calculateTrend(candles: candles5m.suffix(20))
        let trend1h = calculateTrend(candles: candles1h.suffix(10))
        
        return trend5m == trend1h
    }
    
    private func calculateTrend(candles: ArraySlice<Kline>) -> SignalType {
        guard candles.count >= 2 else { return .none }
        let closes = candles.map { $0.close }
        let sma10 = closes.suffix(10).reduce(0, +) / Double(min(10, closes.count))
        let sma20 = closes.suffix(20).reduce(0, +) / Double(min(20, closes.count))
        
        if sma10 > sma20 * 1.001 { return .buy }
        if sma10 < sma20 * 0.999 { return .sell }
        return .none
    }
    
    private func getHistoricalPerformanceMultiplier(symbol: String) async -> Double {
        let stats = await tradeHistory.getSymbolPerformance(symbol: symbol, days: 7)
        
        guard stats.totalTrades >= 5 else { return 1.0 } // Not enough data
        
        if stats.winRate > 0.6 {
            return 1.1 // Good history
        } else if stats.winRate < 0.4 {
            return 0.85 // Poor history
        }
        return 1.0
    }
    
    private func validateData(candles1m: [Kline], candles5m: [Kline], candles1h: [Kline]) -> Bool {
        return candles1m.count >= 100 &&
               candles5m.count >= 50 &&
               candles1h.count >= 20
    }
    
    private func createSignal(symbol: String, type: SignalType, price: Double,
                              confidence: Double, timeframe: String,
                              source: SignalSource, volume: Double) -> Signal {
        let expiryDuration = getExpiryDuration(for: timeframe)
        
        return Signal(
            type: type,
            symbol: symbol,
            price: price,
            confidence: confidence,
            timestamp: Date(),
            timeframe: timeframe,
            expiryTime: Date().addingTimeInterval(expiryDuration),
            status: .pending,
            source: source,
            volume: volume
        )
    }
    
    private func getExpiryDuration(for timeframe: String) -> TimeInterval {
        switch timeframe {
        case "1m": return 300 // 5 minutes
        case "5m": return 900 // 15 minutes
        case "15m": return 2700 // 45 minutes
        case "1h": return 7200 // 2 hours
        default: return 300
        }
    }
    
    private func updateTracking(symbol: String, signal: Signal) async {
        lastSignalTime[symbol] = Date()
        
        // Update signal type history
        var history = lastSignalTypes[symbol] ?? []
        history.append(signal.type)
        if history.count > maxSignalHistory {
            history.removeFirst()
        }
        lastSignalTypes[symbol] = history
        
        // Track signal quality for adaptive learning
        var quality = signalQuality[symbol] ?? []
        quality.append(signal.confidence / 100)
        if quality.count > 20 {
            quality.removeFirst()
        }
        signalQuality[symbol] = quality
    }
}
