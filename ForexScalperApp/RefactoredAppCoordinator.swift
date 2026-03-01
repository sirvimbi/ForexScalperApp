// MARK: - Updated AppCoordinator with Scalping Engine Integration
import Foundation
import Combine

@MainActor
class RefactoredAppCoordinator: ObservableObject {
    private let marketData: MarketDataProvider
    private let tradeMonitor: TradeMonitor
    private let scalpingTradeMonitor: ScalpingTradeMonitor
    private let signalEngine: RefactoredSignalEngine
    private let scalpingEngine: ScalpingSignalEngine
    private let riskManager = RefactoredRiskManager.shared
    private let scalpingRiskManager = ScalpingRiskManager.shared
    private let tradeHistory = RefactoredTradeHistoryManager.shared
    private let binanceService: BinanceService
    private var lastScalpingSignalTime: [String: Date] = [:]
    
    // Published properties for SwiftUI
    @Published var signals: [Signal] = []
    @Published var scalpingSignals: [ScalpingSignalDisplay] = []
    @Published var lastSignal: String = "No signal yet"
    @Published var status: String = "Starting..."
    @Published var connectionStatus: String = "Disconnected"
    @Published var riskMetrics: RiskMetrics?
    @Published var tradingMode: TradingMode = .scalping
    
    @Published var selectedSignalSource: SignalSource = .auto
    private let signalComparator = SignalComparator()
    private var lastBinanceSignal: [String: Signal] = [:]
    private var lastIGSignal: [String: Signal] = [:]
    var sourceLatency: [SignalSource: TimeInterval] = [.binance: 0, .ig: 0]
    var sourceReliability: [SignalSource: Double] = [.binance: 1.0, .ig: 1.0]
    private var lastSourceSwitch: Date = Date()
    private let minSwitchInterval: TimeInterval = 60
    
    // Use Task for background processing
    private var signalGenerationTask: Task<Void, Never>?
    private var metricsUpdateTask: Task<Void, Never>?
    private var isRunning = false
    
    // Batch processing for better performance
    private let symbols: [String]
    private let batchSize = 5
    
    var marketDataProvider: MarketDataProvider {
        return marketData
    }
    
    enum TradingMode {
        case standard
        case scalping
    }
    
    init(symbols: [String] = [
        // Existing pairs
        "EURUSDT", "GBPUSDT", "AUDUSDT", "BTCUSDT", "ETHUSDT",
        // New Forex pairs
        "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "CADCHF", "TRYJPY", "EURCZK",
        // New Crypto pairs
        "XRPUSDT", "ADAUSDT", "DOGEUSDT", "LTCUSDT", "BCHUSDT", "EOSUSDT",
        "XLMUSDT", "NEOUSDT", "BTGUSDT"
    ], useDebugData: Bool = false) {
        // Keep all symbols - don't filter to only USDT
        self.symbols = symbols
        
        // Initialize market data actor
        let marketDataActor = RefactoredMarketDataActor()
        self.marketData = marketDataActor
        
        // Initialize Binance service
        self.binanceService = BinanceService()
        
        // Initialize other components
        let regimeDetector = HeuristicRegimeDetector(marketData: marketData)
        let mlModel = MLModelHandler()
        
        self.tradeMonitor = TradeMonitor(marketData: marketData, tradeHistory: tradeHistory)
        
        self.scalpingEngine = ScalpingSignalEngine(
            marketData: marketData,
            tradeHistory: tradeHistory,
            riskManager: scalpingRiskManager,
            config: ScalpingConfig.shared
        )
        
        self.scalpingTradeMonitor = ScalpingTradeMonitor(
            marketData: marketData,
            tradeHistory: tradeHistory,
            signalEngine: scalpingEngine,
            config: ScalpingConfig.shared
        )
        
        self.signalEngine = RefactoredSignalEngine(
            marketData: marketData,
            regimeDetector: regimeDetector,
            mlModel: mlModel,
            tradeHistory: tradeHistory,
            riskManager: riskManager
        )
        
        // Set up trade monitor callbacks
        Task {
            await tradeMonitor.setOnTradeClosedCallback { [weak self] trade in
                await self?.handleTradeClosed(trade)
            }
            
            await scalpingTradeMonitor.setOnTradeClosedCallback { [weak self] trade in
                await self?.handleTradeClosed(trade)
            }
        }
        
        // Start the coordinator
        Task {
            await connectToDataSources()
            await start()
            await startMetricsUpdates()
        }
    }
    
    private func connectToDataSources() async {
        await MainActor.run {
            status = "Connecting to Binance..."
            connectionStatus = "Connecting..."
        }
        
        // Connect to Binance WebSocket for real-time data
        await binanceService.connect(
            symbols: symbols,
            timeframes: tradingMode == .scalping ?
                ["1m", "5m", "15m", "1h"] : // More timeframes for scalping
                ["1m", "5m", "1h"],
            onKline: { [weak self] symbol, timeframe, kline in
                Task { [weak self] in
                    await self?.handleKlineUpdate(symbol: symbol, timeframe: timeframe, kline: kline)
                }
            }
        )
        
        // Wait for initial data to arrive
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        await MainActor.run {
            connectionStatus = "Connected to Binance"
            status = "Running in \(tradingMode == .scalping ? "SCALPING" : "STANDARD") mode..."
        }
        
        print("✅ Historical data fetch complete for \(symbols.count) symbols")
    }
    
    private func startMetricsUpdates() async {
        metricsUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateRiskMetrics()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
            }
        }
    }
    
    private func updateRiskMetrics() async {
        let metrics = await scalpingRiskManager.getCurrentRiskMetrics()
        await MainActor.run {
            self.riskMetrics = metrics
        }
    }
    
    private func handleScalpingUpdate(symbol: String, timeframe: String, kline: Kline) async {
        // For scalping, we evaluate on every 1m candle
        if timeframe == "1m" {
            // Check if we should evaluate
            guard await shouldEvaluateScalping(symbol: symbol, kline: kline) else { return }
            
            // Evaluate scalping signal
            if let scalpingSignal = await scalpingEngine.evaluateScalpingSignal(symbol: symbol) {
                // Set cooldown AFTER successful signal generation
                await MainActor.run {
                    self.lastScalpingSignalTime[symbol] = Date()
                    print("📊 Cooldown set for \(symbol) - next signal allowed after 120s")
                }
                
                // Create display model for UI
                let displaySignal = ScalpingSignalDisplay(
                    symbol: scalpingSignal.symbol,
                    type: mapScalpingTypeToSignalType(scalpingSignal.type),
                    price: scalpingSignal.price,
                    confidence: scalpingSignal.confidence,
                    score: scalpingSignal.score,
                    factors: scalpingSignal.confidenceFactors,
                    timestamp: scalpingSignal.timestamp
                )
                
                await MainActor.run {
                    self.scalpingSignals.append(displaySignal)
                    // Keep only last 50 signals
                    if self.scalpingSignals.count > 50 {
                        self.scalpingSignals.removeFirst()
                    }
                }
                
                // Convert to regular signal for acceptance flow
                let signal = createSignal(from: scalpingSignal)
                await handleNewSignal(signal)
            }
        }
        
        // Update scalping trade monitor with new price data
        if timeframe == "1m" {
            // Pass latest indicators to trade monitor
            let indicators = await calculateLatestIndicators(symbol: symbol)
            await scalpingTradeMonitor.updatePrice(symbol: symbol, price: kline.close, indicators: indicators)
        }
    }
    
    private func handleStandardUpdate(symbol: String, timeframe: String, kline: Kline) async {
        // Original logic for standard trading
        if timeframe == "1m" {
            let shouldEvaluate = await shouldEvaluateSymbol(symbol: symbol, kline: kline)
            if shouldEvaluate {
                Task {
                    if let signal = await signalEngine.evaluateSymbol(symbol) {
                        await handleNewSignal(signal)
                    }
                }
            }
        }
    }
    
    private func shouldEvaluateScalping(symbol: String, kline: Kline) async -> Bool {
        // Check if we already have a pending signal (this is fine - we don't want duplicate pending signals)
        let existingPending = signals.contains { $0.symbol == symbol && $0.status == .pending }
        if existingPending {
            print("📊 Skipping \(symbol): Pending signal exists")
            return false
        }
        
        // FIX: Don't skip evaluation just because there's an active trade
        // We can still generate signals while a trade is active
        let activeTrades = await tradeHistory.getActiveTrades()
        if activeTrades.contains(where: { $0.symbol == symbol }) {
            // Log that we're generating signals despite active trade
            print("📊 Note: Active trade exists for \(symbol), but still evaluating for new signals")
            // Continue evaluation - don't return false
        }
        
        // Check cooldown period from config
        if let lastSignalTime = lastScalpingSignalTime[symbol] {
            let cooldown = ScalpingConfig.shared.cooldownSeconds
            let timeSinceLastSignal = Date().timeIntervalSince(lastSignalTime)
            if timeSinceLastSignal < cooldown {
                print("📊 Skipping \(symbol): Cooldown active (\(Int(timeSinceLastSignal))s/\(Int(cooldown))s)")
                return false
            }
        }
        
        // Get risk metrics
        let metrics = await scalpingRiskManager.getCurrentRiskMetrics()
        
        // FIXED LINE HERE:
        let maxHourlyTrades = max(2, min(10, metrics.maxConcurrentTrades * 2))
        
        // Check hourly trade limit (but this counts executed trades, not signals)
        if metrics.hourlyTrades >= maxHourlyTrades {
            print("⚠️ Hourly trade limit reached (\(metrics.hourlyTrades)/\(maxHourlyTrades))")
            return false
        }
        
        // Check concurrent trades limit
        if metrics.activeTrades >= metrics.maxConcurrentTrades {
            print("⚠️ Max concurrent trades reached (\(metrics.activeTrades)/\(metrics.maxConcurrentTrades))")
            // We can still generate signals even if at max trades - they'll just wait
            print("📊 Still evaluating signals for queueing purposes")
        }
        
        // Check volatility (avoid extremely low volatility)
        guard let marketDataActor = marketData as? RefactoredMarketDataActor else { return true }
        let candles = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
        guard candles.count >= 20 else { return true }
        
        let closes = candles.suffix(20).map { $0.close }
        let mean = closes.reduce(0, +) / 20
        let variance = closes.map { pow($0 - mean, 2) }.reduce(0, +) / 20
        let volatility = sqrt(variance) / mean * 100
        
        // Skip if volatility is too low
        if volatility < 0.02 {
            print("📊 Skipping \(symbol): Volatility too low (\(String(format: "%.3f", volatility))%)")
            return false
        }
        
        return true
    }
    
    private func calculateLatestIndicators(symbol: String) async -> IndicatorSet? {
        guard let marketDataActor = marketData as? RefactoredMarketDataActor else { return nil }
        
        let candles1m = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
        let candles5m = await marketDataActor.getCandles(symbol: symbol, timeframe: "5m")
        let candles15m = await marketDataActor.getCandles(symbol: symbol, timeframe: "15m")
        let candles1h = await marketDataActor.getCandles(symbol: symbol, timeframe: "1h")
        
        guard candles1m.count >= 100 else { return nil }
        
        // Calculate indicators (simplified version for trade monitor)
        let rsi = Indicators.rsi(candles1m.map { $0.close }, period: 14).last ?? 50
        let stoch = AdvancedIndicators.stochastic(candles1m, periodK: 14, periodD: 3)
        let bb = Indicators.bollingerBands(candles1m.map { $0.close }, period: 20, stdDev: 2.0)
        let currentPrice = candles1m.last?.close ?? 0
        let bbPosition = (currentPrice - (bb.lower.last ?? 0)) /
                         max((bb.upper.last ?? 1) - (bb.lower.last ?? 0), 0.0001)
        
        return IndicatorSet(
            rsi: rsi,
            stochasticK: stoch.k.last ?? 50,
            stochasticD: stoch.d.last ?? 50,
            cci: AdvancedIndicators.cci(candles1m, period: 20).last ?? 0,
            sar: AdvancedIndicators.parabolicSAR(candles1m).last ?? currentPrice,
            atr: AdvancedIndicators.atr(candles1m, period: 14).last ?? 0,
            ema9: Indicators.ema(candles1m.map { $0.close }, period: 9).last ?? currentPrice,
            ema21: Indicators.ema(candles1m.map { $0.close }, period: 21).last ?? currentPrice,
            ema50: Indicators.ema(candles1m.map { $0.close }, period: 50).last ?? currentPrice,
            ema9_5m: Indicators.ema(candles5m.map { $0.close }, period: 9).last ?? currentPrice,
            ema21_5m: Indicators.ema(candles5m.map { $0.close }, period: 21).last ?? currentPrice,
            ema50_5m: Indicators.ema(candles5m.map { $0.close }, period: 50).last ?? currentPrice,
            bbPosition: bbPosition,
            volumeRatio: 1.0,
            volumeProfilePOC: 0,
            support: 0,
            resistance: 0,
            sessions: (asiaRange: (0,0), londonRange: (0,0), usRange: (0,0)),
            trendStrength: 0,
            pricePattern: .none,
            regime: .ranging,
            currentPrice: currentPrice
        )
    }
    
    private func shouldEvaluateSymbol(symbol: String, kline: Kline) async -> Bool {
        // Original logic for standard trading
        let existingPending = signals.contains { $0.symbol == symbol && $0.status == .pending }
        if existingPending {
            return false
        }
        
        let activeTrades = await tradeHistory.getActiveTrades()
        if activeTrades.contains(where: { $0.symbol == symbol }) {
            return false
        }
        
        guard let marketDataActor = marketData as? RefactoredMarketDataActor else { return false }
        
        let candles = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
        guard candles.count >= 2 else { return false }
        
        let previousClose = candles[candles.count - 2].close
        let priceChangePercent = abs((kline.close - previousClose) / previousClose) * 100
        
        let shouldEvaluate = priceChangePercent > 0.1 || Int(Date().timeIntervalSince1970) % 300 < 10
        
        return shouldEvaluate
    }
    
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        
        signalGenerationTask = Task { [weak self] in
            while !Task.isCancelled {
                // Periodic cleanup of expired signals
                await self?.cleanupExpiredSignals()
                
                // Update status based on trading mode
                await self?.updateTradingStatus()
                
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }
    }
    
    private func updateTradingStatus() async {
        let metrics = await scalpingRiskManager.getCurrentRiskMetrics()
        let hour = Calendar.current.component(.hour, from: Date())
        
        var statusDetails = "Running"
        if hour < 8 || hour > 21 {
            statusDetails += " (Low liquidity session)"
        }
        if metrics.consecutiveLosses.values.contains(where: { $0 >= 2 }) {
            statusDetails += " - Reducing risk due to losses"
        }
        if metrics.hourlyTrades >= 4 {
            statusDetails += " - Near hourly limit"
        }
        
        await MainActor.run {
            self.status = statusDetails
        }
    }
    
    private func cleanupExpiredSignals() async {
        let now = Date()
        let activeSignals = signals.filter { $0.status == .pending || $0.status == .accepted }
        
        for signal in activeSignals {
            if signal.expiryTime < now {
                await MainActor.run {
                    if let index = signals.firstIndex(where: { $0.id == signal.id }) {
                        var expiredSignal = signal
                        expiredSignal.status = .expired
                        signals[index] = expiredSignal
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            self.signals.removeAll { $0.id == signal.id && $0.status == .expired }
                        }
                    }
                }
            }
        }
    }
    
    private func handleNewSignal(_ signal: Signal) async {
        // Check if we already have a pending signal for this symbol
        let existingPending = signals.contains { $0.symbol == signal.symbol && $0.status == .pending }
        guard !existingPending else {
            print("⚠️ Already have pending signal for \(signal.symbol)")
            return
        }
        
        // FIX: Don't block signals based on active trades
        // Just log that there's an active trade but still add the signal
        let activeTrades = await tradeHistory.getActiveTrades()
        if activeTrades.contains(where: { $0.symbol == signal.symbol }) {
            print("📊 Note: Adding signal for \(signal.symbol) despite active trade")
        }
        
        await MainActor.run {
            self.signals.append(signal)
            self.lastSignal = "\(signal.symbol) \(signal.type.displayName) @ \(String(format: "%.5f", signal.price))"
            self.objectWillChange.send()
            print("✅ New \(tradingMode == .scalping ? "SCALPING" : "STANDARD") signal generated: \(signal.symbol) \(signal.type) @ \(signal.price) (Confidence: \(String(format: "%.1f", signal.confidence))%)")
        }
        
        NotificationManager.shared.sendSignalNotification(signal)
    }
    
    private func mapScalpingTypeToSignalType(_ type: ScalpingSignalType) -> SignalType {
        switch type {
        case .buy:
            return .buy
        case .sell:
            return .sell
        default:
            return .none
        }
    }

    private func createSignal(from scalpingSignal: ScalpingSignal) -> Signal {
        let expiryDuration: TimeInterval = tradingMode == .scalping ? 180 : 300 // 3 minutes for scalping, 5 for standard
        
        // Map scalping signal type to general SignalType to avoid type mismatch
        let mappedType: SignalType
        switch scalpingSignal.type {
        case .buy:
            mappedType = .buy
        case .sell:
            mappedType = .sell
        default:
            mappedType = .none
        }
        
        return Signal(
            id: UUID(),
            type: mappedType,
            symbol: scalpingSignal.symbol,
            price: scalpingSignal.price,
            confidence: scalpingSignal.confidence,
            timestamp: Date(),
            timeframe: "1m",
            expiryTime: Date().addingTimeInterval(expiryDuration),
            status: .pending,
            acceptedAt: nil,
            acceptedPrice: nil,
            closedAt: nil,
            closedPrice: nil,
            pnl: nil,
            pnlPercent: nil,
            positionSize: nil,
            stopLoss: nil,
            takeProfit: nil,
            source: .binance,
            volume: 0
        )
    }

    // In RefactoredAppCoordinator.swift, update the acceptSignal method:

    func acceptSignal(_ signal: Signal) {
        Task {
            // Use appropriate risk manager based on trading mode
            let currentRiskManager = tradingMode == .scalping ?
                scalpingRiskManager as RiskManagerProtocol :
                riskManager as RiskManagerProtocol
            
            guard await currentRiskManager.canOpenTrade(for: signal.symbol) else {
                print("⚠️ Risk manager prevents accepting trade for \(signal.symbol)")
                
                await MainActor.run {
                    self.signals.removeAll { $0.id == signal.id }
                }
                return
            }
            
            guard let positionSize = await currentRiskManager.calculatePositionSize(for: signal) else {
                return
            }
            
            // Execute trade on IG if source is IG or we're using IG
            var externalDealId: String?
            var tradeStatus: TradeRecord.TradeStatus = .active
            var igExecutionSuccess = false
            
            if signal.source == .ig || selectedSignalSource == .ig || selectedSignalSource == .both {
                do {
                    print("📤 Executing trade on IG for \(signal.symbol)...")
                    let tradeResult = try await IGTradingService.shared.executeTrade(signal: signal)
                    externalDealId = tradeResult.dealId
                    igExecutionSuccess = true
                    print("✅ IG trade executed successfully. Deal ID: \(tradeResult.dealId ?? "N/A")")
                    
                    // Post notification for UI
                    await MainActor.run {
                        NotificationCenter.default.post(name: .igTradeExecuted, object: tradeResult)
                    }
                } catch {
                    print("❌ Failed to execute IG trade: \(error)")
                    
                    // IMPORTANT: For IG signals, we still want to save locally if execution fails
                    // This way the trade appears in history
                    if signal.source == .ig {
                        print("⚠️ IG execution failed but will save trade locally")
                        // Continue with local trade creation
                    } else {
                        // For other sources, abort if IG execution is required
                        await MainActor.run {
                            self.signals.removeAll { $0.id == signal.id }
                        }
                        return
                    }
                }
            }
            
            // Create trade record with external deal ID if available
            let trade = TradeRecord(
                signalId: signal.id,
                symbol: signal.symbol,
                type: signal.type,
                entryPrice: signal.price,
                entryTime: Date(),
                confidence: signal.confidence,
                takeProfit: positionSize.takeProfit,
                stopLoss: positionSize.stopLoss,
                positionSize: positionSize.units,
                status: tradeStatus,
                externalDealId: externalDealId
            )
            
            // Update signal status and link to trade
            await MainActor.run {
                if let index = signals.firstIndex(where: { $0.id == signal.id }) {
                    var updatedSignal = signal
                    updatedSignal.status = .accepted
                    updatedSignal.acceptedAt = Date()
                    updatedSignal.acceptedPrice = signal.price
                    updatedSignal.positionSize = positionSize.units
                    updatedSignal.stopLoss = positionSize.stopLoss
                    updatedSignal.takeProfit = positionSize.takeProfit
                    updatedSignal.tradeId = trade.id
                    updatedSignal.externalDealId = externalDealId
                    signals[index] = updatedSignal
                    objectWillChange.send()
                }
            }
            
            // Register with risk manager
            await currentRiskManager.registerTrade(trade)
            
            // Add to appropriate trade monitor
            if tradingMode == .scalping {
                if let indicators = await calculateLatestIndicators(symbol: signal.symbol) {
                    await scalpingTradeMonitor.addTrade(trade, indicators: indicators)
                } else {
                    await scalpingTradeMonitor.addTrade(trade, indicators: nil)
                }
            } else {
                await tradeMonitor.addTrade(trade)
            }
            
            // Add to history - THIS IS CRITICAL
            await tradeHistory.addTrade(trade)
            
            let riskAmount = tradingMode == .scalping ?
                (positionSize.riskAmount) :
                (positionSize.units * signal.price * 0.01)
            
            print("✅ \(tradingMode == .scalping ? "SCALPING" : "STANDARD") trade opened: \(signal.symbol) - Risk: $\(String(format: "%.2f", riskAmount))")
            
            if let dealId = externalDealId {
                print("📋 IG Deal ID: \(dealId)")
            } else {
                print("📋 Trade saved locally (no IG execution)")
            }
        }
    }

    func denySignal(_ signal: Signal) {
        Task { @MainActor in
            signals.removeAll { $0.id == signal.id }
            objectWillChange.send()
            print("❌ Signal denied: \(signal.symbol)")
        }
    }
    
    private func handleTradeClosed(_ trade: TradeRecord) async {
        // Update the corresponding signal
        await MainActor.run {
            if let index = signals.firstIndex(where: { $0.id == trade.signalId }) {
                var updatedSignal = signals[index]
                updatedSignal.status = .completed
                updatedSignal.closedAt = trade.exitTime
                updatedSignal.closedPrice = trade.exitPrice
                updatedSignal.pnl = trade.pnl
                updatedSignal.pnlPercent = trade.pnlPercent
                signals[index] = updatedSignal
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self.signals.removeAll { $0.id == trade.signalId }
                }
            }
        }
        
        // Update risk metrics
        await updateRiskMetrics()
        
        print("📊 Trade closed: \(trade.symbol) P&L: $\(String(format: "%.2f", trade.pnl ?? 0))")
    }
    
    func stop() async {
        isRunning = false
        signalGenerationTask?.cancel()
        signalGenerationTask = nil
        metricsUpdateTask?.cancel()
        metricsUpdateTask = nil
        
        await binanceService.disconnect()
        
        await MainActor.run {
            status = "Stopped"
            connectionStatus = "Disconnected"
        }
    }
    
    func switchTradingMode(_ mode: TradingMode) async {
        guard mode != tradingMode else { return }
        
        tradingMode = mode
        await MainActor.run {
            signals.removeAll()
            scalpingSignals.removeAll()
            status = "Switching to \(mode == .scalping ? "SCALPING" : "STANDARD") mode..."
        }
        
        // Reconnect with new timeframes
        await binanceService.disconnect()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await connectToDataSources()
    }
    

    func switchSignalSource(_ source: SignalSource) {
        Task { @MainActor in
            self.selectedSignalSource = source
            self.status = "Signal source: \(source.displayName)"
            
            // Clear signals when switching source to avoid confusion
            self.signals.removeAll()
            self.scalpingSignals.removeAll()
            
            print("🔄 Switched signal source to: \(source.displayName)")
            
            // Post notification for UI update
            NotificationCenter.default.post(name: .signalSourceChanged, object: source)
        }
    }

    func recordSignalLatency(source: SignalSource, latency: TimeInterval) {
        sourceLatency[source] = latency
        
        // Update reliability based on latency (lower latency = higher reliability)
        let maxLatency: TimeInterval = 5.0 // 5 seconds max for good reliability
        let reliability = max(0.1, 1.0 - (latency / maxLatency))
        sourceReliability[source] = min(1.0, reliability)
    }

    func recordSourceDowntime(source: SignalSource) {
        // Reduce reliability when source has downtime
        sourceReliability[source] = max(0.1, (sourceReliability[source] ?? 1.0) * 0.8)
        print("⚠️ Recorded downtime for \(source.displayName), reliability now: \(String(format: "%.2f", sourceReliability[source] ?? 0))")
    }

    func getBestSignalSource() -> SignalSource {
        guard selectedSignalSource == .auto else {
            return selectedSignalSource
        }
        
        // Don't switch too frequently
        guard Date().timeIntervalSince(lastSourceSwitch) > minSwitchInterval else {
            // Return current best guess without switching
            if sourceReliability[.binance] ?? 0 > sourceReliability[.ig] ?? 0 {
                return .binance
            } else {
                return .ig
            }
        }
        
        // Compare reliability and latency
        let binanceReliability = sourceReliability[.binance] ?? 1.0
        let igReliability = sourceReliability[.ig] ?? 1.0
        let binanceLatency = sourceLatency[.binance] ?? 0
        let igLatency = sourceLatency[.ig] ?? 0
        
        // Calculate combined score
        let binanceScore = binanceReliability * (1.0 / max(binanceLatency, 0.1))
        let igScore = igReliability * (1.0 / max(igLatency, 0.1))
        
        let bestSource: SignalSource
        if binanceScore > igScore {
            bestSource = .binance
        } else {
            bestSource = .ig
        }
        
        print("📊 Auto source selection - Binance score: \(String(format: "%.2f", binanceScore)), IG score: \(String(format: "%.2f", igScore)) - Selected: \(bestSource.displayName)")
        
        lastSourceSwitch = Date()
        return bestSource
    }

    func processIncomingSignal(_ signal: Signal, from source: SignalSource) async {
        // Record latency
        let latency = Date().timeIntervalSince(signal.timestamp)
        await recordSignalLatency(source: source, latency: latency)
        
        // Store last signal from each source
        switch source {
        case .binance:
            lastBinanceSignal[signal.symbol] = signal
        case .ig:
            lastIGSignal[signal.symbol] = signal
        default:
            break
        }
        
        // Determine which signal to use based on selected mode
        let sourceToUse = getBestSignalSource()
        
        // If source doesn't match selected/auto mode, ignore
        if selectedSignalSource == .auto {
            // In auto mode, only process signals from the best source
            if source == sourceToUse {
                await handleNewSignal(signal)
            } else {
                print("📊 Auto mode: Ignoring \(source.displayName) signal, using \(sourceToUse.displayName)")
            }
        } else if selectedSignalSource == .both {
            // In both mode, process all signals and let comparator decide
            if let binanceSig = lastBinanceSignal[signal.symbol],
               let igSig = lastIGSignal[signal.symbol] {
                let comparison = signalComparator.compareSignals(
                    binanceSignal: binanceSig,
                    igSignal: igSig,
                    newSignal: signal
                )
                
                if comparison.shouldReplace, let bestSignal = comparison.bestSignal {
                    await handleNewSignal(bestSignal)
                }
            }
        } else if source == selectedSignalSource {
            // Manual mode - only process from selected source
            await handleNewSignal(signal)
        }
    }

    // Modify handleKlineUpdate to use the new method
    func handleKlineUpdate(symbol: String, timeframe: String, kline: Kline) async {
    
        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            await marketDataActor.addCandle(symbol: symbol, timeframe: timeframe, candle: kline)
        }
        
    
        switch tradingMode {
        case .scalping:
            await handleScalpingUpdate(symbol: symbol, timeframe: timeframe, kline: kline)
        case .standard:
            await handleStandardUpdate(symbol: symbol, timeframe: timeframe, kline: kline)
        }
    }
    
    func getScalpingMetrics() async -> String {
        let metrics = await scalpingRiskManager.getCurrentRiskMetrics()
        
        var report = """
        📊 SCALPING METRICS
        Daily P&L: $\(String(format: "%.2f", metrics.dailyPnL))
        Daily Limit: $\(String(format: "%.2f", metrics.dailyLossLimit))
        Hourly Trades: \(metrics.hourlyTrades)/5
        Active Trades: \(metrics.activeTrades)/\(metrics.maxConcurrentTrades)
        
        Consecutive Losses:
        """
        
        for (symbol, losses) in metrics.consecutiveLosses {
            report += "\n  \(symbol): \(losses)"
        }
        
        return report
    }
    
    // MARK: - Debug/Testing Helper Methods
    
    func resetAllCooldownsForTesting() async {
        await MainActor.run {
            self.lastScalpingSignalTime.removeAll()
            print("✅ All signal cooldowns reset")
        }
    }
    
    func forceResetAllLimitsForTesting() async {
        // Reset risk manager limits
        await scalpingRiskManager.resetAllLimitsForTesting()
        
        // Reset cooldowns
        await MainActor.run {
            self.lastScalpingSignalTime.removeAll()
            print("✅ All trading limits and cooldowns reset for testing")
        }
    }
    
    // Add this method to force signal evaluation (keeping for diagnostic purposes but marking as test-only)
    func forceGenerateSignal(symbol: String) async {
        print("🔧 TEST MODE: Force generating signal for \(symbol)")
        
        // Force reset limits
        await scalpingRiskManager.forceAllowTrading()
        
        // Manually trigger signal evaluation
        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            let candles = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
            if let lastCandle = candles.last {
                await handleScalpingUpdate(symbol: symbol, timeframe: "1m", kline: lastCandle)
            }
        }
    }
    
    // MARK: - Test Signal Injection
    func injectTestSignal(_ signal: Signal) async {
        // Route test signals through the normal handling path
        await handleNewSignal(signal)
    }
}

// MARK: - Supporting Types
struct ScalpingSignalDisplay: Identifiable {
    let id = UUID()
    let symbol: String
    let type: SignalType
    let price: Double
    let confidence: Double
    let score: Int
    let factors: [String: Double]
    let timestamp: Date
    
    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 {
            return "\(seconds)s ago"
        } else {
            return "\(seconds/60)m ago"
        }
    }
}

