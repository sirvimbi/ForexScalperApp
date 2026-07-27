// DashboardViewModel.swift - Updated with Full Settings Functionality
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var signals: [Signal] = []
    @Published var tradeHistory: [TradeRecord] = []
    @Published var activeTrades: [TradeRecord] = []
    @Published var accountBalance: Double = 10000
    @Published var accountCurrency: String = "USD"
    @Published var riskPerTrade: Double = 0.01 { didSet { syncRiskParameters() } }
    @Published var maxDailyRisk: Double = 0.03 { didSet { syncRiskParameters() } }
    @Published var maxConcurrentTrades: Int = 3 { didSet { syncRiskParameters() } }
    @Published var igAPIKey: String = ""
    @Published var igAccountID: String = ""
    @Published var igEnvironment: String = "demo"
    @Published var igAutoReconnect: Bool = true
    @Published var igConnected: Bool = false
    @Published var igConnectionError: String = ""
    
    // MT5 Properties
    @Published var mt5Connected: Bool = false
    @Published var mt5Error: String = ""
    @Published var mt5BridgeURL: String = "http://127.0.0.1:8891"
    @Published var mt5AuthToken: String = "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
    @Published var mt5MagicNumber: Int = 888888
    
    // MT5 Account Credentials (PROD REAL DEFAULTS)
    @Published var mt5Login: String = "134522550"
    @Published var mt5Password: String = "Kenya@254"
    @Published var mt5Server: String = "ExnessKE-MT5Real9"
    
    @Published var isConnecting: Bool = false
    @Published var notifyOnSignal: Bool = true
    @Published var notifyOnTrade: Bool = true
    @Published var notifyOnClose: Bool = true
    @Published var notifyOnExpiry: Bool = true
    @Published var selectedTimeFilter: DashboardTimeFilter = .allTime
    @Published var isRefreshing: Bool = false

    @Published var mandatoryConfluenceLevel: Double = 2 // Double for slider compatibility
    @Published var defaultStopLossPercent: Double = 1.0
    @Published var defaultRRRatio: Double = 2.0
    @Published var activeSymbols: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(activeSymbols), forKey: "activeSymbols")
            print("🛡 Active Pairs Updated: \(activeSymbols.count) symbols")
        }
    }
    
    // Auto-Trade Settings
    @Published var isAutoTradeEnabled: Bool = false
    @Published var minAutoTradeConfidence: Double = 85.0
    
    // Added missing properties
    @Published var isExecutingTrade: Bool = false
    @Published var riskSettingsChanged: Bool = false
    @Published var tradingPairsChanged: Bool = false
    @Published var showSaveSuccess: Bool = false
    
    // CSV Export State
    @Published var exportURL: URL?
    @Published var isShowingShareSheet: Bool = false
    
    // Auto-refresh timer
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval = 0.5
    
    // Signal source metrics
    @Published var binanceLatency: TimeInterval = 0
    @Published var igLatency: TimeInterval = 0
    @Published var mt5Latency: TimeInterval = 0
    @Published var binanceReliability: Double = 1.0
    @Published var igReliability: Double = 1.0
    @Published var mt5Reliability: Double = 1.0
    @Published var activeSource: SignalSource = .auto
    
    let availableSymbols = TradingPair.allCases.map { $0.rawValue }
    
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
            self.mt5Latency = coordinator.sourceLatency[.mt5] ?? 0
            self.binanceReliability = coordinator.sourceReliability[.binance] ?? 1.0
            self.igReliability = coordinator.sourceReliability[.ig] ?? 1.0
            self.mt5Reliability = coordinator.sourceReliability[.mt5] ?? 1.0
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
        
        mandatoryConfluenceLevel = Double(scalpingConfig.mandatoryConfluenceLevel)
        
        // Load MT5 settings
        mt5BridgeURL = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://localhost:8891"
        mt5AuthToken = UserDefaults.standard.string(forKey: "mt5AuthToken") ?? "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
        mt5MagicNumber = UserDefaults.standard.integer(forKey: "mt5MagicNumber") != 0 ?
            UserDefaults.standard.integer(forKey: "mt5MagicNumber") : 888888
        mt5Login = UserDefaults.standard.string(forKey: "mt5Login") ?? "134522550"
        mt5Password = UserDefaults.standard.string(forKey: "mt5Password") ?? "Kenya@254"
        mt5Server = UserDefaults.standard.string(forKey: "mt5Server") ?? "ExnessKE-MT5Real9"
        
        // Load Active Trading Pairs
        if let savedSymbols = UserDefaults.standard.array(forKey: "activeSymbols") as? [String] {
            // PRODUCTION SANITIZATION: Only keep symbols that are in our current TradingPair list
            let validSymbols = Set(TradingPair.allCases.map { $0.rawValue })
            let filtered = savedSymbols.filter { validSymbols.contains($0) }
            
            activeSymbols = Set(filtered)
            
            // If sanitization resulted in empty set, use defaults
            if activeSymbols.isEmpty {
                activeSymbols = Set(["EURUSD", "GBPUSD", "USDJPY"])
            }
        } else {
            // Default to some active symbols - Forex Only
            activeSymbols = Set(["EURUSD", "GBPUSD", "USDJPY"])
        }
        
        // Load Auto-Trade settings
        isAutoTradeEnabled = UserDefaults.standard.bool(forKey: "isAutoTradeEnabled")
        minAutoTradeConfidence = UserDefaults.standard.double(forKey: "minAutoTradeConfidence") != 0 ?
            UserDefaults.standard.double(forKey: "minAutoTradeConfidence") : 85.0
        
        // CRITICAL: Push loaded settings to Risk Managers immediately on launch
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
        
        print("✅ Settings loaded from UserDefaults and synced to Risk Managers")
    }
    
    func saveSettings() {
        // Validation
        guard accountBalance >= 100 else {
            showNotification(title: "Invalid Balance", message: "Account balance must be at least $100")
            return
        }
        
        guard riskPerTrade > 0 && riskPerTrade <= 0.20 else {
            showNotification(title: "Invalid Risk", message: "Risk per trade must be between 0.1% and 20%")
            return
        }
        
        guard mt5BridgeURL.hasPrefix("http") else {
            showNotification(title: "Invalid URL", message: "Bridge URL must start with http:// or https://")
            return
        }
        
        // Save Risk Management settings (EXCEPT accountBalance, which is live)
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
        
        // Sync to ScalpingConfig
        scalpingConfig.mandatoryConfluenceLevel = Int(mandatoryConfluenceLevel)
        scalpingConfig.saveConfig()
        
        // Save IG settings
        UserDefaults.standard.set(igAPIKey, forKey: "igAPIKey")
        UserDefaults.standard.set(igAccountID, forKey: "igAccountID")
        UserDefaults.standard.set(igEnvironment, forKey: "igEnvironment")
        UserDefaults.standard.set(igAutoReconnect, forKey: "igAutoReconnect")
        
        // Save Auto-Trade settings
        UserDefaults.standard.set(isAutoTradeEnabled, forKey: "isAutoTradeEnabled")
        UserDefaults.standard.set(minAutoTradeConfidence, forKey: "minAutoTradeConfidence")
        
        // Save MT5 settings
        UserDefaults.standard.set(mt5BridgeURL, forKey: "mt5BridgeURL")
        UserDefaults.standard.set(mt5AuthToken, forKey: "mt5AuthToken")
        UserDefaults.standard.set(mt5MagicNumber, forKey: "mt5MagicNumber")
        UserDefaults.standard.set(mt5Login, forKey: "mt5Login")
        UserDefaults.standard.set(mt5Password, forKey: "mt5Password")
        UserDefaults.standard.set(mt5Server, forKey: "mt5Server")
        
        // Remove v1 from URL if user entered it (the service handles it)
        if mt5BridgeURL.hasSuffix("/v1") {
            mt5BridgeURL = String(mt5BridgeURL.dropLast(3))
            UserDefaults.standard.set(mt5BridgeURL, forKey: "mt5BridgeURL")
        } else if mt5BridgeURL.hasSuffix("/v1/") {
            mt5BridgeURL = String(mt5BridgeURL.dropLast(4))
            UserDefaults.standard.set(mt5BridgeURL, forKey: "mt5BridgeURL")
        }
        
        // Save Active Trading Pairs
        UserDefaults.standard.set(Array(activeSymbols), forKey: "activeSymbols")
        
        // Synchronize with coordinator if possible
        if self.coordinator != nil {
             // The coordinator's activeSymbols property is computed from UserDefaults,
             // so it will be updated automatically next time it's accessed.
        }
        
        // Update risk manager with new parameters
        Task {
            let params = RiskParameters(
                accountBalance: accountBalance,
                riskPerTrade: riskPerTrade,
                maxDailyRisk: maxDailyRisk,
                maxConcurrentTrades: maxConcurrentTrades
            )
            await RefactoredRiskManager.shared.updateParameters(params)
            await ScalpingRiskManager.shared.updateParameters(params)
        }
        
        // Update scalping config
        scalpingConfig.saveConfig()
        
        // Show success message
        showSaveSuccess = true
        riskSettingsChanged = false
        tradingPairsChanged = false
        
        showNotification(title: "Settings Saved", message: "All configuration parameters have been updated")
        print("✅ Settings saved to UserDefaults")
    }

    func showNotification(title: String, message: String) {
        // 1. System Notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        
        // 2. Local State for UI Feedback
        Task { @MainActor in
            // You can add a published 'alertMessage' here if you want an in-app alert too
            print("📢 Notification: \(title) - \(message)")
        }
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
            let currentSignals = coordinator.signals
            let currentActiveSource = coordinator.getBestSignalSource()
            let binanceLat = coordinator.sourceLatency[.binance] ?? 0
            let igLat = coordinator.sourceLatency[.ig] ?? 0
            let mt5Lat = coordinator.sourceLatency[.mt5] ?? 0
            let binanceRel = coordinator.sourceReliability[.binance] ?? 1.0
            let igRel = coordinator.sourceReliability[.ig] ?? 1.0
            let mt5Rel = coordinator.sourceReliability[.mt5] ?? 1.0
            
            await MainActor.run {
                // FILTER: Only show signals for symbols currently active in Settings
                self.signals = currentSignals.filter { self.activeSymbols.contains($0.symbol) }

                self.activeSource = currentActiveSource
                self.binanceLatency = binanceLat
                self.igLatency = igLat
                self.mt5Latency = mt5Lat
                self.binanceReliability = binanceRel
                self.igReliability = igRel
                self.mt5Reliability = mt5Rel
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
        case .mt5:
            return mt5Reliability > 0.7 ? .green : (mt5Reliability > 0.3 ? .orange : .red)
        case .auto:
            return .accentCyan
        case .both:
            return .purple
        }
    }
    
    // Single acceptSignal method
    func acceptSignal(_ signal: Signal) {
        // Validation
        guard signal.volume > 0 || (signal.positionSize ?? 0) > 0 else {
            showNotification(title: "Invalid Volume", message: "Trade volume must be greater than 0")
            return
        }
        
        guard signal.price > 0 else {
            showNotification(title: "Invalid Price", message: "Entry price must be valid")
            return
        }
        
        // Show loading state
        isExecutingTrade = true
        
        coordinator?.acceptSignal(signal)
        
        showNotification(title: "Execution Sent", message: "Order for \(signal.symbol) dispatched to MT5")
        
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
        case .mt5:
            latency = mt5Latency
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
            loadTradeHistory()
        }
    }
    
    func clearAllHistory() {
        Task {
            await RefactoredTradeHistoryManager.shared.clearAllHistory()
            loadTradeHistory()
        }
    }

    func prepareCSVExport() async {
        let csvString = await RefactoredTradeHistoryManager.shared.generateCSV()
        let fileName = "GodMode_History_\(Int(Date().timeIntervalSince1970)).csv"
        
        #if os(macOS)
        // USE NSSAVEPANEL TO BYPASS PERMISSION ISSUES
        await MainActor.run {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.commaSeparatedText]
            savePanel.nameFieldStringValue = fileName
            savePanel.message = "Choose where to save your Trade History"
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                do {
                    try csvString.write(to: url, atomically: true, encoding: .utf8)
                    godLog("📁 CSV Exported: \(url.path)", level: .success)
                    showNotification(title: "Export Successful", message: "CSV saved successfully.")
                    self.exportURL = url
                } catch {
                    godLog("❌ Export Failed: \(error.localizedDescription)", level: .error)
                    showNotification(title: "Export Failed", message: error.localizedDescription)
                }
            }
        }
        #else
        // iOS: Still use temporary directory for ShareSheet
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
            await MainActor.run {
                self.exportURL = tempURL
                self.isShowingShareSheet = true
            }
        } catch {
            print("❌ Failed to write temp CSV: \(error)")
        }
        #endif
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

    func refreshAccountInfo() async {
        do {
            let account = try await MT5Service.shared.getAccountInfo()
            await MainActor.run {
                self.accountBalance = account.equity
                self.accountCurrency = account.currency
                print("💰 Manual Equity Refresh: KES \(account.equity)")
                
                // Update risk managers
                let params = RiskParameters(
                    accountBalance: account.equity,
                    riskPerTrade: self.riskPerTrade,
                    maxDailyRisk: self.maxDailyRisk,
                    maxConcurrentTrades: self.maxConcurrentTrades
                )
                
                Task {
                    await RefactoredRiskManager.shared.updateParameters(params)
                    await ScalpingRiskManager.shared.updateParameters(params)
                }
            }
        } catch {
            print("❌ Account Refresh Failed: \(error)")
        }
    }
    
    func connectToMT5() async {
        guard !isConnecting else { return }
        
        await MainActor.run {
            self.mt5Connected = false
            self.mt5Error = ""
            self.isConnecting = true
            saveSettings()
        }
        
        do {
            MT5Service.shared.setBaseURL(mt5BridgeURL)
            MT5Service.shared.setAuthToken(mt5AuthToken)
            
            let connected = try await MT5Service.shared.checkConnection()
            
            if connected {
                // FETCH ACCOUNT INFO - Use Equity for Risk Calculation
                if let account = try? await MT5Service.shared.getAccountInfo() {
                    await MainActor.run {
                        self.accountBalance = account.equity // Use Equity instead of Balance
                        self.accountCurrency = account.currency
                        print("💰 Live Equity Sync: KES \(account.equity)")
                        
                        // Push live equity to Risk Managers immediately
                        Task {
                            let params = RiskParameters(
                                accountBalance: account.equity,
                                riskPerTrade: self.riskPerTrade,
                                maxDailyRisk: self.maxDailyRisk,
                                maxConcurrentTrades: self.maxConcurrentTrades
                            )
                            await RefactoredRiskManager.shared.updateParameters(params)
                            await ScalpingRiskManager.shared.updateParameters(params)
                        }
                    }
                }

                await MainActor.run {
                    self.mt5Connected = true
                    self.isConnecting = false
                    showNotification(title: "MT5 Connected", message: "Successfully linked to Exness (\(accountCurrency))")
                }
                
                if let coordinator = self.coordinator {
                    await coordinator.start()
                }
            } else {
                print("⚠️ Dashboard: Bridge reachable, but EA not responding")
                await MainActor.run {
                    self.mt5Connected = false
                    self.isConnecting = false
                    self.mt5Error = "EA not responding. Is SocketBridgeEA on a chart?"
                    showNotification(title: "EA Offline", message: "Bridge is active, but SocketBridgeEA is not found on a chart.")
                }
            }
        } catch {
            print("❌ Dashboard: Connection failed: \(error.localizedDescription)")
            await MainActor.run {
                self.mt5Connected = false
                self.isConnecting = false
                self.mt5Error = error.localizedDescription
                showNotification(title: "Connection Failed", message: error.localizedDescription)
            }
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
        guard accountBalance > 0 else { return 0 }
        return (totalPnL / accountBalance) * 100
    }
    
    var currencySymbol: String {
        return "KES "
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

    var totalPnLString: String {
        String(format: "%@%@%.2f", totalPnL >= 0 ? "+" : "", currencySymbol, totalPnL)
    }
    
    var todayPnLString: String {
        String(format: "%@%@%.2f", todayPnL >= 0 ? "+" : "", currencySymbol, todayPnL)
    }

    var totalPnLColor: Color {
        totalPnL >= 0 ? .accentGreen : .accentRed
    }
    
    var todayPnLColor: Color {
        todayPnL >= 0 ? .accentGreen : .accentRed
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
        let positivePnLs = tradeHistory.compactMap { $0.pnl }.filter { $0 > 0 }
        let grossProfit = positivePnLs.reduce(0.0, +)
        
        let negativePnLs = tradeHistory.compactMap { $0.pnl }.filter { $0 < 0 }
        let grossLoss = abs(negativePnLs.reduce(0.0, +))
        
        if grossLoss == 0 {
            return grossProfit > 0 ? .infinity : 0
        }
        return grossProfit / grossLoss
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
        // Observe new signals to keep local array in sync
        NotificationCenter.default.publisher(for: .newSignalGenerated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)

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
        
        NotificationCenter.default.publisher(for: .mt5AccountUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let account = notification.object as? MT5AccountInfo {
                    self?.accountBalance = account.equity
                    self?.accountCurrency = account.currency
                    print("💰 Live Equity Update: KES \(account.equity)")
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
        self.mt5Latency = coordinator.sourceLatency[.mt5] ?? 0
        self.binanceReliability = coordinator.sourceReliability[.binance] ?? 1.0
        self.igReliability = coordinator.sourceReliability[.ig] ?? 1.0
        self.mt5Reliability = coordinator.sourceReliability[.mt5] ?? 1.0
        self.activeSource = coordinator.getBestSignalSource()
    }
    
    private func handleTradeUpdate(_ trade: TradeRecord) {
        // Update the trade in history if needed
        loadTradeHistory()
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
    
    deinit {
        // Stop refresh timer if active
        // Note: we can't use Task { @MainActor in self.stopAutoRefresh() } here safely in Swift 6
        // because self is being deallocated. 
        // DashboardViewModel is @MainActor, so deinit should be on MainActor too?
        // In Swift, deinit of a MainActor class is not guaranteed to be on MainActor.
    }
}

// MARK: - Extension for DashboardTimeFilter
enum DashboardTimeFilter: String, CaseIterable {
    case allTime = "ALL"
    case today = "TODAY"
    case week = "WEEK"
    case month = "MONTH"
}
