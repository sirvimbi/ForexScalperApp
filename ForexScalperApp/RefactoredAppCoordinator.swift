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
    @Published var lastSignal: String = "No signal yet"
    @Published var status: String = "Starting..."
    @Published var connectionStatus: String = "Disconnected"
    @Published var riskMetrics: RiskMetrics?
    @Published var tradingMode: TradingMode = .scalping
    
    @Published var selectedSignalSource: SignalSource = .auto
    private let signalComparator = SignalComparator()
    private var lastBinanceSignal: [String: Signal] = [:]
    private var lastIGSignal: [String: Signal] = [:]
    private var lastMT5Signal: [String: Signal] = [:]
    var sourceLatency: [SignalSource: TimeInterval] = [.binance: 0, .ig: 0, .mt5: 0]
    var sourceReliability: [SignalSource: Double] = [.binance: 1.0, .ig: 1.0, .mt5: 1.0]
    private var lastSourceSwitch: Date = Date()
    private let minSwitchInterval: TimeInterval = 60
    
    // Use Task for background processing
    private var signalGenerationTask: Task<Void, Never>?
    private var metricsUpdateTask: Task<Void, Never>?
    private var isRunning = false
    
    // Batch processing for better performance
    private let symbols: [String]
    private let batchSize = 5
    
    private var activeSymbols: Set<String> {
        // PRODUCTION SANITIZATION: Strictly only allow symbols from the TradingPair enum
        let saved = UserDefaults.standard.stringArray(forKey: "activeSymbols") ?? []
        let validSymbols = Set(TradingPair.allCases.map { $0.rawValue })
        let filtered = saved.filter { validSymbols.contains($0) }
        
        // If everything was filtered out but we need something to monitor
        if filtered.isEmpty {
            return Set(["EURUSD", "GBPUSD", "USDJPY"])
        }
        return Set(filtered)
    }
    
    var marketDataProvider: MarketDataProvider {
        return marketData
    }

    // MARK: - Symbol Whitelist for Scalping
    private let allowedScalpingSymbols = Set([
        "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD",  // Majors
        "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "EURGBP", "EURCHF",  // Minors with tight spreads
        "GBPCHF", "CADJPY", "CHFJPY", "AUDCHF", "NZDCAD", "AUDNZD"   // Additional tight spreads
    ])
    
    enum TradingMode {
        case standard
        case scalping
    }
    
    init(symbols: [String] = TradingPair.allCases.map { $0.rawValue }) {
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
            status = "Connecting to Data Sources..."
            connectionStatus = "Connecting..."
        }
        
        // 1. Connect to Binance WebSocket for real-time data
        await binanceService.connect(
            symbols: symbols,
            timeframes: tradingMode == .scalping ?
                ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"] : 
                ["1m", "5m", "1h", "4h", "D1"],
            onKline: { [weak self] symbol, timeframe, kline in
                Task { [weak self] in
                    await self?.handleKlineUpdate(symbol: symbol, timeframe: timeframe, kline: kline)
                }
            }
        )
        
        // 2. Connect/Check MT5 (God Mode)
        do {
            let mt5Login = UserDefaults.standard.string(forKey: "mt5Login") ?? "436886946"
            let mt5Password = UserDefaults.standard.string(forKey: "mt5Password") ?? "Kenya@254"
            let mt5Server = UserDefaults.standard.string(forKey: "mt5Server") ?? "ExnessKE-MT5Trial9"
            
            try await MT5Service.shared.initialize(
                login: Int(mt5Login) ?? 0,
                password: mt5Password,
                server: mt5Server
            )

            let mt5Connected = try await MT5Service.shared.checkConnection()
            if mt5Connected {
                print("✅ MT5 Connected")
                await syncMT5Data() // Fetch history and charts
            }
        } catch {
            print("⚠️ MT5 connection failed: \(error.localizedDescription)")
        }
        
        // Wait for initial data to arrive
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        await MainActor.run {
            connectionStatus = "Multi-Source Connected"
            status = "Running in \(tradingMode == .scalping ? "SCALPING" : "STANDARD") mode..."
        }
    }
    
    private func syncMT5Data() async {
        print("🔄 Syncing MT5 Data (Deep Context)...")
        
        // 1. PUSH WATCHLIST: Ensure EA knows which symbols we care about
        let symbolsArray = Array(activeSymbols)
        if !symbolsArray.isEmpty {
            do {
                _ = try await MT5Service.shared.setTrackedSymbols(symbolsArray)
                print("✅ MT5: Watchlist pushed to EA (\(symbolsArray.count) symbols)")
            } catch {
                print("⚠️ MT5: Failed to push watchlist: \(error)")
            }
        }

        // 2. FETCH HISTORY: Serial sync to prevent socket saturation
        for symbol in symbolsArray.prefix(15) { // Limit initial deep sync to top 15 pairs
            let tfs = ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"]
            
            for tf in tfs {
                // Check if already cancelled
                if Task.isCancelled { return }
                
                let depth = (tf == "1m" || tf == "5m") ? 1000 : 300 // Slightly reduced depth for minor TFs
                
                do {
                    let candles = try await MT5Service.shared.getCandles(symbol: symbol, timeframe: tf, count: depth)
                    if let marketDataActor = marketData as? RefactoredMarketDataActor {
                        for candle in candles {
                            await marketDataActor.addCandle(symbol: symbol, timeframe: tf, candle: candle)
                        }
                        print("📊 \(symbol) [\(tf)]: Loaded \(candles.count) bars")
                    }
                    // CRITICAL: Small sleep to let MT5 socket breathe
                    try? await Task.sleep(nanoseconds: 100_000_000) 
                } catch {
                    print("⚠️ Failed to sync \(symbol) \(tf): \(error.localizedDescription)")
                }
            }
        }
        
        await syncMT5Trades()
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
            // ELITE EXECUTION FLOW: No extra guard here, let the Engine handle internal risk logic
            // Evaluate scalping signal
            if let scalpingSignal = await scalpingEngine.evaluateScalpingSignal(symbol: symbol) {
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
        // 0. Check if market data is ready (has sufficient history for all timeframes)
        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            guard await marketDataActor.isReadyForSignals(symbol: symbol) else {
                return false
            }
        }
        
        // 1. Check if symbol is strictly in our active list
        guard activeSymbols.contains(symbol) else {
            return false
        }
        
        // 2. Check for pending signal
        let existingPending = signals.contains { $0.symbol == symbol && $0.status == .pending }
        if existingPending {
            return false
        }
        
        // 3. Check cooldown
        if let lastSignalTime = lastScalpingSignalTime[symbol] {
            let cooldown = ScalpingConfig.shared.cooldownSeconds
            if Date().timeIntervalSince(lastSignalTime) < cooldown {
                return false
            }
        }
        
        return true
    }
    
    private func calculateLatestIndicators(symbol: String) async -> IndicatorSet? {
        guard let marketDataActor = marketData as? RefactoredMarketDataActor else { return nil }
        
        let candles1m = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
        let candles5m = await marketDataActor.getCandles(symbol: symbol, timeframe: "5m")
        let _ = await marketDataActor.getCandles(symbol: symbol, timeframe: "15m")
        let _ = await marketDataActor.getCandles(symbol: symbol, timeframe: "30m")
        let _ = await marketDataActor.getCandles(symbol: symbol, timeframe: "1h")
        let candles4h = await marketDataActor.getCandles(symbol: symbol, timeframe: "4h")
        let candlesD1 = await marketDataActor.getCandles(symbol: symbol, timeframe: "D1")
        let candlesW1 = await marketDataActor.getCandles(symbol: symbol, timeframe: "W1")
        
        guard candles1m.count >= 100 else { return nil }
        
        // Calculate indicators (simplified version for trade monitor)
        let rsi = Indicators.rsi(candles1m.map { $0.close }, period: 14).last ?? 50
        let stoch = AdvancedIndicators.stochastic(candles1m, periodK: 14, periodD: 3)
        let bb = Indicators.bollingerBands(candles1m.map { $0.close }, period: 20, stdDev: 2.0)
        let currentPrice = candles1m.last?.close ?? 0
        let bbPosition = (currentPrice - (bb.lower.last ?? 0)) /
                         max((bb.upper.last ?? 1) - (bb.lower.last ?? 0), 0.0001)
        
        let ema9 = Indicators.ema(candles1m.map { $0.close }, period: 9).last ?? currentPrice
        let ema21 = Indicators.ema(candles1m.map { $0.close }, period: 21).last ?? currentPrice
        let ema50 = Indicators.ema(candles1m.map { $0.close }, period: 50).last ?? currentPrice
        let ema9_5m = Indicators.ema(candles5m.map { $0.close }, period: 9).last ?? currentPrice
        let ema21_5m = Indicators.ema(candles5m.map { $0.close }, period: 21).last ?? currentPrice
        let ema50_5m = Indicators.ema(candles5m.map { $0.close }, period: 50).last ?? currentPrice
        
        let cci = AdvancedIndicators.cci(candles1m, period: 20).last ?? 0
        let sar = AdvancedIndicators.parabolicSAR(candles1m).last ?? currentPrice
        let atr = AdvancedIndicators.atr(candles1m, period: 14).last ?? 0
        
        let h4TrendVal = calculateTrend(candles: Array(candles4h.suffix(20)))
        let d1TrendVal = calculateTrend(candles: Array(candlesD1.suffix(10)))
        let w1TrendVal = calculateTrend(candles: Array(candlesW1.suffix(5)))

        return IndicatorSet(
            rsi: rsi,
            stochasticK: stoch.k.last ?? 50,
            stochasticD: stoch.d.last ?? 50,
            cci: cci,
            sar: sar,
            atr: atr,
            ema9: ema9,
            ema21: ema21,
            ema50: ema50,
            ema9_5m: ema9_5m,
            ema21_5m: ema21_5m,
            ema50_5m: ema50_5m,
            bbPosition: bbPosition,
            volumeRatio: 1.0,
            volumeProfilePOC: 0,
            support: 0,
            resistance: 0,
            sessions: (asiaRange: (0,0), londonRange: (0,0), usRange: (0,0)),
            trendStrength: 0,
            pricePattern: .none,
            regime: .ranging,
            currentPrice: currentPrice,
            h4Trend: h4TrendVal,
            d1Trend: d1TrendVal,
            w1Trend: w1TrendVal
        )
    }

    private func calculateTrend(candles: [Kline]) -> SignalType {
        guard candles.count >= 2 else { return .none }
        let closes = candles.map { $0.close }
        let sma10 = closes.suffix(10).reduce(0, +) / Double(min(10, closes.count))
        let sma20 = closes.suffix(20).reduce(0, +) / Double(min(20, closes.count))
        
        if sma10 > sma20 * 1.001 { return .buy }
        if sma10 < sma20 * 0.999 { return .sell }
        return .none
    }
    
    private func shouldEvaluateSymbol(symbol: String, kline: Kline) async -> Bool {
        // 0. Check if market data is ready
        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            guard await marketDataActor.isReadyForSignals(symbol: symbol) else {
                return false
            }
        }
        
        // 1. Check if strictly in active symbols
        guard activeSymbols.contains(symbol) else {
            return false
        }
        
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
    
    private var mt5PollingTask: Task<Void, Never>?
    private var mt5TradeSyncTask: Task<Void, Never>?
    private var htfRefreshTask: Task<Void, Never>?

    func start() async {
        guard !isRunning else { 
            await syncMT5Data()
            return 
        }
        isRunning = true
        
        signalGenerationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.cleanupExpiredSignals()
                await self?.updateTradingStatus()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }

        // Start MT5 polling task
        mt5PollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollMT5Data()
                try? await Task.sleep(nanoseconds: 15_000_000_000) 
            }
        }
        
        // Start MT5 trade sync task
        mt5TradeSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncMT5Trades()
                try? await Task.sleep(nanoseconds: 30_000_000_000) 
            }
        }

        // ELITE ANCHOR REFRESHER: Keep H4/D1/W1 current every hour
        htfRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                print("⚓️ Anchor Refresher: Updating HTF trends...")
                await self?.syncMT5Data() // Full deep sync
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour
            }
        }
    }
    
    private func pollMT5Data() async {
        guard marketData is RefactoredMarketDataActor else { return }
        
        // Only poll symbols that are strictly active
        let symbolsToPoll = Array(activeSymbols)
        guard !symbolsToPoll.isEmpty else { return }
        
        for symbol in symbolsToPoll {
            // Check for cancellation between requests
            if Task.isCancelled { return }
            
            // Only poll for symbols that aren't updating frequently from Binance, or all if MT5 is selected
            if selectedSignalSource == .mt5 || selectedSignalSource == .both || selectedSignalSource == .auto {
                do {
                    let candles = try await MT5Service.shared.getCandles(symbol: symbol, timeframe: "1m", count: 2)
                    if let lastCandle = candles.last {
                        await handleKlineUpdate(symbol: symbol, timeframe: "1m", kline: lastCandle)
                    }
                } catch {
                    // Silent fail for polling
                }
            }
            
            // THROTTLE: Wait 500ms between requests to prevent network overload (nw_path errors)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func syncMT5Trades() async {
        // Update Account Balance/Equity during sync
        if let account = try? await MT5Service.shared.getAccountInfo() {
            print("💰 Live Sync: Updating Account Equity to KES \(account.equity)")
            await MainActor.run {
                NotificationCenter.default.post(name: .mt5AccountUpdated, object: account)
            }
        }

        // PRODUCTION SYNC LOGIC
        print("🔄 Force-Syncing MT5 trades and positions...")
        
        let allInternalTrades = await tradeHistory.getAllTrades()
        
        // 1. Sync Active Positions & Pending Orders
        do {
            let mt5Data = try await MT5Service.shared.getPositionsAndOrders()
            let internalActiveTrades = allInternalTrades.filter { $0.status == .active }
            
            // ELITE RECONCILIATION: Close internal trades that are no longer in MT5 (Active OR Pending)
            for internalTrade in internalActiveTrades {
                guard let dealId = internalTrade.externalDealId else { continue }
                
                let stillActive = mt5Data.active.contains { String($0.ticket) == dealId }
                let stillPending = mt5Data.pending.contains { String($0.ticket) == dealId }
                
                if !stillActive && !stillPending {
                    print("🧹 Reconciliation: Internal trade \(internalTrade.symbol) #\(dealId) no longer in MT5. Marking as completed.")
                    
                    var closedTrade = internalTrade
                    closedTrade.status = .completed
                    await tradeHistory.updateTrade(closedTrade)
                    
                    await scalpingTradeMonitor.removeTrade(id: internalTrade.id)
                    await tradeMonitor.removeTrade(id: internalTrade.id)
                    
                    await scalpingRiskManager.closeTrade(closedTrade)
                    await riskManager.closeTrade(closedTrade)
                }
            }

            // Add any new positions found in MT5 that we don't have internally
            for pos in mt5Data.active {
                let dealId = String(pos.ticket)
                if await tradeHistory.getTradeByExternalId(dealId) == nil {
                    print("📋 Found MT5 Position: \(pos.symbol) \(pos.type) @ \(pos.priceOpen)")
                    
                    let trade = TradeRecord(
                        signalId: UUID(),
                        symbol: pos.symbol,
                        type: pos.type.lowercased().contains("buy") ? .buy : .sell,
                        entryPrice: pos.priceOpen,
                        entryTime: parseMT5Time(pos.openTime) ?? Date(),
                        confidence: 100,
                        takeProfit: pos.tp > 0 ? pos.tp : nil,
                        stopLoss: pos.sl > 0 ? pos.sl : nil,
                        positionSize: pos.volume,
                        status: .active,
                        externalDealId: dealId
                    )
                    await tradeHistory.addTrade(trade)
                    
                    if tradingMode == .scalping {
                        await scalpingTradeMonitor.addTrade(trade, indicators: nil)
                    } else {
                        await tradeMonitor.addTrade(trade)
                    }
                }
            }
            
            // Add any new pending orders found in MT5
            for pos in mt5Data.pending {
                let dealId = String(pos.ticket)
                if await tradeHistory.getTradeByExternalId(dealId) == nil {
                    print("🕒 Found MT5 Pending Order: \(pos.symbol) \(pos.type) @ \(pos.priceOpen)")
                    
                    let trade = TradeRecord(
                        signalId: UUID(),
                        symbol: pos.symbol,
                        type: pos.type.lowercased().contains("buy") ? .buy : .sell,
                        entryPrice: pos.priceOpen,
                        entryTime: parseMT5Time(pos.openTime) ?? Date(),
                        confidence: 100,
                        takeProfit: pos.tp > 0 ? pos.tp : nil,
                        stopLoss: pos.sl > 0 ? pos.sl : nil,
                        positionSize: pos.volume,
                        status: .pending,
                        externalDealId: dealId
                    )
                    await tradeHistory.addTrade(trade)
                }
            }
        } catch {
            print("⚠️ MT5 sync failed: \(error)")
        }
        
        // 2. Sync Closed History
        do {
            let history = try await MT5Service.shared.getTradeHistory(days: 3)
            
            for pos in history {
                let dealId = String(pos.ticket)
                
                // Find if we already have this trade
                if let existingTrade = await tradeHistory.getTradeByExternalId(dealId) {
                    // If it was previously active, update it with final P&L
                    if existingTrade.status == .active || existingTrade.status == .pending || (existingTrade.pnl == nil) {
                        print("📊 Updating closed MT5 trade: \(pos.symbol) P&L: \(pos.profit)")
                        var updatedTrade = existingTrade
                        updatedTrade.exitPrice = pos.close_price
                        updatedTrade.exitTime = parseMT5Time(pos.close_time) ?? Date()
                        updatedTrade.pnl = pos.profit + pos.commission + pos.swap
                        updatedTrade.swap = pos.swap
                        updatedTrade.commission = pos.commission
                        updatedTrade.status = .completed
                        await tradeHistory.updateTrade(updatedTrade)
                    }
                } else {
                    // It's a completely new historical trade we don't have
                    print("📊 Syncing new historical MT5 trade: \(pos.symbol) P&L: \(pos.profit)")
                    
                    let trade = TradeRecord(
                        signalId: UUID(),
                        symbol: pos.symbol,
                        type: pos.type.lowercased().contains("buy") ? .buy : .sell,
                        entryPrice: pos.open_price,
                        entryTime: parseMT5Time(pos.open_time) ?? Date(),
                        exitPrice: pos.close_price,
                        exitTime: parseMT5Time(pos.close_time) ?? Date(),
                        confidence: 100,
                        pnl: pos.profit + pos.commission + pos.swap,
                        status: .completed,
                        externalDealId: dealId,
                        swap: pos.swap,
                        commission: pos.commission
                    )
                    await tradeHistory.addTrade(trade)
                }
            }
        } catch {
            print("⚠️ MT5 History sync failed: \(error)")
        }
    }
    
    private func parseMT5Time(_ timestamp: Int64?) -> Date? {
        guard let ts = timestamp, ts > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    private func parseMT5Time(_ timeStr: String?) -> Date? {
        guard let timeStr = timeStr else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Format 1: YYYY.MM.DD HH:MM:SS
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        if let date = formatter.date(from: timeStr) { return date }
        
        // Format 2: YYYY-MM-DD'T'HH:MM:SS
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: timeStr) { return date }
        
        // Format 3: YYYY.MM.DD
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.date(from: timeStr)
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
        // ELITE SIGNAL REFRESH: Replace any existing pending signal for this symbol with the fresh one
        await MainActor.run {
            if let existingIndex = self.signals.firstIndex(where: { $0.symbol == signal.symbol && $0.status == .pending }) {
                print("🔄 Updating pending signal for \(signal.symbol) with fresh data")
                self.signals.remove(at: existingIndex)
            }

            self.signals.append(signal)
            self.lastSignal = "\(signal.symbol) \(signal.type.displayName) @ \(String(format: "%.5f", signal.price))"
            
            // ELITE UI REFRESH: Notify listeners that signals array changed
            self.objectWillChange.send()
            
            print("✅ New \(tradingMode == .scalping ? "SCALPING" : "STANDARD") signal generated: \(signal.symbol) \(signal.type) @ \(signal.price) (Confidence: \(String(format: "%.1f", signal.confidence))%)")
            
            // ELITE AUTO-TRADE EXECUTION
            let isAutoTradeEnabled = UserDefaults.standard.bool(forKey: "isAutoTradeEnabled")
            let minConfidence = UserDefaults.standard.double(forKey: "minAutoTradeConfidence")
            
            if isAutoTradeEnabled && signal.confidence >= minConfidence {
                print("⚡️ AUTO-TRADE: Signal confidence (\(Int(signal.confidence))%) >= Threshold (\(Int(minConfidence))%). Executing immediately.")
                self.acceptSignal(signal)
            }
        }
        
        // Post global notification for any non-SwiftUI listeners
        NotificationCenter.default.post(name: .newSignalGenerated, object: signal)
        
        NotificationManager.shared.sendSignalNotification(signal)
    }
    
    private func createSignal(from scalpingSignal: ScalpingSignal) -> Signal {
        // ELITE DYNAMIC EXPIRY:
        // 1. Base duration: 180s (3m) for scalping
        var expiryDuration: TimeInterval = 180 
        
        // 2. Trend Conviction Bonus: If HTF aligned, the window of opportunity is wider
        if scalpingSignal.confidenceFactors.keys.contains("HTF Power Alignment") || 
           scalpingSignal.confidenceFactors.keys.contains("Elite Dip Buy") ||
           scalpingSignal.confidenceFactors.keys.contains("Elite Rally Sell") {
            expiryDuration = 420 // 7 minutes (Elite signals have macro backing)
        } else if scalpingSignal.confidence > 90 {
            expiryDuration = 300 // 5 minutes (High confidence)
        }
        
        if tradingMode == .standard {
            expiryDuration = 600 // 10 minutes for standard mode
        }
        
        return Signal(
            id: UUID(),
            type: scalpingSignal.type,
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
            positionSize: scalpingSignal.volume,
            stopLoss: scalpingSignal.stopLoss,
            takeProfit: scalpingSignal.takeProfit,
            source: .mt5,
            volume: scalpingSignal.volume ?? 0.1,
            tradeId: nil,
            externalDealId: nil,
            magicNumber: 888888,
            comment: "GOD_MODE_SIGNAL",
            deviation: 10,
            filler: scalpingSignal.fillingType ?? .ioc,
            orderType: scalpingSignal.orderType,
            executionMode: scalpingSignal.executionMode ?? .market
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
            
            // Execute trade on appropriate service
            var externalDealId: String?
            
            // MT5 Execution (God Mode)
            if signal.source == .mt5 || selectedSignalSource == .mt5 || selectedSignalSource == .both {
                do {
                    print("📤 Executing trade on MT5 for \(signal.symbol)...")
                    var mt5Signal = signal
                    
                    // Prioritize UI-adjusted values if they exist, otherwise use engine's
                    mt5Signal.positionSize = signal.positionSize ?? positionSize.units
                    mt5Signal.stopLoss = signal.stopLoss ?? positionSize.stopLoss
                    mt5Signal.takeProfit = signal.takeProfit ?? positionSize.takeProfit
                    
                    mt5Signal.magicNumber = Int(UserDefaults.standard.integer(forKey: "mt5MagicNumber"))
                    if mt5Signal.magicNumber == 0 { mt5Signal.magicNumber = 888888 }
                    
                    mt5Signal.comment = "GOD_MODE_SCALP"
                    mt5Signal.executionMode = signal.executionMode ?? .market
                    mt5Signal.filler = signal.filler ?? .ioc
                    mt5Signal.deviation = signal.deviation ?? 10
                    
                    let tradeResult = try await MT5Service.shared.executeTrade(signal: mt5Signal)
                    externalDealId = tradeResult.deal != nil ? String(tradeResult.deal!) : String(tradeResult.order ?? 0)
                    print("✅ MT5 trade executed successfully. Ticket/Deal: \(externalDealId ?? "N/A")")
                    
                    await MainActor.run {
                        NotificationCenter.default.post(name: .mt5TradeExecuted, object: tradeResult)
                    }
                } catch {
                    print("❌ Failed to execute MT5 trade: \(error.localizedDescription)")
                    
                    // PRODUCTION FIX: Handle "Trade Disabled" or 10044 (Real Only) by marking symbol restricted
                    if error.localizedDescription.contains("trade disabled") || 
                       error.localizedDescription.contains("10044") {
                        print("🛡 GodMode: Auto-Restricting \(signal.symbol) (Broker Restriction Detected)")
                    }

                    if signal.source == .mt5 {
                        print("⚠️ MT5 execution failed - aborting")
                        await MainActor.run {
                            self.signals.removeAll { $0.id == signal.id }
                        }
                        return
                    }
                }
            } 
            // IG Execution
            else if signal.source == .ig || selectedSignalSource == .ig {
                do {
                    print("📤 Executing trade on IG for \(signal.symbol)...")
                    let tradeResult = try await IGTradingService.shared.executeTrade(signal: signal)
                    externalDealId = tradeResult.dealId
                    print("✅ IG trade executed successfully. Deal ID: \(tradeResult.dealId ?? "N/A")")
                    
                    await MainActor.run {
                        NotificationCenter.default.post(name: .igTradeExecuted, object: tradeResult)
                    }
                } catch {
                    print("❌ Failed to execute IG trade: \(error)")
                    if signal.source == .ig {
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
                status: .active,
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
            
            print("✅ \(tradingMode == .scalping ? "SCALPING" : "STANDARD") trade opened: \(signal.symbol) - Risk: KES \(String(format: "%.2f", riskAmount))")
            
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
        
        print("📊 Trade closed: \(trade.symbol) P&L: KES \(String(format: "%.2f", trade.pnl ?? 0))")
    }
    
    func stop() async {
        isRunning = false
        signalGenerationTask?.cancel()
        signalGenerationTask = nil
        metricsUpdateTask?.cancel()
        metricsUpdateTask = nil
        mt5PollingTask?.cancel()
        mt5PollingTask = nil
        
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
            let bRel = sourceReliability[.binance] ?? 0
            let iRel = sourceReliability[.ig] ?? 0
            let mRel = sourceReliability[.mt5] ?? 0
            
            if bRel >= iRel && bRel >= mRel { return .binance }
            if iRel >= bRel && iRel >= mRel { return .ig }
            return .mt5
        }
        
        // Compare reliability and latency
        let binanceReliability = sourceReliability[.binance] ?? 1.0
        let igReliability = sourceReliability[.ig] ?? 1.0
        let mt5Reliability = sourceReliability[.mt5] ?? 1.0
        let binanceLatency = sourceLatency[.binance] ?? 0
        let igLatency = sourceLatency[.ig] ?? 0
        let mt5Latency = sourceLatency[.mt5] ?? 0
        
        // Calculate combined score
        let binanceScore = binanceReliability * (1.0 / max(binanceLatency, 0.1))
        let igScore = igReliability * (1.0 / max(igLatency, 0.1))
        let mt5Score = mt5Reliability * (1.0 / max(mt5Latency, 0.1))
        
        let bestSource: SignalSource
        if binanceScore >= igScore && binanceScore >= mt5Score {
            bestSource = .binance
        } else if igScore >= binanceScore && igScore >= mt5Score {
            bestSource = .ig
        } else {
            bestSource = .mt5
        }
        
        print("📊 Auto source selection - Binance score: \(String(format: "%.2f", binanceScore)), IG score: \(String(format: "%.2f", igScore)) - Selected: \(bestSource.displayName)")
        
        lastSourceSwitch = Date()
        return bestSource
    }

    func processIncomingSignal(_ signal: Signal, from source: SignalSource) async {
        // Record latency
        let latency = Date().timeIntervalSince(signal.timestamp)
        recordSignalLatency(source: source, latency: latency)
        
        // Store last signal from each source
        switch source {
        case .binance:
            lastBinanceSignal[signal.symbol] = signal
        case .ig:
            lastIGSignal[signal.symbol] = signal
        case .mt5:
            lastMT5Signal[signal.symbol] = signal
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
               let igSig = lastIGSignal[signal.symbol],
               let _ = lastMT5Signal[signal.symbol] {
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

    func handleKlineUpdate(symbol: String, timeframe: String, kline: Kline) async {
        // ELITE PAIR FILTER: Completely ignore pairs not selected in Settings
        guard activeSymbols.contains(symbol) else { return }
        
        // FIXED: Additional whitelist check for scalping mode
        if tradingMode == .scalping {
            guard allowedScalpingSymbols.contains(symbol) else {
                // print("📊 \(symbol) ignored: Not in scalping whitelist")
                return
            }
        }

        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            await marketDataActor.addCandle(symbol: symbol, timeframe: timeframe, candle: kline)
        }
        
        // PRODUCTION FIX: Only evaluate signals for current data (within last 2 minutes)
        // This prevents "ghost signals" from historical data loading
        let klineTime = Date(timeIntervalSince1970: TimeInterval(kline.closeTime))
        let isRecent = abs(Date().timeIntervalSince(klineTime)) < 120
        
        guard isRecent else { return }

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
        Daily P&L: KES \(String(format: "%.2f", metrics.dailyPnL))
        Daily Limit: KES \(String(format: "%.2f", metrics.dailyLossLimit))
        Hourly Trades: \(metrics.hourlyTrades)/5
        Active Trades: \(metrics.activeTrades)/\(metrics.maxConcurrentTrades)
        
        Consecutive Losses:
        """
        
        for (symbol, losses) in metrics.consecutiveLosses {
            report += "\n  \(symbol): \(losses)"
        }
        
        return report
    }

    // MARK: - Trade Analysis
    
    func analyzeTradeHistory() async {
        let trades = await tradeHistory.getAllTrades()
        let report = TradeAnalyzer.analyze(trades)
        let recommendations = TradeAnalyzer.generateRecommendations(report)
        let blacklistCode = TradeAnalyzer.generateBlacklistCode(report)
        
        // Print to console
        print(recommendations)
        print("\n\n")
        print("// ===========================================")
        print("// BLACKLIST CODE TO COPY INTO YOUR PROJECT")
        print("// ===========================================")
        print(blacklistCode)
        
        // Also save to file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reportPath = documentsPath.appendingPathComponent("trade_analysis_report.txt")
        let codePath = documentsPath.appendingPathComponent("symbol_blacklist_code.swift")
        
        do {
            try recommendations.write(to: reportPath, atomically: true, encoding: .utf8)
            try blacklistCode.write(to: codePath, atomically: true, encoding: .utf8)
            print("\n✅ Reports saved to:")
            print("   - \(reportPath.path)")
            print("   - \(codePath.path)")
        } catch {
            print("❌ Failed to save reports: \(error)")
        }
    }

    // CSV Parser for Trade History
    func parseTradeHistoryCSV(_ csvContent: String) -> [TradeRecord] {
        var trades: [TradeRecord] = []
        let rows = csvContent.components(separatedBy: "\n")
        
        guard rows.count > 1 else { return trades }
        
        // Skip header
        for row in rows.dropFirst() {
            let columns = row.components(separatedBy: ",")
            guard columns.count >= 12 else { continue }
            
            // Parse data
            let symbol = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let typeString = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let entryPrice = Double(columns[6]) ?? 0
            let exitPrice = Double(columns[7]) ?? 0
            let pnl = Double(columns[11]) ?? 0
            let result = columns[12].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Determine status
            let status: TradeRecord.TradeStatus = (result == "ACTIVE" || result == "PENDING") ? .active : .completed
            
            // Determine trade type
            let type: SignalType = typeString == "BUY" ? .buy : .sell
            
            let trade = TradeRecord(
                signalId: UUID(),
                symbol: symbol,
                type: type,
                entryPrice: entryPrice,
                entryTime: Date(),
                exitPrice: status == .completed ? exitPrice : nil,
                exitTime: status == .completed ? Date() : nil,
                confidence: 100,
                pnl: pnl,
                status: status
            )
            trades.append(trade)
        }
        
        return trades
    }
    
    // MARK: - Status Update Methods
}


