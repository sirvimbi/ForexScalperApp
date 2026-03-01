// DashboardViewModel.swift - Updated with Full Settings Functionality
import SwiftUI
import Combine
import UserNotifications

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var signals: [Signal] = []
    @Published var tradeHistory: [TradeRecord] = []
    @Published var activeTrades: [TradeRecord] = []
    @Published var accountBalance: Double = 10000
    @Published var riskPerTrade: Double = 0.01
    @Published var maxDailyRisk: Double = 0.03
    @Published var maxConcurrentTrades: Int = 3
    @Published var igAPIKey: String = ""
    @Published var igAccountID: String = ""
    @Published var igEnvironment: String = "demo"
    @Published var igAutoReconnect: Bool = true
    @Published var igConnected: Bool = false
    @Published var igConnectionError: String = ""
    @Published var isConnecting: Bool = false
    @Published var notifyOnSignal: Bool = true
    @Published var notifyOnTrade: Bool = true
    @Published var notifyOnClose: Bool = true
    @Published var notifyOnExpiry: Bool = true
    @Published var minConfidenceForNotification: Double = 70
    @Published var selectedTimeFilter: DashboardTimeFilter = .allTime
    @Published var isRefreshing: Bool = false
    @Published var backtestResult: BacktestResultData?
    @Published var isBacktesting: Bool = false
    @Published var backtestProgress: Int = 0
    @Published var backtestSymbol: String = "EURUSD"
    @Published var backtestTimeframe: String = "1m"
    @Published var backtestMinConfidence: Double = 70
    @Published var backtestRiskPercent: Double = 1.0
    @Published var backtestStartBalance: Double = 10000
    @Published var backtestPeriod: String = "30d"
    @Published var backtestStopLossPercent: Double = 1.0
    @Published var backtestRRRatio: Double = 2.0
    @Published var minScalpingScore: Double = 15
    @Published var maxSpreadBps: Double = 10
    @Published var signalCooldownSeconds: Double = 120
    @Published var defaultStopLossPercent: Double = 1.0
    @Published var defaultRRRatio: Double = 2.0
    @Published var activeSymbols: Set<String> = []
    
    // Added missing properties
    @Published var isExecutingTrade: Bool = false
    @Published var riskSettingsChanged: Bool = false
    @Published var tradingPairsChanged: Bool = false
    @Published var showSaveSuccess: Bool = false
    
    // Auto-refresh timer
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval = 0.5
    
    // Signal source metrics
    @Published var binanceLatency: TimeInterval = 0
    @Published var igLatency: TimeInterval = 0
    @Published var binanceReliability: Double = 1.0
    @Published var igReliability: Double = 1.0
    @Published var activeSource: SignalSource = .auto
    
    let availableSymbols = [
        // Existing
        "EURUSDT", "GBPUSDT", "AUDUSDT", "BTCUSDT", "ETHUSDT",
        // New Forex
        "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "CADCHF", "TRYJPY", "EURCZK",
        // New Crypto
        "XRPUSDT", "ADAUSDT", "DOGEUSDT", "LTCUSDT", "BCHUSDT", "EOSUSDT",
        "XLMUSDT", "NEOUSDT", "BTGUSDT"
    ]
    
    @Published var scalpingConfig = ScalpingConfig.shared
    private weak var coordinator: RefactoredAppCoordinator?
    private var cancellables = Set<AnyCancellable>()
    
    init(coordinator: RefactoredAppCoordinator?) {
        self.coordinator = coordinator
        setupNotificationObservers()
        loadSettings() // Load saved settings on init
        
        // Load initial source metrics if coordinator exists
        if let coordinator = coordinator {
            self.activeSource = coordinator.selectedSignalSource
            self.binanceLatency = coordinator.sourceLatency[.binance] ?? 0
            self.igLatency = coordinator.sourceLatency[.ig] ?? 0
            self.binanceReliability = coordinator.sourceReliability[.binance] ?? 1.0
            self.igReliability = coordinator.sourceReliability[.ig] ?? 1.0
        }
    }
    
    // MARK: - Settings Loading and Saving
    
    func loadSettings() {
        // Load Risk Management settings
        accountBalance = UserDefaults.standard.double(forKey: "accountBalance") != 0 ?
            UserDefaults.standard.double(forKey: "accountBalance") : 10000
        riskPerTrade = UserDefaults.standard.double(forKey: "riskPerTrade") != 0 ?
            UserDefaults.standard.double(forKey: "riskPerTrade") : 0.01
        maxDailyRisk = UserDefaults.standard.double(forKey: "maxDailyRisk") != 0 ?
            UserDefaults.standard.double(forKey: "maxDailyRisk") : 0.03
        maxConcurrentTrades = UserDefaults.standard.integer(forKey: "maxConcurrentTrades") != 0 ?
            UserDefaults.standard.integer(forKey: "maxConcurrentTrades") : 3
        defaultStopLossPercent = UserDefaults.standard.double(forKey: "defaultStopLossPercent") != 0 ?
            UserDefaults.standard.double(forKey: "defaultStopLossPercent") : 1.0
        defaultRRRatio = UserDefaults.standard.double(forKey: "defaultRRRatio") != 0 ?
            UserDefaults.standard.double(forKey: "defaultRRRatio") : 2.0
        
        // Load Notification settings
        notifyOnSignal = UserDefaults.standard.object(forKey: "notifyOnSignal") != nil ?
            UserDefaults.standard.bool(forKey: "notifyOnSignal") : true
        notifyOnTrade = UserDefaults.standard.object(forKey: "notifyOnTrade") != nil ?
            UserDefaults.standard.bool(forKey: "notifyOnTrade") : true
        notifyOnClose = UserDefaults.standard.object(forKey: "notifyOnClose") != nil ?
            UserDefaults.standard.bool(forKey: "notifyOnClose") : true
        notifyOnExpiry = UserDefaults.standard.object(forKey: "notifyOnExpiry") != nil ?
            UserDefaults.standard.bool(forKey: "notifyOnExpiry") : true
        minConfidenceForNotification = UserDefaults.standard.double(forKey: "minConfidenceForNotification") != 0 ?
            UserDefaults.standard.double(forKey: "minConfidenceForNotification") : 70
        
        // Load Scalping settings
        minScalpingScore = UserDefaults.standard.double(forKey: "minScalpingScore") != 0 ?
            UserDefaults.standard.double(forKey: "minScalpingScore") : 15
        maxSpreadBps = UserDefaults.standard.double(forKey: "maxSpreadBps") != 0 ?
            UserDefaults.standard.double(forKey: "maxSpreadBps") : 10
        signalCooldownSeconds = UserDefaults.standard.double(forKey: "signalCooldownSeconds") != 0 ?
            UserDefaults.standard.double(forKey: "signalCooldownSeconds") : 120
        
        // Load IG settings
        igAPIKey = UserDefaults.standard.string(forKey: "igAPIKey") ?? ""
        igAccountID = UserDefaults.standard.string(forKey: "igAccountID") ?? ""
        igEnvironment = UserDefaults.standard.string(forKey: "igEnvironment") ?? "demo"
        igAutoReconnect = UserDefaults.standard.object(forKey: "igAutoReconnect") != nil ?
            UserDefaults.standard.bool(forKey: "igAutoReconnect") : true
        
        // Load Active Trading Pairs
        if let savedSymbols = UserDefaults.standard.array(forKey: "activeSymbols") as? [String] {
            activeSymbols = Set(savedSymbols)
        } else {
            // Default to some active symbols
            activeSymbols = Set(["EURUSD", "GBPUSD", "BTCUSDT"])
        }
        
        print("✅ Settings loaded from UserDefaults")
    }
    
    func saveSettings() {
        // Save Risk Management settings
        UserDefaults.standard.set(accountBalance, forKey: "accountBalance")
        UserDefaults.standard.set(riskPerTrade, forKey: "riskPerTrade")
        UserDefaults.standard.set(maxDailyRisk, forKey: "maxDailyRisk")
        UserDefaults.standard.set(maxConcurrentTrades, forKey: "maxConcurrentTrades")
        UserDefaults.standard.set(defaultStopLossPercent, forKey: "defaultStopLossPercent")
        UserDefaults.standard.set(defaultRRRatio, forKey: "defaultRRRatio")
        
        // Save Notification settings
        UserDefaults.standard.set(notifyOnSignal, forKey: "notifyOnSignal")
        UserDefaults.standard.set(notifyOnTrade, forKey: "notifyOnTrade")
        UserDefaults.standard.set(notifyOnClose, forKey: "notifyOnClose")
        UserDefaults.standard.set(notifyOnExpiry, forKey: "notifyOnExpiry")
        UserDefaults.standard.set(minConfidenceForNotification, forKey: "minConfidenceForNotification")
        
        // Save Scalping settings
        UserDefaults.standard.set(minScalpingScore, forKey: "minScalpingScore")
        UserDefaults.standard.set(maxSpreadBps, forKey: "maxSpreadBps")
        UserDefaults.standard.set(signalCooldownSeconds, forKey: "signalCooldownSeconds")
        
        // Save IG settings
        UserDefaults.standard.set(igAPIKey, forKey: "igAPIKey")
        UserDefaults.standard.set(igAccountID, forKey: "igAccountID")
        UserDefaults.standard.set(igEnvironment, forKey: "igEnvironment")
        UserDefaults.standard.set(igAutoReconnect, forKey: "igAutoReconnect")
        
        // Save Active Trading Pairs
        UserDefaults.standard.set(Array(activeSymbols), forKey: "activeSymbols")
        
        // Update risk manager with new parameters
        Task {
            await RefactoredRiskManager.shared.updateParameters(
                RiskParameters(
                    accountBalance: accountBalance,
                    riskPerTrade: riskPerTrade,
                    maxDailyRisk: maxDailyRisk,
                    maxConcurrentTrades: maxConcurrentTrades
                )
            )
        }
        
        // Update scalping config
        scalpingConfig.saveConfig()
        
        // Show success message
        showSaveSuccess = true
        riskSettingsChanged = false
        tradingPairsChanged = false
        
        print("✅ Settings saved to UserDefaults")
    }
    
    func startAutoRefresh(interval: TimeInterval = 0.5) {
        refreshInterval = interval
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshData()
            }
        }
        print("🔄 Auto-refresh started at \(interval)s interval")
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("🔄 Auto-refresh stopped")
    }
    
    func updateCoordinator(_ coordinator: RefactoredAppCoordinator) {
        self.coordinator = coordinator
        refreshData()
        
        // Update source metrics
        self.activeSource = coordinator.selectedSignalSource
        self.binanceLatency = coordinator.sourceLatency[.binance] ?? 0
        self.igLatency = coordinator.sourceLatency[.ig] ?? 0
        self.binanceReliability = coordinator.sourceReliability[.binance] ?? 1.0
        self.igReliability = coordinator.sourceReliability[.ig] ?? 1.0
    }
    
    func refreshData() {
        guard let coordinator = coordinator else { return }
        
        Task {
            // Update signals from coordinator
            let currentSignals = await MainActor.run { coordinator.signals }
            let currentActiveSource = await MainActor.run { coordinator.getBestSignalSource() }
            let binanceLat = await MainActor.run { coordinator.sourceLatency[.binance] ?? 0 }
            let igLat = await MainActor.run { coordinator.sourceLatency[.ig] ?? 0 }
            let binanceRel = await MainActor.run { coordinator.sourceReliability[.binance] ?? 1.0 }
            let igRel = await MainActor.run { coordinator.sourceReliability[.ig] ?? 1.0 }
            
            await MainActor.run {
                self.signals = currentSignals
                self.activeSource = currentActiveSource
                self.binanceLatency = binanceLat
                self.igLatency = igLat
                self.binanceReliability = binanceRel
                self.igReliability = igRel
            }
        }
    }
    
    func switchSignalSource(_ source: SignalSource) {
        coordinator?.switchSignalSource(source)
        
        // Update local state
        self.activeSource = source
        
        // Log the switch
        print("🔄 ViewModel: Switched signal source to \(source.displayName)")
    }
    
    func getSourceStatusColor(for source: SignalSource) -> Color {
        switch source {
        case .binance:
            return binanceReliability > 0.7 ? .green : (binanceReliability > 0.3 ? .orange : .red)
        case .ig:
            return igReliability > 0.7 ? .green : (igReliability > 0.3 ? .orange : .red)
        case .auto:
            return .accentCyan
        case .both:
            return .purple
        }
    }
    
    // Single acceptSignal method (removed duplicate)
    func acceptSignal(_ signal: Signal) {
        // Show loading state
        isExecutingTrade = true
        
        coordinator?.acceptSignal(signal)
        
        // Reset loading state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isExecutingTrade = false
        }
    }
    
    func getSourceLatencyString(for source: SignalSource) -> String {
        let latency: TimeInterval
        switch source {
        case .binance:
            latency = binanceLatency
        case .ig:
            latency = igLatency
        default:
            return "N/A"
        }
        
        if latency <= 0 {
            return "—"
        } else if latency < 0.001 {
            return "<1ms"
        } else {
            return String(format: "%.0fms", latency * 1000)
        }
    }
    
    func denySignal(_ signal: Signal) {
        coordinator?.denySignal(signal)
    }
    
    func updateTimeFilter(_ filter: DashboardTimeFilter) {
        selectedTimeFilter = filter
        loadTradeHistory()
    }
    
    func loadTradeHistory() {
        Task {
            // Load from TradeHistoryManager
            let history = await RefactoredTradeHistoryManager.shared.getCompletedTrades(filter: selectedTimeFilter)
            let active = await RefactoredTradeHistoryManager.shared.getActiveTrades()
            
            await MainActor.run {
                self.tradeHistory = history
                self.activeTrades = active
            }
        }
    }
    
    func clearHistory() {
        Task {
            await RefactoredTradeHistoryManager.shared.clearHistory(keepActive: true)
            await loadTradeHistory()
        }
    }
    
    func clearAllHistory() {
        Task {
            await RefactoredTradeHistoryManager.shared.clearAllHistory()
            await loadTradeHistory()
        }
    }
    
    func runBacktest() {
        guard !isBacktesting else { return }
        isBacktesting = true
        backtestProgress = 0
        
        Task {
            // Simulate backtest progress
            for i in 0...100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                await MainActor.run {
                    self.backtestProgress = i
                }
            }
            
            // Create mock backtest result
            let result = BacktestResultData(
                symbol: backtestSymbol,
                totalTrades: 145,
                wins: 98,
                losses: 47,
                winRate: 67.6,
                totalPnL: 2345.67,
                maxDrawdown: 456.78,
                sharpeRatio: 1.82,
                profitFactor: 2.15
            )
            
            await MainActor.run {
                self.backtestResult = result
                self.isBacktesting = false
            }
        }
    }
    
    func connectToIG() async {
        await MainActor.run {
            igConnected = false
            igConnectionError = ""
            isConnecting = true
        }
        
        do {
            // Use credentials from secure storage
            let identifier = UserDefaults.standard.string(forKey: "igIdentifier") ?? "kiptoo.bryan@gmail.com"
            let password = UserDefaults.standard.string(forKey: "igPassword") ?? "Kenya@254"
            
            // Use the API key from UserDefaults or fallback
            let apiKey = igAPIKey.isEmpty ? "23ca12562ccdbef0e9ab24d55c4f423b604bddd9" : igAPIKey
            
            let response = try await IGTradingService.shared.authenticate(
                identifier: identifier,
                password: password,
                apiKey: apiKey
            )
            
            if response.success {
                await MainActor.run {
                    self.igConnected = true
                    self.igConnectionError = ""
                    self.isConnecting = false
                    
                    // Save credentials if auto-reconnect is enabled
                    if self.igAutoReconnect {
                        UserDefaults.standard.set(identifier, forKey: "igIdentifier")
                        UserDefaults.standard.set(password, forKey: "igPassword")
                    }
                    
                    print("✅ Successfully connected to IG")
                }
            } else {
                await MainActor.run {
                    self.igConnectionError = response.error ?? "Authentication failed"
                    self.isConnecting = false
                }
            }
        } catch let error as TradingError {
            await MainActor.run {
                self.igConnectionError = error.errorDescription ?? error.localizedDescription
                self.isConnecting = false
            }
        } catch {
            await MainActor.run {
                self.igConnectionError = error.localizedDescription
                self.isConnecting = false
            }
        }
    }
    
    func disconnectFromIG() async {
        // Implement disconnect logic
        await MainActor.run {
            igConnected = false
            isConnecting = false
            IGTradingService.shared.clearSession()
        }
    }
    
    // MARK: - Computed Properties
    
    var totalTrades: Int {
        tradeHistory.count
    }
    
    var wins: Int {
        tradeHistory.filter { ($0.pnl ?? 0) > 0 }.count
    }
    
    var losses: Int {
        tradeHistory.filter { ($0.pnl ?? 0) < 0 }.count
    }
    
    var winRate: Double {
        guard totalTrades > 0 else { return 0 }
        return Double(wins) / Double(totalTrades) * 100
    }
    
    var totalPnL: Double {
        tradeHistory.compactMap { $0.pnl }.reduce(0, +)
    }
    
    var todayPnL: Double {
        let today = Calendar.current.startOfDay(for: Date())
        return tradeHistory
            .filter { Calendar.current.isDate($0.entryTime, inSameDayAs: today) }
            .compactMap { $0.pnl }
            .reduce(0, +)
    }
    
    var avgWin: Double {
        let wins = tradeHistory.filter { ($0.pnl ?? 0) > 0 }.compactMap { $0.pnl }
        return wins.isEmpty ? 0 : wins.reduce(0, +) / Double(wins.count)
    }
    
    var avgLoss: Double {
        let losses = tradeHistory.filter { ($0.pnl ?? 0) < 0 }.compactMap { $0.pnl }
        return losses.isEmpty ? 0 : abs(losses.reduce(0, +) / Double(losses.count))
    }
    
    var profitFactor: Double {
        let grossProfit = tradeHistory.filter { ($0.pnl ?? 0) > 0 }.compactMap { $0.pnl }.reduce(0, +)
        let grossLoss = abs(tradeHistory.filter { ($0.pnl ?? 0) < 0 }.compactMap { $0.pnl }.reduce(0, +))
        return grossLoss == 0 ? (grossProfit > 0 ? .infinity : 0) : grossProfit / grossLoss
    }
    
    var maxDrawdown: Double {
        // Simplified calculation
        var peak = 0.0
        var maxDD = 0.0
        var cumulative = 0.0
        
        for trade in tradeHistory.sorted(by: { $0.entryTime < $1.entryTime }) {
            cumulative += trade.pnl ?? 0
            if cumulative > peak {
                peak = cumulative
            }
            let dd = peak - cumulative
            if dd > maxDD {
                maxDD = dd
            }
        }
        
        return maxDD
    }
    
    var bestTrade: Double {
        tradeHistory.compactMap { $0.pnl }.max() ?? 0
    }
    
    var worstTrade: Double {
        tradeHistory.compactMap { $0.pnl }.min() ?? 0
    }
    
    var avgTradeDuration: String {
        let durations = tradeHistory.compactMap { trade -> TimeInterval? in
            guard let exitTime = trade.exitTime else { return nil }
            return exitTime.timeIntervalSince(trade.entryTime)
        }
        
        guard !durations.isEmpty else { return "N/A" }
        
        let avgSeconds = durations.reduce(0, +) / Double(durations.count)
        let minutes = Int(avgSeconds) / 60
        let seconds = Int(avgSeconds) % 60
        
        return "\(minutes)m \(seconds)s"
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .tradeHistoryUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadTradeHistory()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .tradeUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let trade = notification.object as? TradeRecord {
                    self?.handleTradeUpdate(trade)
                }
            }
            .store(in: &cancellables)
        
        // Observe signal source changes
        NotificationCenter.default.publisher(for: .signalSourceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let source = notification.object as? SignalSource {
                    self?.activeSource = source
                    self?.refreshData()
                    print("📢 ViewModel: Signal source changed to \(source.displayName)")
                }
            }
            .store(in: &cancellables)
        
        // Observe source metrics updates
        NotificationCenter.default.publisher(for: .sourceMetricsUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSourceMetrics()
            }
            .store(in: &cancellables)
    }
    
    private func refreshSourceMetrics() {
        guard let coordinator = coordinator else { return }
        
        self.binanceLatency = coordinator.sourceLatency[.binance] ?? 0
        self.igLatency = coordinator.sourceLatency[.ig] ?? 0
        self.binanceReliability = coordinator.sourceReliability[.binance] ?? 1.0
        self.igReliability = coordinator.sourceReliability[.ig] ?? 1.0
        self.activeSource = coordinator.getBestSignalSource()
    }
    
    private func handleTradeUpdate(_ trade: TradeRecord) {
        // Update the trade in history if needed
        loadTradeHistory()
    }
    
    deinit {
        Task { @MainActor in
            self.stopAutoRefresh()
        }
    }
}

// MARK: - Extension for DashboardTimeFilter
enum DashboardTimeFilter: String, CaseIterable {
    case allTime = "ALL"
    case today = "TODAY"
    case week = "WEEK"
    case month = "MONTH"
}
