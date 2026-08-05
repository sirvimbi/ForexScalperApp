// DashboardViewModel.swift - UPDATED FOR ELITE SETTINGS
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties (Syncs with Settings UI)
    @Published var accountBalance: Double = 10000
    @Published var accountCurrency: String = "KES"
    @Published var riskPerTrade: Double = 0.008 { didSet { syncRiskParameters() } }
    @Published var maxDailyRisk: Double = 0.02 { didSet { syncRiskParameters() } }
    @Published var maxConcurrentTrades: Int = 2 { didSet { syncRiskParameters() } }
    
    // MARK: - Scalping Config (Syncs with Settings UI)
    @Published var scalpingConfig = ScalpingConfig.shared
    @Published var mandatoryConfluenceLevel: Double = 2.0
    @Published var maxHourlyTrades: Double = 3.0
    @Published var enableHourlyLimit: Bool = true
    @Published var activeSymbols: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(activeSymbols), forKey: "activeSymbols")
        }
    }
    
    // MARK: - MT5 Settings
    @Published var mt5Connected: Bool = false
    @Published var mt5BridgeURL: String = "http://127.0.0.1:8891"
    @Published var mt5AuthToken: String = "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
    @Published var mt5MagicNumber: Int = 888888
    @Published var mt5Login: String = "134522550"
    @Published var mt5Password: String = "Kenya@254"
    @Published var mt5Server: String = "ExnessKE-MT5Trial9"
    @Published var isConnecting: Bool = false
    
    // MARK: - IG Settings
    @Published var igAPIKey: String = ""
    @Published var igAccountID: String = ""
    @Published var igEnvironment: String = "demo"
    @Published var igAutoReconnect: Bool = true
    @Published var igConnected: Bool = false
    
    // MARK: - Notification Settings
    @Published var notifyOnSignal: Bool = true
    @Published var notifyOnTrade: Bool = true
    @Published var notifyOnClose: Bool = true
    @Published var notifyOnExpiry: Bool = true
    
    // MARK: - Auto-Trade Settings
    @Published var isAutoTradeEnabled: Bool = false
    @Published var minAutoTradeConfidence: Double = 78.0 // ELITE: 78% min
    
    // MARK: - Performance
    @Published var signals: [Signal] = []
    @Published var tradeHistory: [TradeRecord] = []
    @Published var activeTrades: [TradeRecord] = []
    @Published var allInsights: [GodModeInsight] = []
    @Published var isRefreshing: Bool = false
    @Published var selectedTimeFilter: DashboardTimeFilter = .allTime
    
    // Computed UI Strings
    @Published var todayPnLString: String = "KES 0.00"
    @Published var todayPnLColor: Color = .white
    @Published var totalPnLString: String = "KES 0.00"
    @Published var totalPnLColor: Color = .white
    
    // Performance Metrics
    @Published var maxDrawdown: Double = 0
    @Published var bestTrade: Double = 0
    @Published var worstTrade: Double = 0
    @Published var avgTradeDuration: String = "0:00"
    @Published var availableSymbols: [String] = []

    @Published var exportURL: URL?
    @Published var isShowingShareSheet: Bool = false
    @Published var isNotificationBannerDismissed: Bool = false
    
    private var coordinator: RefactoredAppCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    
    // MARK: - Init & Settings Loading
    
    init(coordinator: RefactoredAppCoordinator?) {
        self.coordinator = coordinator
        self.availableSymbols = TradingPair.allCases.map { $0.rawValue }
        loadSettings()
        setupNotificationObservers()
        
        // IG Settings Defaults
        self.igAPIKey = UserDefaults.standard.string(forKey: "igAPIKey") ?? ""
        self.igAccountID = UserDefaults.standard.string(forKey: "igAccountID") ?? ""
        self.igEnvironment = UserDefaults.standard.string(forKey: "igEnvironment") ?? "demo"
        self.igAutoReconnect = UserDefaults.standard.bool(forKey: "igAutoReconnect")
        
        // Load from ScalpingConfig
        self.mandatoryConfluenceLevel = Double(scalpingConfig.mandatoryConfluenceLevel)
        self.maxHourlyTrades = Double(scalpingConfig.maxHourlyTrades)
        self.enableHourlyLimit = scalpingConfig.enableHourlyLimit
    }
    
    func updateCoordinator(_ coordinator: RefactoredAppCoordinator) {
        self.coordinator = coordinator
        refreshData()
    }
    
    func loadSettings() {
        // Risk Settings
        accountBalance = UserDefaults.standard.double(forKey: "accountBalance") != 0 ?
            UserDefaults.standard.double(forKey: "accountBalance") : 10000
        riskPerTrade = UserDefaults.standard.double(forKey: "riskPerTrade") != 0 ?
            UserDefaults.standard.double(forKey: "riskPerTrade") : 0.008
        maxDailyRisk = UserDefaults.standard.double(forKey: "maxDailyRisk") != 0 ?
            UserDefaults.standard.double(forKey: "maxDailyRisk") : 0.02
        maxConcurrentTrades = UserDefaults.standard.integer(forKey: "maxConcurrentTrades") != 0 ?
            UserDefaults.standard.integer(forKey: "maxConcurrentTrades") : 2
        
        // Scalping Config (ELITE DEFAULTS)
        scalpingConfig.confidenceThreshold = UserDefaults.standard.double(forKey: "eliteConfidenceThreshold") != 0 ?
            UserDefaults.standard.double(forKey: "eliteConfidenceThreshold") : 78.0
        scalpingConfig.spreadTolerance = UserDefaults.standard.double(forKey: "eliteSpreadTolerance") != 0 ?
            UserDefaults.standard.double(forKey: "eliteSpreadTolerance") : 1.5
        scalpingConfig.minScore = UserDefaults.standard.double(forKey: "eliteMinScore") != 0 ?
            UserDefaults.standard.double(forKey: "eliteMinScore") : 70.0
        scalpingConfig.cooldownSeconds = UserDefaults.standard.double(forKey: "eliteCooldownSeconds") != 0 ?
            UserDefaults.standard.double(forKey: "eliteCooldownSeconds") : 60.0
        scalpingConfig.minVolatilityATR = UserDefaults.standard.double(forKey: "eliteMinVolatilityATR") != 0 ?
            UserDefaults.standard.double(forKey: "eliteMinVolatilityATR") : 0.006
        scalpingConfig.minVolumeRatio = UserDefaults.standard.double(forKey: "eliteMinVolumeRatio") != 0 ?
            UserDefaults.standard.double(forKey: "eliteMinVolumeRatio") : 1.5
        scalpingConfig.minConfluencePillars = UserDefaults.standard.double(forKey: "eliteMinConfluencePillars") != 0 ?
            UserDefaults.standard.double(forKey: "eliteMinConfluencePillars") : 3.0
        
        // MT5 Settings
        mt5BridgeURL = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8891"
        mt5AuthToken = UserDefaults.standard.string(forKey: "mt5AuthToken") ?? "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
        mt5MagicNumber = UserDefaults.standard.integer(forKey: "mt5MagicNumber") != 0 ?
            UserDefaults.standard.integer(forKey: "mt5MagicNumber") : 888888
        mt5Login = UserDefaults.standard.string(forKey: "mt5Login") ?? "134522550"
        mt5Password = UserDefaults.standard.string(forKey: "mt5Password") ?? "Kenya@254"
        mt5Server = UserDefaults.standard.string(forKey: "mt5Server") ?? "ExnessKE-MT5Trial9"
        
        // Notifications
        notifyOnSignal = UserDefaults.standard.object(forKey: "notifyOnSignal") != nil ? UserDefaults.standard.bool(forKey: "notifyOnSignal") : true
        notifyOnTrade = UserDefaults.standard.object(forKey: "notifyOnTrade") != nil ? UserDefaults.standard.bool(forKey: "notifyOnTrade") : true
        notifyOnClose = UserDefaults.standard.object(forKey: "notifyOnClose") != nil ? UserDefaults.standard.bool(forKey: "notifyOnClose") : true
        notifyOnExpiry = UserDefaults.standard.object(forKey: "notifyOnExpiry") != nil ? UserDefaults.standard.bool(forKey: "notifyOnExpiry") : true

        // Active Symbols
        if let savedSymbols = UserDefaults.standard.array(forKey: "activeSymbols") as? [String] {
            activeSymbols = Set(savedSymbols)
        } else {
            activeSymbols = Set(["EURUSD", "GBPUSD", "USDJPY"])
        }
        
        // Auto-Trade
        isAutoTradeEnabled = UserDefaults.standard.bool(forKey: "isAutoTradeEnabled")
        minAutoTradeConfidence = UserDefaults.standard.double(forKey: "minAutoTradeConfidence") != 0 ?
            UserDefaults.standard.double(forKey: "minAutoTradeConfidence") : 78.0
        
        // Sync to Risk Managers
        syncRiskParameters()
        
        print("✅ Elite Settings loaded")
    }
    
    func saveSettings() {
        UserDefaults.standard.set(riskPerTrade, forKey: "riskPerTrade")
        UserDefaults.standard.set(maxDailyRisk, forKey: "maxDailyRisk")
        UserDefaults.standard.set(maxConcurrentTrades, forKey: "maxConcurrentTrades")
        UserDefaults.standard.set(accountBalance, forKey: "accountBalance")
        
        UserDefaults.standard.set(scalpingConfig.confidenceThreshold, forKey: "eliteConfidenceThreshold")
        UserDefaults.standard.set(scalpingConfig.spreadTolerance, forKey: "eliteSpreadTolerance")
        UserDefaults.standard.set(scalpingConfig.minScore, forKey: "eliteMinScore")
        UserDefaults.standard.set(scalpingConfig.cooldownSeconds, forKey: "eliteCooldownSeconds")
        UserDefaults.standard.set(scalpingConfig.minVolatilityATR, forKey: "eliteMinVolatilityATR")
        UserDefaults.standard.set(scalpingConfig.minVolumeRatio, forKey: "eliteMinVolumeRatio")
        UserDefaults.standard.set(scalpingConfig.minConfluencePillars, forKey: "eliteMinConfluencePillars")
        
        UserDefaults.standard.set(enableHourlyLimit, forKey: "enableHourlyLimit")
        UserDefaults.standard.set(Int(maxHourlyTrades), forKey: "maxHourlyTrades")
        
        UserDefaults.standard.set(notifyOnSignal, forKey: "notifyOnSignal")
        UserDefaults.standard.set(notifyOnTrade, forKey: "notifyOnTrade")
        UserDefaults.standard.set(notifyOnClose, forKey: "notifyOnClose")
        UserDefaults.standard.set(notifyOnExpiry, forKey: "notifyOnExpiry")

        scalpingConfig.saveConfig()
        
        UserDefaults.standard.set(mt5BridgeURL, forKey: "mt5BridgeURL")
        UserDefaults.standard.set(mt5AuthToken, forKey: "mt5AuthToken")
        UserDefaults.standard.set(mt5MagicNumber, forKey: "mt5MagicNumber")
        UserDefaults.standard.set(mt5Login, forKey: "mt5Login")
        UserDefaults.standard.set(mt5Password, forKey: "mt5Password")
        UserDefaults.standard.set(mt5Server, forKey: "mt5Server")
        
        UserDefaults.standard.set(Array(activeSymbols), forKey: "activeSymbols")
        UserDefaults.standard.set(isAutoTradeEnabled, forKey: "isAutoTradeEnabled")
        UserDefaults.standard.set(minAutoTradeConfidence, forKey: "minAutoTradeConfidence")
        
        syncRiskParameters()
        
        Task {
            await MT5Service.shared.setBaseURL(mt5BridgeURL)
            await MT5Service.shared.setAuthToken(mt5AuthToken)
        }
        
        showNotification(title: "Settings Saved", message: "Elite Mode parameters updated")
    }
    
    private func syncRiskParameters() {
        let params = RiskParameters(
            accountBalance: accountBalance,
            riskPerTrade: riskPerTrade,
            maxDailyRisk: maxDailyRisk,
            maxConcurrentTrades: maxConcurrentTrades
        )
        Task {
            await RefactoredRiskManager.shared.updateParameters(params)
            await ScalpingRiskManager.shared.updateParameters(params)
        }
    }
    
    func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func acceptSignal(_ signal: Signal) {
        coordinator?.acceptSignal(signal)
    }
    
    func denySignal(_ signal: Signal) {
        coordinator?.denySignal(signal)
    }
    
    func updateTimeFilter(_ filter: DashboardTimeFilter) {
        self.selectedTimeFilter = filter
        refreshData()
    }
    
    func refreshData() {
        guard let coordinator = coordinator else { return }
        self.signals = coordinator.signals
        
        Task {
            let active = await coordinator.scalpingTradeMonitor.getActiveTrades()
            let history = await RefactoredTradeHistoryManager.shared.getCompletedTrades(filter: selectedTimeFilter)
            
            await MainActor.run {
                self.activeTrades = active
                self.tradeHistory = history
                
                let today = history.filter { Calendar.current.isDateInToday($0.exitTime ?? Date()) }
                    .compactMap { $0.pnl }.reduce(0, +)
                self.todayPnLString = "KES \(String(format: "%.2f", today))"
                self.todayPnLColor = today >= 0 ? .accentGreen : .accentRed
                
                let total = history.compactMap { $0.pnl }.reduce(0, +)
                self.totalPnLString = "KES \(String(format: "%.2f", total))"
                self.totalPnLColor = total >= 0 ? .accentGreen : .accentRed
            }
        }
    }
    
    func loadTradeHistory() {
        refreshData()
    }
    
    func clearHistory() {
        Task {
            await RefactoredTradeHistoryManager.shared.clearHistory(keepActive: true)
            refreshData()
        }
    }
    
    func clearAllHistory() {
        Task {
            await RefactoredTradeHistoryManager.shared.clearAllHistory()
            refreshData()
        }
    }
    
    func prepareCSVExport() async {
        let csvString = await RefactoredTradeHistoryManager.shared.generateCSV()
        let fileName = "GodMode_History_\(Int(Date().timeIntervalSince1970)).csv"
        
        #if os(macOS)
        await MainActor.run {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.commaSeparatedText]
            savePanel.nameFieldStringValue = fileName
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try? csvString.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }
    
    func refreshAccountInfo() async {
        if let account = try? await MT5Service.shared.getAccountInfo() {
            self.accountBalance = account.equity
            self.accountCurrency = account.currency
        }
    }
    
    func connectToMT5() async {
        isConnecting = true
        godLog("🔄 MT5: Manual connection sequence started...", level: .info)
        
        // Ensure latest values are used
        godLog("🌐 MT5: Setting Bridge URL to \(mt5BridgeURL)", level: .diagnostic)
        await MT5Service.shared.setBaseURL(mt5BridgeURL)
        await MT5Service.shared.setAuthToken(mt5AuthToken)
        
        do {
            godLog("🔍 MT5: Pinging bridge...", level: .diagnostic)
            let success = try await MT5Service.shared.checkConnection()
            
            self.mt5Connected = success
            if success {
                godLog("✅ MT5: CONNECTED SUCCESSFULLY", level: .success)
                await refreshAccountInfo()
            } else {
                godLog("❌ MT5: BRIDGE OFFLINE (Check Bridge App & Port)", level: .error)
            }
        } catch {
            godLog("❌ MT5: CONNECTION FAILED - \(error.localizedDescription)", level: .error)
            self.mt5Connected = false
        }

        isConnecting = false
    }

    func connectToIG() {
        // Implementation for IG connection
        igConnected = true // Mock for now
        showNotification(title: "IG Connection", message: "Connecting to IG \(igEnvironment) environment...")
    }

    func startAutoRefresh(interval: TimeInterval) {
        refreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshData()
            }
    }

    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Computed Properties
    var totalTrades: Int { tradeHistory.count }
    var wins: Int { tradeHistory.filter { ($0.pnl ?? 0) > 0 }.count }
    var losses: Int { tradeHistory.filter { ($0.pnl ?? 0) < 0 }.count }
    var winRate: Double { totalTrades > 0 ? Double(wins) / Double(totalTrades) * 100 : 0 }
    var profitFactor: Double {
        let totalWin = tradeHistory.filter { ($0.pnl ?? 0) > 0 }.compactMap { $0.pnl }.reduce(0, +)
        let totalLoss = abs(tradeHistory.filter { ($0.pnl ?? 0) < 0 }.compactMap { $0.pnl }.reduce(0, +))
        return totalLoss > 0 ? totalWin / totalLoss : totalWin
    }
    var avgWin: Double { wins > 0 ? tradeHistory.filter { ($0.pnl ?? 0) > 0 }.compactMap { $0.pnl }.reduce(0, +) / Double(wins) : 0 }
    var avgLoss: Double { losses > 0 ? tradeHistory.filter { ($0.pnl ?? 0) < 0 }.compactMap { $0.pnl }.reduce(0, +) / Double(losses) : 0 }
    var totalPnL: Double { tradeHistory.compactMap { $0.pnl }.reduce(0, +) }
    var currencySymbol: String { "KES " }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .newGodModeInsight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let insight = note.object as? GodModeInsight {
                    self?.allInsights.insert(insight, at: 0)
                    if (self?.allInsights.count ?? 0) > 100 { self?.allInsights.removeLast() }
                    
                    self?.showNotification(title: "🧠 \(insight.type.rawValue)", message: "\(insight.title): \(insight.message)")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showLearningInsight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let signal = note.object as? Signal {
                    let insight = GodModeInsight(
                        id: UUID(),
                        type: .performance,
                        symbol: signal.symbol,
                        title: "Performance Warning",
                        message: signal.selfLearningInsight ?? "Low win rate pattern detected",
                        sentiment: .none,
                        affectedPairs: [signal.symbol],
                        timestamp: Date()
                    )
                    self?.allInsights.insert(insight, at: 0)
                    if (self?.allInsights.count ?? 0) > 100 { self?.allInsights.removeLast() }
                    
                    self?.showNotification(title: "🧠 God Mode Insight", message: "\(signal.symbol): \(insight.message)")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .newSignalGenerated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .tradeHistoryUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .mt5AccountUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let account = notification.object as? MT5AccountInfo {
                    self?.accountBalance = account.equity
                    self?.accountCurrency = account.currency
                }
            }
            .store(in: &cancellables)
    }
}
