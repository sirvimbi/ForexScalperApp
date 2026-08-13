// DashboardViewModel.swift - UPDATED FOR ELITE SETTINGS
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties (Syncs with Settings UI)
    @Published var accountBalance: Double = 10000 { didSet { syncRiskParameters() } }
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
    @Published var mt5BridgeURL: String = "http://127.0.0.1:8890"
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
        
        // V10.0 Precision Settings
        scalpingConfig.enableOrderFlowFilter = UserDefaults.standard.object(forKey: "enableOrderFlowFilter") != nil ? 
            UserDefaults.standard.bool(forKey: "enableOrderFlowFilter") : true
        scalpingConfig.orderFlowThreshold = UserDefaults.standard.double(forKey: "orderFlowThreshold") != 0 ?
            UserDefaults.standard.double(forKey: "orderFlowThreshold") : 50.0
        scalpingConfig.enablePullbackEntry = UserDefaults.standard.object(forKey: "enablePullbackEntry") != nil ? 
            UserDefaults.standard.bool(forKey: "enablePullbackEntry") : true
        scalpingConfig.enableMLTrendFilter = UserDefaults.standard.object(forKey: "enableMLTrendFilter") != nil ? 
            UserDefaults.standard.bool(forKey: "enableMLTrendFilter") : true
        scalpingConfig.enableSwingSL = UserDefaults.standard.object(forKey: "enableSwingSL") != nil ? 
            UserDefaults.standard.bool(forKey: "enableSwingSL") : true
        scalpingConfig.volatilityMultiplierMin = UserDefaults.standard.double(forKey: "volatilityMultiplierMin") != 0 ?
            UserDefaults.standard.double(forKey: "volatilityMultiplierMin") : 0.5
        scalpingConfig.fixedSLPips = UserDefaults.standard.double(forKey: "fixedSLPips") != 0 ?
            UserDefaults.standard.double(forKey: "fixedSLPips") : 30.0
        scalpingConfig.enableRRCheck = UserDefaults.standard.object(forKey: "enableRRCheck") != nil ?
            UserDefaults.standard.bool(forKey: "enableRRCheck") : true
        scalpingConfig.minRRRatio = UserDefaults.standard.double(forKey: "minRRRatio") != 0 ?
            UserDefaults.standard.double(forKey: "minRRRatio") : 1.5
        
        // V10.0 More Precision
        scalpingConfig.pullbackEMAPeriod = UserDefaults.standard.integer(forKey: "pullbackEMAPeriod") != 0 ?
            UserDefaults.standard.integer(forKey: "pullbackEMAPeriod") : 21
        scalpingConfig.rocPeriod = UserDefaults.standard.integer(forKey: "rocPeriod") != 0 ?
            UserDefaults.standard.integer(forKey: "rocPeriod") : 1
        scalpingConfig.mlConfidenceThreshold = UserDefaults.standard.double(forKey: "mlConfidenceThreshold") != 0 ?
            UserDefaults.standard.double(forKey: "mlConfidenceThreshold") : 0.7
        scalpingConfig.swingLookback = UserDefaults.standard.integer(forKey: "swingLookback") != 0 ?
            UserDefaults.standard.integer(forKey: "swingLookback") : 20
        
        // V10.0 Partial TP Settings
        scalpingConfig.partialTP1_Percent = UserDefaults.standard.double(forKey: "partialTP1_Percent") != 0 ?
            UserDefaults.standard.double(forKey: "partialTP1_Percent") : 0.50
        scalpingConfig.partialTP1_Pips = UserDefaults.standard.double(forKey: "partialTP1_Pips") != 0 ?
            UserDefaults.standard.double(forKey: "partialTP1_Pips") : 10.0
        scalpingConfig.partialTP2_Percent = UserDefaults.standard.double(forKey: "partialTP2_Percent") != 0 ?
            UserDefaults.standard.double(forKey: "partialTP2_Percent") : 0.30
        scalpingConfig.partialTP2_Pips = UserDefaults.standard.double(forKey: "partialTP2_Pips") != 0 ?
            UserDefaults.standard.double(forKey: "partialTP2_Pips") : 15.0
        scalpingConfig.partialTP3_Percent = UserDefaults.standard.double(forKey: "partialTP3_Percent") != 0 ?
            UserDefaults.standard.double(forKey: "partialTP3_Percent") : 0.20
        scalpingConfig.partialTP3_Pips = UserDefaults.standard.double(forKey: "partialTP3_Pips") != 0 ?
            UserDefaults.standard.double(forKey: "partialTP3_Pips") : 20.0
        
        // Strategy Weights
        scalpingConfig.weightHTFAlignment = UserDefaults.standard.double(forKey: "weightHTFAlignment") != 0 ?
            UserDefaults.standard.double(forKey: "weightHTFAlignment") : 25.0
        scalpingConfig.weightMomentumExhaustion = UserDefaults.standard.double(forKey: "weightMomentumExhaustion") != 0 ?
            UserDefaults.standard.double(forKey: "weightMomentumExhaustion") : 15.0
        scalpingConfig.weightVolumeSurge = UserDefaults.standard.double(forKey: "weightVolumeSurge") != 0 ?
            UserDefaults.standard.double(forKey: "weightVolumeSurge") : 12.0
        scalpingConfig.weightEMAStack = UserDefaults.standard.double(forKey: "weightEMAStack") != 0 ?
            UserDefaults.standard.double(forKey: "weightEMAStack") : 18.0
        scalpingConfig.weightBollingerRejection = UserDefaults.standard.double(forKey: "weightBollingerRejection") != 0 ?
            UserDefaults.standard.double(forKey: "weightBollingerRejection") : 10.0
        scalpingConfig.weightCCICycle = UserDefaults.standard.double(forKey: "weightCCICycle") != 0 ?
            UserDefaults.standard.double(forKey: "weightCCICycle") : 10.0
        scalpingConfig.weightSARTrend = UserDefaults.standard.double(forKey: "weightSARTrend") != 0 ?
            UserDefaults.standard.double(forKey: "weightSARTrend") : 10.0
        scalpingConfig.weightMomentumSurge = UserDefaults.standard.double(forKey: "weightMomentumSurge") != 0 ?
            UserDefaults.standard.double(forKey: "weightMomentumSurge") : 12.0
        scalpingConfig.weightOrderFlow = UserDefaults.standard.double(forKey: "weightOrderFlow") != 0 ?
            UserDefaults.standard.double(forKey: "weightOrderFlow") : 15.0
        scalpingConfig.weightMLConfirmed = UserDefaults.standard.double(forKey: "weightMLConfirmed") != 0 ?
            UserDefaults.standard.double(forKey: "weightMLConfirmed") : 10.0
        
        // MT5 Settings
        // V10.3 ELITE: Force reset if saved URL is using the legacy 8891 port
        let savedURL = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
        if savedURL.contains(":8891") {
            print("🛡️ MT5: Correcting legacy port 8891 to 8890 in settings...")
            let corrected = savedURL.replacingOccurrences(of: ":8891", with: ":8890")
            UserDefaults.standard.set(corrected, forKey: "mt5BridgeURL")
            mt5BridgeURL = corrected
        } else {
            mt5BridgeURL = savedURL
        }
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
        
        // V10.0 Precision Save
        UserDefaults.standard.set(scalpingConfig.enableOrderFlowFilter, forKey: "enableOrderFlowFilter")
        UserDefaults.standard.set(scalpingConfig.orderFlowThreshold, forKey: "orderFlowThreshold")
        UserDefaults.standard.set(scalpingConfig.enablePullbackEntry, forKey: "enablePullbackEntry")
        UserDefaults.standard.set(scalpingConfig.enableMLTrendFilter, forKey: "enableMLTrendFilter")
        UserDefaults.standard.set(scalpingConfig.enableSwingSL, forKey: "enableSwingSL")
        UserDefaults.standard.set(scalpingConfig.volatilityMultiplierMin, forKey: "volatilityMultiplierMin")
        UserDefaults.standard.set(scalpingConfig.fixedSLPips, forKey: "fixedSLPips")
        UserDefaults.standard.set(scalpingConfig.enableRRCheck, forKey: "enableRRCheck")
        UserDefaults.standard.set(scalpingConfig.minRRRatio, forKey: "minRRRatio")
        
        // V10.0 More Precision Save
        UserDefaults.standard.set(scalpingConfig.pullbackEMAPeriod, forKey: "pullbackEMAPeriod")
        UserDefaults.standard.set(scalpingConfig.rocPeriod, forKey: "rocPeriod")
        UserDefaults.standard.set(scalpingConfig.mlConfidenceThreshold, forKey: "mlConfidenceThreshold")
        UserDefaults.standard.set(scalpingConfig.swingLookback, forKey: "swingLookback")
        
        // V10.0 Partial TP Save
        UserDefaults.standard.set(scalpingConfig.partialTP1_Percent, forKey: "partialTP1_Percent")
        UserDefaults.standard.set(scalpingConfig.partialTP1_Pips, forKey: "partialTP1_Pips")
        UserDefaults.standard.set(scalpingConfig.partialTP2_Percent, forKey: "partialTP2_Percent")
        UserDefaults.standard.set(scalpingConfig.partialTP2_Pips, forKey: "partialTP2_Pips")
        UserDefaults.standard.set(scalpingConfig.partialTP3_Percent, forKey: "partialTP3_Percent")
        UserDefaults.standard.set(scalpingConfig.partialTP3_Pips, forKey: "partialTP3_Pips")
        
        // Strategy Weights Save
        UserDefaults.standard.set(scalpingConfig.weightHTFAlignment, forKey: "weightHTFAlignment")
        UserDefaults.standard.set(scalpingConfig.weightMomentumExhaustion, forKey: "weightMomentumExhaustion")
        UserDefaults.standard.set(scalpingConfig.weightVolumeSurge, forKey: "weightVolumeSurge")
        UserDefaults.standard.set(scalpingConfig.weightEMAStack, forKey: "weightEMAStack")
        UserDefaults.standard.set(scalpingConfig.weightBollingerRejection, forKey: "weightBollingerRejection")
        UserDefaults.standard.set(scalpingConfig.weightCCICycle, forKey: "weightCCICycle")
        UserDefaults.standard.set(scalpingConfig.weightSARTrend, forKey: "weightSARTrend")
        UserDefaults.standard.set(scalpingConfig.weightMomentumSurge, forKey: "weightMomentumSurge")
        UserDefaults.standard.set(scalpingConfig.weightOrderFlow, forKey: "weightOrderFlow")
        UserDefaults.standard.set(scalpingConfig.weightMLConfirmed, forKey: "weightMLConfirmed")
        
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
    
    // V10.3 Performance Extension
    var totalDailyPnL: Double { 
        let today = Calendar.current.startOfDay(for: Date())
        return tradeHistory.filter { ($0.exitTime ?? Date()) >= today }.compactMap { $0.pnl }.reduce(0, +)
    }
    
    var totalBuyTrades: Int { tradeHistory.filter { $0.type == .buy }.count }
    var totalSellTrades: Int { tradeHistory.filter { $0.type == .sell }.count }
    var totalBuyWins: Int { tradeHistory.filter { $0.type == .buy && ($0.pnl ?? 0) > 0 }.count }
    var totalSellWins: Int { tradeHistory.filter { $0.type == .sell && ($0.pnl ?? 0) > 0 }.count }
    var totalBuyPnL: Double { tradeHistory.filter { $0.type == .buy }.compactMap { $0.pnl }.reduce(0, +) }
    var totalSellPnL: Double { tradeHistory.filter { $0.type == .sell }.compactMap { $0.pnl }.reduce(0, +) }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .newGodModeInsight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self = self else { return }
                if let insight = note.object as? GodModeInsight {
                    // Prevent duplicate news/performance alerts
                    if !self.allInsights.contains(where: { 
                        $0.type == insight.type && 
                        $0.title == insight.title && 
                        abs($0.timestamp.timeIntervalSince(insight.timestamp)) < 60 
                    }) {
                        self.allInsights.insert(insight, at: 0)
                        if self.allInsights.count > 100 { self.allInsights.removeLast() }
                        
                        self.showNotification(title: "🧠 \(insight.type.rawValue)", message: "\(insight.title): \(insight.message)")
                    }
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
                    
                    if !self.allInsights.contains(where: {
                        $0.type == insight.type && 
                        $0.title == insight.title && 
                        $0.message == insight.message
                    }) {
                        self.allInsights.insert(insight, at: 0)
                        if self.allInsights.count > 100 { self.allInsights.removeLast() }
                        self.showNotification(title: "🧠 Stellas Insight", message: "\(signal.symbol): \(insight.message)")
                    }
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
                guard let self = self else { return }
                if let account = notification.object as? MT5AccountInfo {
                    godLog("💰 Dashboard: Live Balance Sync - Equity: \(account.equity)", level: .info)
                    // Update balance only if it's different to prevent redundant UI refreshes
                    if self.accountBalance != account.equity {
                        self.accountBalance = account.equity
                        self.accountCurrency = account.currency
                        // FORCE SAVE TO USERDEFAULTS TO OVERWRITE STALE VALUES
                        UserDefaults.standard.set(account.equity, forKey: "accountBalance")
                        self.syncRiskParameters()
                    }
                }
            }
            .store(in: &cancellables)
    }
}
