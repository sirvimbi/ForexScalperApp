// MARK: - Updated AppCoordinator with Scalping Engine Integration
import Foundation
import Combine
import UserNotifications

@MainActor
class RefactoredAppCoordinator: ObservableObject {
    private let marketData: MarketDataProvider
    private let tradeMonitor: TradeMonitor
    let scalpingTradeMonitor: ScalpingTradeMonitor
    private let signalEngine: RefactoredSignalEngine
    private let scalpingEngine: ScalpingSignalEngine
    private let riskManager = RefactoredRiskManager.shared
    private let scalpingRiskManager = ScalpingRiskManager.shared
    private let tradeHistory = RefactoredTradeHistoryManager.shared
    private let binanceService: BinanceService
    private var lastScalpingSignalTime: [String: Date] = [:]

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

    private var signalGenerationTask: Task<Void, Never>?
    private var metricsUpdateTask: Task<Void, Never>?
    private var isRunning = false

    private let symbols: [String]
    private let batchSize = 5
    private var pendingReconciliation: [String: TradeRecord] = [:]
    private var isEvaluating: Set<String> = []
    private var mt5PollingTask: Task<Void, Never>?
    private var mt5TradeSyncTask: Task<Void, Never>?
    private var htfRefreshTask: Task<Void, Never>?
    private var mt5ReconnectTask: Task<Void, Never>?

    private var activeSymbols: Set<String> {
        let saved = UserDefaults.standard.stringArray(forKey: "activeSymbols") ?? []
        let validSymbols = Set(TradingPair.allCases.map { $0.rawValue })
        let filtered = saved.filter { validSymbols.contains($0) }
        if filtered.isEmpty {
            return Set(["EURUSD", "GBPUSD", "USDJPY"])
        }
        return Set(filtered)
    }

    private let allowedScalpingSymbols = Set([
                                                 "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD",
                                                 "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "EURGBP", "EURCHF",
                                                 "GBPCHF", "CADJPY", "CHFJPY", "AUDCHF", "NZDCAD", "AUDNZD"
                                             ])

    enum TradingMode {
        case standard
        case scalping
    }

    init(symbols: [String] = TradingPair.allCases.map { $0.rawValue }) {
        self.symbols = symbols

        let marketDataActor = RefactoredMarketDataActor()
        self.marketData = marketDataActor

        self.binanceService = BinanceService()

        let regimeDetector = HeuristicRegimeDetector(marketData: marketData)
        let mlModel = MLModelHandler()

        self.tradeMonitor = TradeMonitor(marketData: marketData, tradeHistory: tradeHistory)

        self.scalpingEngine = ScalpingSignalEngine(
            marketData: marketData,
            tradeHistory: tradeHistory,
            riskManager: scalpingRiskManager,
            mlModel: mlModel,
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

        setupMonitorCallbacks()

        Task {
            await tradeMonitor.setOnTradeClosedCallback { [weak self] trade in
                await self?.handleTradeClosed(trade)
            }

            await scalpingTradeMonitor.setOnTradeClosedCallback { [weak self] trade in
                await self?.handleTradeClosed(trade)
            }
        }

        Task {
            await connectToDataSources()
            await start()
            await startMetricsUpdates()
        }
    }

    private func normalizeSymbol(_ symbol: String) -> String {
        var normalized = symbol.replacingOccurrences(of: "m", with: "")
        if let dotIndex = normalized.firstIndex(of: ".") {
            normalized = String(normalized[..<dotIndex])
        }
        if normalized == "USTEC" || normalized == "US100" {
            return "US100"
        }
        return normalized
    }

    private func connectToDataSources() async {
        await MainActor.run {
            status = "Connecting to Data Sources..."
            connectionStatus = "Connecting..."
        }

        // 1. Connect to Binance WebSocket
        await binanceService.connect(
            symbols: symbols,
            timeframes: tradingMode == .scalping ?
                ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"] :
                ["1m", "5m", "1h", "4h", "D1"],
            onKline: { [weak self] symbol, timeframe, kline, isLive in
                Task { [weak self] in
                    await self?.handleKlineUpdate(symbol: symbol, timeframe: timeframe, kline: kline, isLive: isLive)
                }
            }
        )

        // 2. Connect to MT5 with proper initialization
        await connectMT5()

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await MainActor.run {
            connectionStatus = "Multi-Source Connected"
            status = "Running in \(tradingMode == .scalping ? "SCALPING" : "STANDARD") mode..."
        }
    }

    private func connectMT5() async {
        let mt5Login = UserDefaults.standard.string(forKey: "mt5Login") ?? "436886946"
        let mt5Password = UserDefaults.standard.string(forKey: "mt5Password") ?? "Kenya@254"
        let mt5Server = UserDefaults.standard.string(forKey: "mt5Server") ?? "ExnessKE-MT5Trial9"

        let loginInt = Int(mt5Login) ?? 0

        do {
            godLog("🔄 MT5: Initializing connection to \(mt5Server)...", level: .info)

            // Try to initialize the EA with login credentials
            try await MT5Service.shared.initialize(
                login: loginInt,
                password: mt5Password,
                server: mt5Server
            )

            // Check connection status
            let mt5Connected = try await MT5Service.shared.checkConnection()

            if mt5Connected {
                godLog("✅ MT5: Connected successfully", level: .success)
                await MainActor.run { self.connectionStatus = "Connected" }

                // Get account info to verify
                if let account = try? await MT5Service.shared.getAccountInfo() {
                    godLog("💰 MT5: Balance: \(account.balance) \(account.currency), Equity: \(account.equity)", level: .info)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .mt5AccountUpdated, object: account)
                    }
                }

                // Sync MT5 data
                await syncMT5Data()

                // Connect to WebSocket for real-time updates
                await MT5WebSocketService.shared.connect(symbols: symbols)

                // Start MT5 reconnection monitor
                startMT5ReconnectionMonitor()
            } else {
                await MainActor.run { self.connectionStatus = "Connecting..." }
                godLog("⚠️ MT5: Bridge online but EA not connected. Retrying...", level: .warning)

                // Retry connection with a delay
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // Try one more time with explicit initialization
                let retryConnected = try await MT5Service.shared.checkConnection()
                if retryConnected {
                    godLog("✅ MT5: Connected on retry", level: .success)
                    await MainActor.run { self.connectionStatus = "Connected" }
                    await syncMT5Data()
                } else {
                    await MainActor.run { self.connectionStatus = "Disconnected" }
                    godLog("❌ MT5: Could not establish connection. Please check:", level: .error)
                    godLog("   1. MT5 Terminal is running", level: .error)
                    godLog("   2. Algo Trading is enabled (AutoTrading button is green)", level: .error)
                    godLog("   3. The SocketBridgeEA.mq5 is attached to a chart", level: .error)
                    godLog("   4. Login credentials are correct", level: .error)
                }
            }
        } catch {
            await MainActor.run { self.connectionStatus = "Error" }
            godLog("❌ MT5: Connection error - \(error.localizedDescription)", level: .error)
        }
    }

    private func startMT5ReconnectionMonitor() {
        mt5ReconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Check every 30 seconds

                guard let self = self else { break }

                // Check if MT5 is still connected
                do {
                    let connected = try await MT5Service.shared.checkConnection()
                    if !connected {
                        godLog("⚠️ MT5: Connection lost. Attempting to reconnect...", level: .warning)
                        await self.connectMT5()
                    }
                } catch {
                    godLog("⚠️ MT5: Health check failed: \(error.localizedDescription)", level: .warning)
                    // Try to reconnect
                    await self.connectMT5()
                }
            }
        }
    }

    private func syncMT5Data() async {
        godLog("🔄 Syncing MT5 Data (Deep Context)...", level: .info)

        let symbolsArray = Array(activeSymbols)
        if !symbolsArray.isEmpty {
            do {
                _ = try await MT5Service.shared.setTrackedSymbols(symbolsArray)
                godLog("✅ MT5: Watchlist pushed to EA (\(symbolsArray.count) symbols)", level: .success)
            } catch {
                godLog("⚠️ MT5: Failed to push watchlist: \(error)", level: .warning)
            }
        }

        // Fetch history for each symbol and timeframe
        for symbol in symbolsArray.prefix(20) {
            let tfs = ["1m", "5m", "15m", "30m", "1h", "4h", "D1", "W1"]

            for tf in tfs {
                if Task.isCancelled { return }

                let maxDepth = (tf == "1m" || tf == "5m") ? 1500 : 500
                var depth = maxDepth

                if let lastTime = await CandlePersistenceManager.shared.getLatestCandleTime(for: symbol, timeframe: tf) {
                    let diffSeconds = Date().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(lastTime)))
                    let tfMinutes: Double = {
                        switch tf {
                        case "1m": return 1
                        case "5m": return 5
                        case "15m": return 15
                        case "30m": return 30
                        case "1h": return 60
                        case "4h": return 240
                        case "D1": return 1440
                        case "W1": return 10080
                        default: return 1
                        }
                    }()
                    let gapCandles = Int(ceil(diffSeconds / (tfMinutes * 60)))
                    depth = min(maxDepth, max(200, gapCandles + 20))
                }

                var success = false
                var retryCount = 0
                while !success && retryCount < 3 {
                    do {
                        let candles = try await MT5Service.shared.getCandles(symbol: symbol, timeframe: tf, count: depth)
                        if let marketDataActor = marketData as? RefactoredMarketDataActor {
                            await marketDataActor.addCandles(symbol: symbol, timeframe: tf, newCandles: candles)
                        }
                        success = true
                    } catch {
                        retryCount += 1
                        if retryCount < 3 {
                            godLog("⚠️ Retry \(retryCount): Failed to sync \(symbol) \(tf): \(error.localizedDescription)", level: .warning)
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        } else {
                            godLog("❌ Failed to sync \(symbol) \(tf) after 3 retries", level: .error)
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await syncMT5Trades()
    }

    func syncMT5Trades() async {
        // Update Account Balance/Equity
        if let account = try? await MT5Service.shared.getAccountInfo() {
            godLog("💰 Live Sync: Updating Account Equity to \(account.currency) \(String(format: "%.2f", account.equity))", level: .info)
            await MainActor.run {
                NotificationCenter.default.post(name: .mt5AccountUpdated, object: account)
            }
        }

        // Fetch closed history
        do {
            let mt5History = try await MT5Service.shared.getTradeHistory(days: 90)
            if !mt5History.isEmpty {
                godLog("📥 Deep Sync: Merging \(mt5History.count) closed deals from MT5...", level: .info)
                
                // PERFORMANCE FIX: Map existing trades by external ID for O(1) lookup
                let existingTrades = await tradeHistory.getAllTrades()
                let existingExternalIds = Set(existingTrades.compactMap { $0.externalDealId })
                
                for pos in mt5History {
                    let ticketStr = String(pos.ticket)
                    
                    // PREVENT DUPLICATES: Only add if ticket doesn't already exist
                    guard !existingExternalIds.contains(ticketStr) else {
                        continue
                    }
                    
                    let record = TradeRecord(
                        id: UUID(),
                        signalId: UUID(),
                        symbol: normalizeSymbol(pos.symbol),
                        type: pos.type.lowercased() == "buy" ? .buy : .sell,
                        entryPrice: pos.open_price,
                        entryTime: Date(timeIntervalSince1970: TimeInterval(pos.open_time)),
                        exitPrice: pos.close_price,
                        exitTime: Date(timeIntervalSince1970: TimeInterval(pos.close_time)),
                        confidence: 100.0,
                        positionSize: pos.volume,
                        pnl: pos.profit + pos.commission + pos.swap,
                        status: .completed,
                        externalDealId: ticketStr,
                        swap: pos.swap,
                        commission: pos.commission
                    )
                    await tradeHistory.addTrade(record)
                }
                godLog("✅ Deep Sync: History merged successfully", level: .success)
            }
        } catch {
            godLog("⚠️ Deep Sync Error: \(error)", level: .warning)
        }

        // Sync active positions
        do {
            let mt5Data = try await MT5Service.shared.getPositionsAndOrders()
            let internalActiveTrades = await tradeHistory.getActiveTrades()

            // Sync active symbols with correlation filter
            let activeSymbolsFromMT5 = Set(mt5Data.active.map { normalizeSymbol($0.symbol) })
            await CorrelationFilter.shared.syncActiveSymbols(activeSymbolsFromMT5)
            await scalpingRiskManager.syncActiveTrades(activeSymbolsFromMT5)
            await riskManager.syncActiveTrades(activeSymbolsFromMT5)

            // Add any new positions found in MT5
            for pos in mt5Data.active {
                let dealId = String(pos.ticket)
                if await tradeHistory.getTradeByExternalId(dealId) == nil {
                    godLog("📋 Found MT5 Position: \(pos.symbol) \(pos.type) @ \(pos.priceOpen)", level: .info)

                    let normalizedSymbol = normalizeSymbol(pos.symbol)
                    let trade = TradeRecord(
                        signalId: UUID(),
                        symbol: normalizedSymbol,
                        type: pos.type.lowercased().contains("buy") ? .buy : .sell,
                        entryPrice: pos.priceOpen,
                        entryTime: parseMT5Time(pos.openTime) ?? Date(),
                        confidence: 100,
                        takeProfit: pos.tp > 0 ? pos.tp : nil,
                        stopLoss: pos.sl > 0 ? pos.sl : nil,
                        positionSize: pos.volume,
                        status: .active,
                        externalDealId: dealId,
                        originalVolume: pos.volume,
                        remainingVolume: pos.volume
                    )
                    await tradeHistory.addTrade(trade)

                    if tradingMode == .scalping {
                        await scalpingTradeMonitor.addTrade(trade, indicators: nil)
                    } else {
                        await tradeMonitor.addTrade(trade)
                    }
                }
            }

            // Check for closed trades
            for internalTrade in internalActiveTrades {
                guard let dealId = internalTrade.externalDealId else { continue }
                let stillActive = mt5Data.active.contains { "\($0.ticket)" == dealId }
                let stillPending = mt5Data.pending.contains { "\($0.ticket)" == dealId }

                if !stillActive && !stillPending {
                    // Trade is no longer active in MT5 - check history for final P&L
                    let history = try? await MT5Service.shared.getTradeHistory(days: 1)
                    if let closedTrade = history?.first(where: { "\($0.ticket)" == dealId }) {
                        godLog("📊 Trade closed: \(internalTrade.symbol) P&L: \(closedTrade.profit + closedTrade.commission + closedTrade.swap)", level: .info)

                        var updatedTrade = internalTrade
                        updatedTrade.exitPrice = closedTrade.close_price
                        updatedTrade.exitTime = parseMT5Time(closedTrade.close_time)
                        updatedTrade.pnl = closedTrade.profit + closedTrade.commission + closedTrade.swap
                        updatedTrade.swap = closedTrade.swap
                        updatedTrade.commission = closedTrade.commission
                        updatedTrade.status = .completed
                        updatedTrade.remainingVolume = 0

                        await tradeHistory.updateTrade(updatedTrade)
                        await scalpingTradeMonitor.removeTrade(id: internalTrade.id)
                        await tradeMonitor.removeTrade(id: internalTrade.id)
                        await scalpingRiskManager.closeTrade(updatedTrade)
                        await riskManager.closeTrade(updatedTrade)
                        await handleTradeClosed(updatedTrade)
                    }
                }
            }
        } catch {
            godLog("⚠️ MT5 position sync failed: \(error)", level: .warning)
        }
    }

    private func parseMT5Time(_ timestamp: Int64?) -> Date? {
        guard let ts = timestamp, ts > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    private func startMetricsUpdates() async {
        metricsUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateRiskMetrics()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateRiskMetrics() async {
        let metrics = await scalpingRiskManager.getCurrentRiskMetrics()
        await MainActor.run {
            self.riskMetrics = metrics
        }
    }

    private func setupMonitorCallbacks() {
        Task {
            await self.scalpingTradeMonitor.setPendingReconciliationCallback { [weak self] trade in
                guard let self = self, let dealId = trade.externalDealId else { return }
                await MainActor.run {
                    self.pendingReconciliation[dealId] = trade
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .mt5PriceUpdated,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let userInfo = note.userInfo,
                  let symbol = userInfo["symbol"] as? String,
                  let price = userInfo["bid"] as? Double else { return }
            Task { [weak self] in
                await self?.handleRealTimePriceUpdate(symbol: symbol, price: price)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .mt5TradeClosed,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let userInfo = note.userInfo as? [String: Any] else { return }
            Task { [weak self] in
                await self?.handleRealTimeTradeClosed(userInfo: userInfo)
            }
        }
    }

    private func handleRealTimeTradeClosed(userInfo: [String: Any]) async {
        guard let ticketId = userInfo["ticket"] as? String else { return }

        if let existingTrade = await tradeHistory.getTradeByExternalId(ticketId) {
            if existingTrade.status != .completed {
                godLog("💎 Real-time closure detected for \(existingTrade.symbol) Ticket #\(ticketId)", level: .success)

                var updatedTrade = existingTrade
                updatedTrade.pnl = (userInfo["profit"] as? Double ?? 0.0) + (userInfo["swap"] as? Double ?? 0.0) + (userInfo["commission"] as? Double ?? 0.0)
                updatedTrade.status = .completed
                updatedTrade.exitTime = Date()

                await tradeHistory.updateTrade(updatedTrade)
                await scalpingTradeMonitor.removeTrade(id: existingTrade.id)
                await tradeMonitor.removeTrade(id: existingTrade.id)
                await scalpingRiskManager.closeTrade(updatedTrade)
                await riskManager.closeTrade(updatedTrade)
                await handleTradeClosed(updatedTrade)
            }
        }
    }

    private func handleRealTimePriceUpdate(symbol: String, price: Double) async {
        guard tradingMode == .scalping else { return }

        if let scalpingSignal = await scalpingEngine.evaluateFastSignal(symbol: symbol, currentPrice: price) {
            let signal = createSignal(from: scalpingSignal)
            await handleNewSignal(signal)
        }
        await scalpingTradeMonitor.updatePrice(symbol: symbol, price: price, indicators: nil)
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true

        signalGenerationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.cleanupExpiredSignals()
                await self?.updateTradingStatus()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }

        mt5PollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollMT5Data()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }

        mt5TradeSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncMT5Trades()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }

        htfRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncMT5Data()
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        }
    }

    private func pollMT5Data() async {
        guard marketData is RefactoredMarketDataActor else { return }
        let symbolsToPoll = Array(activeSymbols)
        guard !symbolsToPoll.isEmpty else { return }

        for symbol in symbolsToPoll {
            if Task.isCancelled { return }

            if selectedSignalSource == .mt5 || selectedSignalSource == .both || selectedSignalSource == .auto {
                do {
                    let candles = try await MT5Service.shared.getCandles(symbol: symbol, timeframe: "1m", count: 2)
                    if let lastCandle = candles.last {
                        await handleKlineUpdate(symbol: symbol, timeframe: "1m", kline: lastCandle, isLive: true)
                    }
                } catch {
                    // Silent fail for polling
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func cleanupExpiredSignals() async {
        let now = Date()
        let activeSignals = signals.filter { signal in
            let status = signal.status
            return status == .pending || status == .accepted
        }

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
        if metrics.hourlyTrades >= metrics.maxHourlyTrades - 1 {
            statusDetails += " - Near hourly limit"
        }

        await MainActor.run {
            self.status = statusDetails
        }
    }

    private func handleNewSignal(_ signal: Signal) async {
        let normalizedSymbol = normalizeSymbol(signal.symbol)
        var normalizedSignal = signal
        normalizedSignal.symbol = normalizedSymbol

        godLog("🛎 NEW SIGNAL: \(normalizedSymbol) \(signal.type) @ \(String(format: "%.5f", signal.price)) (Confidence: \(Int(signal.confidence))%)", level: .info)

        await MainActor.run {
            if let existingIndex = self.signals.firstIndex(where: {
                self.normalizeSymbol($0.symbol) == normalizedSymbol && $0.status == .pending
            }) {
                self.signals.remove(at: existingIndex)
            }

            self.signals.append(normalizedSignal)
            self.lastSignal = "\(normalizedSymbol) \(normalizedSignal.type.displayName) @ \(String(format: "%.5f", normalizedSignal.price))"
            self.objectWillChange.send()
        }

        // Check for auto-trade
        let isAutoTradeEnabled = UserDefaults.standard.bool(forKey: "isAutoTradeEnabled")
        let minConfidence = UserDefaults.standard.double(forKey: "minAutoTradeConfidence")

        if isAutoTradeEnabled && normalizedSignal.confidence >= minConfidence {
            godLog("⚡️ AUTO-TRADE: Executing immediately.", level: .success)
            acceptSignal(normalizedSignal)
        }

        // Send notification
        NotificationManager.shared.sendSignalNotification(normalizedSignal)
    }

    private func createSignal(from scalpingSignal: ScalpingSignal) -> Signal {
        var expiryDuration: TimeInterval = 180

        if scalpingSignal.confidenceFactors.keys.contains("HTF Power Alignment") {
            expiryDuration = 600
        } else if scalpingSignal.confidence > 90 {
            expiryDuration = 420
        }

        if tradingMode == .standard {
            expiryDuration = 900
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
            source: .mt5,
            volume: scalpingSignal.volume ?? 0.1,
            magicNumber: 888888,
            comment: "GOD_MODE_SIGNAL",
            filler: scalpingSignal.fillingType ?? .ioc,
            orderType: scalpingSignal.orderType,
            executionMode: scalpingSignal.executionMode ?? .market,
            optimalEntryPrice: scalpingSignal.optimalEntryPrice
        )
    }

    func acceptSignal(_ signal: Signal) {
        Task {
            let normalizedSymbol = normalizeSymbol(signal.symbol)
            var normalizedSignal = signal
            normalizedSignal.symbol = normalizedSymbol

            let currentRiskManager = tradingMode == .scalping ?
                scalpingRiskManager as RiskManagerProtocol :
                riskManager as RiskManagerProtocol

            guard await currentRiskManager.canOpenTrade(for: normalizedSymbol) else {
                await MainActor.run {
                    self.signals.removeAll { $0.id == normalizedSignal.id }
                }
                return
            }

            guard let positionSize = await currentRiskManager.calculatePositionSize(for: normalizedSignal) else {
                return
            }

            var externalDealId: String?

            // Execute on MT5
            let mt5Available = (try? await MT5Service.shared.checkConnection()) ?? false
            if mt5Available {
                externalDealId = await executeSmartOrder(signal: normalizedSignal, positionSize: positionSize)

                if externalDealId == nil {
                    godLog("⚠️ MT5 execution failed - aborting", level: .warning)
                    await MainActor.run {
                        self.signals.removeAll { $0.id == normalizedSignal.id }
                    }
                    return
                }
            } else {
                godLog("❌ MT5 not available - cannot execute trade", level: .error)
                await MainActor.run {
                    self.signals.removeAll { $0.id == normalizedSignal.id }
                }
                return
            }

            let finalVolume = normalizedSignal.positionSize ?? positionSize.units
            let finalSL = normalizedSignal.stopLoss ?? positionSize.stopLoss
            let finalTP = normalizedSignal.takeProfit ?? positionSize.takeProfit

            let trade = TradeRecord(
                signalId: normalizedSignal.id,
                symbol: normalizedSymbol,
                type: normalizedSignal.type,
                entryPrice: normalizedSignal.price,
                entryTime: Date(),
                confidence: normalizedSignal.confidence,
                takeProfit: finalTP,
                stopLoss: finalSL,
                positionSize: finalVolume,
                status: .active,
                externalDealId: externalDealId
            )

            await MainActor.run {
                if let index = signals.firstIndex(where: { $0.id == normalizedSignal.id }) {
                    var updatedSignal = normalizedSignal
                    updatedSignal.status = .accepted
                    updatedSignal.acceptedAt = Date()
                    updatedSignal.acceptedPrice = normalizedSignal.price
                    updatedSignal.positionSize = finalVolume
                    updatedSignal.stopLoss = finalSL
                    updatedSignal.takeProfit = finalTP
                    updatedSignal.tradeId = trade.id
                    updatedSignal.externalDealId = externalDealId
                    signals[index] = updatedSignal
                    objectWillChange.send()
                }
            }

            await currentRiskManager.registerTrade(trade)

            if tradingMode == .scalping {
                if let indicators = await calculateLatestIndicators(symbol: normalizedSymbol) {
                    await scalpingTradeMonitor.addTrade(trade, indicators: indicators)
                } else {
                    await scalpingTradeMonitor.addTrade(trade, indicators: nil)
                }
            } else {
                await tradeMonitor.addTrade(trade)
            }

            await tradeHistory.addTrade(trade)

            godLog("✅ Trade opened: \(normalizedSymbol) - Risk: KES \(String(format: "%.2f", positionSize.riskAmount))", level: .success)
        }
    }

    private func executeSmartOrder(signal: Signal, positionSize: PositionSize) async -> String? {
        let symbol = signal.symbol

        guard await CorrelationFilter.shared.canOpenTrade(symbol: symbol, confidence: signal.confidence) else {
            godLog("🔄 Correlation Filter blocked \(symbol)", level: .warning)
            return nil
        }

        // Get ATR for volatility adjustment
        let atr = try? await MT5Service.shared.getATR(symbol: symbol, period: 14)
        let atrVal = atr ?? 0.0020
        let pipSize = symbol.contains("JPY") ? 0.01 : 0.0001
        let atrPips = atrVal / pipSize

        var executionMode: MT5ExecutionMode = .market
        var deviation: Int = 10
        var filler: MT5FillingType = .ioc

        if atrPips > 50 {
            executionMode = .market
            deviation = 20
            filler = .any
            godLog("📊 High volatility: \(String(format: "%.1f", atrPips)) pips - Using market order", level: .info)
        } else if atrPips < 20 {
            executionMode = .instant
            deviation = 5
            filler = .ioc
            godLog("📊 Low volatility: \(String(format: "%.1f", atrPips)) pips - Using instant execution", level: .info)
        }

        var optimizedSignal = signal
        optimizedSignal.executionMode = executionMode
        optimizedSignal.deviation = deviation
        optimizedSignal.filler = filler
        optimizedSignal.positionSize = positionSize.units
        optimizedSignal.stopLoss = positionSize.stopLoss
        optimizedSignal.takeProfit = positionSize.takeProfit

        do {
            let result = try await MT5Service.shared.executeTrade(signal: optimizedSignal)
            let externalDealId = result.deal != nil ? String(result.deal!) : String(result.order ?? 0)
            godLog("✅ Smart order executed (#\(externalDealId))", level: .success)

            await CorrelationFilter.shared.registerTrade(symbol: symbol)

            await MainActor.run {
                NotificationCenter.default.post(name: .mt5TradeExecuted, object: result)
            }
            return externalDealId
        } catch {
            godLog("❌ Smart order failed: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    private func calculateLatestIndicators(symbol: String) async -> IndicatorSet? {
        guard let marketDataActor = marketData as? RefactoredMarketDataActor else { return nil }

        let candles1m = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
        let candles5m = await marketDataActor.getCandles(symbol: symbol, timeframe: "5m")
        let candles4h = await marketDataActor.getCandles(symbol: symbol, timeframe: "4h")
        let candlesD1 = await marketDataActor.getCandles(symbol: symbol, timeframe: "D1")
        let candlesW1 = await marketDataActor.getCandles(symbol: symbol, timeframe: "W1")

        guard candles1m.count >= 100 else { return nil }

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

        let roc1 = (currentPrice - (candles1m.dropLast().last?.close ?? currentPrice)) / (candles1m.dropLast().last?.close ?? currentPrice) * 100
        let gaps = AdvancedIndicators.detectFairValueGaps(candles1m)
        let delta = await MT5WebSocketService.shared.getDeltaVolume(for: symbol)

        let stochK = stoch.k.last ?? 50
        let stochD = stoch.d.last ?? 50
        let currentSpread = candles1m.last?.spread
        let asiaRange = (high: 0.0, low: 0.0)
        let londonRange = (high: 0.0, low: 0.0)
        let usRange = (high: 0.0, low: 0.0)
        let sessionRanges = (asiaRange: asiaRange, londonRange: londonRange, usRange: usRange)

        return IndicatorSet(
            rsi: rsi,
            stochasticK: stochK,
            stochasticD: stochD,
            cci: cci,
            sar: sar,
            atr: atr,
            spread: currentSpread,
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
            sessions: sessionRanges,
            trendStrength: 0,
            pricePattern: .none,
            regime: .ranging,
            currentPrice: currentPrice,
            h4Trend: h4TrendVal,
            d1Trend: d1TrendVal,
            w1Trend: w1TrendVal,
            momentumScore: roc1,
            isAccelerating: false,
            fvgGaps: gaps,
            deltaVolume: delta
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

    func handleKlineUpdate(symbol: String, timeframe: String, kline: Kline, isLive: Bool = true) async {
        let normalizedSymbol = normalizeSymbol(symbol)

        guard activeSymbols.contains(normalizedSymbol) else { return }

        if tradingMode == .scalping {
            guard allowedScalpingSymbols.contains(normalizedSymbol) else { return }
        }

        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            await marketDataActor.addCandle(symbol: normalizedSymbol, timeframe: timeframe, candle: kline)
        }

        if !isLive { return }

        let klineTime = Date(timeIntervalSince1970: TimeInterval(kline.closeTime))
        let age = abs(Date().timeIntervalSince(klineTime))
        let maxAge: TimeInterval = allowedScalpingSymbols.contains(normalizedSymbol) && !normalizedSymbol.contains("USDT") ? 3600 * 4 : 120

        guard age < maxAge else { return }

        switch tradingMode {
        case .scalping:
            await handleScalpingUpdate(symbol: normalizedSymbol, timeframe: timeframe, kline: kline)
        case .standard:
            await handleStandardUpdate(symbol: normalizedSymbol, timeframe: timeframe, kline: kline)
        }
    }

    private func handleScalpingUpdate(symbol: String, timeframe: String, kline: Kline) async {
        if timeframe == "1m" {
            Task { [weak self] in
                guard let self = self else { return }

                let alreadyEvaluating = await MainActor.run { self.isEvaluating.contains(symbol) }
                if alreadyEvaluating { return }

                _ = await MainActor.run { self.isEvaluating.insert(symbol) }

                defer {
                    Task { @MainActor in _ = self.isEvaluating.remove(symbol) }
                }

                if let scalpingSignal = await scalpingEngine.evaluateScalpingSignal(symbol: symbol) {
                    let signal = createSignal(from: scalpingSignal)
                    await handleNewSignal(signal)
                }
            }
        }

        if timeframe == "1m" {
            let indicators = await calculateLatestIndicators(symbol: symbol)
            await scalpingTradeMonitor.updatePrice(symbol: symbol, price: kline.close, indicators: indicators)
        }
    }

    private func handleStandardUpdate(symbol: String, timeframe: String, kline: Kline) async {
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

    private func shouldEvaluateSymbol(symbol: String, kline: Kline) async -> Bool {
        if let marketDataActor = marketData as? RefactoredMarketDataActor {
            guard await marketDataActor.isReadyForSignals(symbol: symbol) else { return false }
        }

        guard activeSymbols.contains(symbol) else { return false }

        let existingPending = signals.contains { $0.symbol == symbol && $0.status == .pending }
        if existingPending { return false }

        let activeTrades = await tradeHistory.getActiveTrades()
        if activeTrades.contains(where: { $0.symbol == symbol }) { return false }

        guard let marketDataActor = marketData as? RefactoredMarketDataActor else { return false }

        let candles = await marketDataActor.getCandles(symbol: symbol, timeframe: "1m")
        guard candles.count >= 2 else { return false }

        let previousClose = candles[candles.count - 2].close
        let priceChangePercent = abs((kline.close - previousClose) / previousClose) * 100

        return priceChangePercent > 0.1 || Int(Date().timeIntervalSince1970) % 300 < 10
    }

    private func handleTradeClosed(_ trade: TradeRecord) async {
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

        await updateRiskMetrics()

        if tradingMode == .scalping {
            let wasWin = (trade.pnl ?? 0) > 0
            await scalpingEngine.updateSignalQuality(
                symbol: trade.symbol,
                type: trade.type,
                confidence: trade.confidence,
                wasWin: wasWin
            )
            await scalpingEngine.updateSymbolPerformance(symbol: trade.symbol, pnl: trade.pnl ?? 0)
        }

        await PerformanceAnalyzer.shared.recordTrade(trade)
        await CorrelationFilter.shared.removeTrade(symbol: trade.symbol)

        godLog("📊 Trade closed: \(trade.symbol) P&L: KES \(String(format: "%.2f", trade.pnl ?? 0))", level: trade.isWin == true ? .success : .warning)
        NotificationManager.shared.sendTradeClosedNotification(trade)
    }

    func stop() async {
        isRunning = false
        signalGenerationTask?.cancel()
        signalGenerationTask = nil
        metricsUpdateTask?.cancel()
        metricsUpdateTask = nil
        mt5PollingTask?.cancel()
        mt5PollingTask = nil
        mt5TradeSyncTask?.cancel()
        mt5TradeSyncTask = nil
        mt5ReconnectTask?.cancel()
        mt5ReconnectTask = nil

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

        await binanceService.disconnect()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await connectToDataSources()
    }

    func switchSignalSource(_ source: SignalSource) {
        Task { @MainActor in
            self.selectedSignalSource = source
            self.status = "Signal source: \(source.displayName)"
            self.signals.removeAll()
            NotificationCenter.default.post(name: .signalSourceChanged, object: source)
        }
    }

    var marketDataProvider: MarketDataProvider {
        return marketData
    }

    func getScalpingMetrics() async -> String {
        let metrics = await scalpingRiskManager.getCurrentRiskMetrics()
        var report = """
                     📊 SCALPING METRICS
                     Daily P&L: KES \(String(format: "%.2f", metrics.dailyPnL))
                     Daily Limit: KES \(String(format: "%.2f", metrics.dailyLossLimit))
                     Hourly Trades: \(metrics.hourlyTrades)/\(metrics.maxHourlyTrades)
                     Active Trades: \(metrics.activeTrades)/\(metrics.maxConcurrentTrades)
                     Consecutive Losses:
                     """
        for (symbol, losses) in metrics.consecutiveLosses {
            report += "\n  \(symbol): \(losses)"
        }
        return report
    }

    func denySignal(_ signal: Signal) {
        Task { @MainActor in
            signals.removeAll { $0.id == signal.id }
            objectWillChange.send()
            godLog("❌ Signal denied: \(signal.symbol)", level: .info)
        }
    }
}