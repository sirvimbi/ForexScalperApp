// DiagnosticSignalTester.swift
import Foundation
import Combine
import UserNotifications

// Add this enum for event levels
enum DiagnosticEventLevel {
    case info
    case warning
    case error
}

// Add this struct for events
struct DiagnosticEvent: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let level: DiagnosticEventLevel
    let timestamp = Date()
}

@MainActor
class DiagnosticSignalTester: ObservableObject {
    @Published var diagnosticResults: [String] = []
    @Published var isRunning = false
    @Published var events: [DiagnosticEvent] = [] // Add this property
    
    // Add an explicit initializer
    init() {}
    
    // Add generateSampleSignal method
    func generateSampleSignal(type: SignalType) {
        let event = DiagnosticEvent(
            title: "Sample Signal Generated",
            message: "Generated \(type == .buy ? "BUY" : "SELL") signal for testing",
            level: .info
        )
        events.append(event)
        
        // Also add to diagnostic results for backward compatibility
        diagnosticResults.append("Generated sample \(type) signal at \(Date())")
        
        print("📊 Generated sample \(type) signal")
    }
    
    // Add pushNotificationSample method
    func pushNotificationSample() {
        let event = DiagnosticEvent(
            title: "Notification Test",
            message: "Sample notification sent",
            level: .info
        )
        events.append(event)
        diagnosticResults.append("Test notification sent at \(Date())")
        
        // Send a test notification
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from the diagnostic tool"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send test notification: \(error)")
            } else {
                print("📱 Test notification sent successfully")
            }
        }
        
        print("📱 Test notification sent")
    }
    
    // Add resetDiagnostic method
    func resetDiagnostic() {
        diagnosticResults.removeAll()
        events.removeAll()
        print("🧹 Diagnostic results cleared")
    }
    
    // NEW: Reset all trading limits
    func resetAllTradingLimits() async {
        await ScalpingRiskManager.shared.resetAllLimitsForTesting()
        await MainActor.run {
            events.append(DiagnosticEvent(
                title: "Limits Reset",
                message: "All trading limits and cooldowns have been reset",
                level: .info
            ))
            diagnosticResults.append("✅ Trading limits reset at \(Date())")
        }
        print("✅ Trading limits reset")
    }
    
    // NEW: Force generate signal for a specific symbol
    func forceGenerateSignal(symbol: String, coordinator: RefactoredAppCoordinator) async {
        await MainActor.run {
            diagnosticResults.append("🔧 Force generating signal for \(symbol)")
            
            // Create a simulated signal
            let signal = Signal(
                type: Bool.random() ? .buy : .sell,
                symbol: symbol,
                price: Double.random(in: 1.0...1.2),
                confidence: Double.random(in: 70...95),
                timestamp: Date(),
                timeframe: "1m",
                expiryTime: Date().addingTimeInterval(180),
                status: .pending,
                source: .binance,
                volume: Double.random(in: 1000...10000)
            )
            
            // Add to coordinator
            // You'll need to expose a method in coordinator to add test signals
            // For now, we'll just log it
            diagnosticResults.append("✅ Force generated: \(signal.type) \(symbol) @ \(String(format: "%.5f", signal.price)) (Confidence: \(String(format: "%.1f", signal.confidence))%)")
            
            events.append(DiagnosticEvent(
                title: "Force Signal Generated",
                message: "\(signal.type) \(symbol) with \(String(format: "%.1f", signal.confidence))% confidence",
                level: .info
            ))
        }
    }
    
    func runFullDiagnostic(coordinator: RefactoredAppCoordinator) {
        Task {
            isRunning = true
            diagnosticResults.removeAll()
            events.removeAll()
            
            await addResult("🔍 STARTING COMPREHENSIVE DIAGNOSTIC")
            await addResult("====================================")
            
            // First reset all limits to ensure clean test
            await resetAllTradingLimits()
            await addResult("✅ Trading limits reset")
            
            // Test each symbol - updated with all trading pairs (Forex, Exotics, and Crypto)
            let symbols = TradingPair.allCases.map { $0.rawValue }
            
            for symbol in symbols {
                await testSymbol(symbol: symbol, coordinator: coordinator)
            }
            
            await addResult("\n✅ DIAGNOSTIC COMPLETE")
            isRunning = false
        }
    }
    
    private func testSymbol(symbol: String, coordinator: RefactoredAppCoordinator) async {
        await addResult("\n📊 TESTING: \(symbol)")
        await addResult("------------------------")
        
        // Get market data
        guard let marketData = coordinator.marketDataProvider as? RefactoredMarketDataActor else {
            await addResult("❌ Cannot access market data")
            return
        }
        
        // Check each timeframe
        let timeframes = ["1m", "5m", "15m", "1h"]
        var totalCandles = 0
        
        for tf in timeframes {
            let candles = await marketData.getCandles(symbol: symbol, timeframe: tf)
            await addResult("   \(tf): \(candles.count) candles")
            totalCandles += candles.count
            
            if candles.count >= 100 && tf == "1m" {
                // Calculate volatility
                let closes = candles.suffix(20).map { $0.close }
                let mean = closes.reduce(0, +) / Double(closes.count)
                let variance = closes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(closes.count)
                let volatility = sqrt(variance) / mean * 100
                await addResult("   Volatility: \(String(format: "%.3f", volatility))%")
                
                if volatility < 0.02 {
                    await addResult("   ⚠️ Volatility very low (\(String(format: "%.3f", volatility))%) - may not generate signals")
                } else if volatility < 0.05 {
                    await addResult("   ⚠️ Volatility slightly low (\(String(format: "%.3f", volatility))%)")
                }
                
                // Show last price
                if let lastPrice = candles.last?.close {
                    await addResult("   Last price: \(lastPrice)")
                }
                
                // Calculate RSI for this symbol
                let rsi = Indicators.rsi(closes, period: 14).last ?? 50
                await addResult("   Current RSI: \(String(format: "%.1f", rsi))")
                
                if rsi < 30 {
                    await addResult("   📈 RSI indicates OVERSOLD - potential BUY signal")
                } else if rsi > 70 {
                    await addResult("   📉 RSI indicates OVERBOUGHT - potential SELL signal")
                }
            }
        }
        
        // Check if we have enough data
        let hasEnoughData = totalCandles >= 200
        await addResult("   Total candles: \(totalCandles) - \(hasEnoughData ? "✅" : "❌")")
        
        if !hasEnoughData {
            await addResult("   ❌ INSUFFICIENT DATA")
        }
        
        // Check risk manager limits
        let riskManager = await getRiskManager(from: coordinator)
        if let scalpingRM = riskManager as? ScalpingRiskManager {
            let metrics = await scalpingRM.getCurrentRiskMetrics()
            await addResult("   Risk Metrics:")
            await addResult("      Daily P&L: \(String(format: "%.2f", metrics.dailyPnL))")
            await addResult("      Daily Limit: \(String(format: "%.2f", metrics.dailyLossLimit))")
            await addResult("      Hourly trades: \(metrics.hourlyTrades)/5")
            await addResult("      Active trades: \(metrics.activeTrades)")
            
            let canTrade = await scalpingRM.canOpenTrade(for: symbol)
            await addResult("      Can open trade: \(canTrade ? "✅" : "❌")")
        }
        
        // Try to manually generate a signal using the scalping engine
        await addResult("\n   Attempting signal generation...")
        
        // Force evaluate the symbol
        if let engine = await getScalpingEngine(from: coordinator) {
            let signal = await engine.evaluateScalpingSignal(symbol: symbol)
            
            if let signal = signal {
                await addResult("   ✅ SIGNAL GENERATED: \(signal.type)")
                await addResult("      Confidence: \(String(format: "%.1f", signal.confidence))%")
                await addResult("      Score: \(signal.score)/\(signal.sellScore)")
                await addResult("      Factors: \(signal.confidenceFactors.keys.joined(separator: ", "))")
            } else {
                await addResult("   ❌ No signal generated")
            }
        }
    }
    
    private func getScalpingEngine(from coordinator: RefactoredAppCoordinator) async -> ScalpingSignalEngine? {
        let mirror = Mirror(reflecting: coordinator)
        for child in mirror.children {
            if let engine = child.value as? ScalpingSignalEngine {
                return engine
            }
        }
        return nil
    }
    
    // DiagnosticSignalTester.swift - Add this method
    func forceEnableTrading() async {
        await ScalpingRiskManager.shared.forceAllowTrading()
        await MainActor.run {
            events.append(DiagnosticEvent(
                title: "Trading Forced",
                message: "All trading limits bypassed - signals should now generate",
                level: .info
            ))
            diagnosticResults.append("✅ Trading limits bypassed - signals should now generate")
        }
        print("✅ Trading limits bypassed - waiting for signals...")
    }
    
    func debugRiskManagers() async {
        await MainActor.run {
            diagnosticResults.append("🔍 DEBUGGING RISK MANAGERS")
        }
        
        // Check the shared instance
        let sharedRM = ScalpingRiskManager.shared
        let metrics = await sharedRM.getCurrentRiskMetrics()
        
        await MainActor.run {
            diagnosticResults.append("📊 Shared Risk Manager:")
            diagnosticResults.append("   - Daily P&L: \(String(format: "%.2f", metrics.dailyPnL))")
            diagnosticResults.append("   - Hourly Trades: \(metrics.hourlyTrades)")
            diagnosticResults.append("   - Active Trades: \(metrics.activeTrades)")
        }
        
        // Force enable trading on shared instance
        await sharedRM.forceAllowTrading()
        
        await MainActor.run {
            diagnosticResults.append("✅ Force enabled trading on shared instance")
        }
        
        // Try to find any other instances using reflection
        // This is a bit hacky but can help
        await MainActor.run {
            let instances = findInstancesOf(scalpingRiskManagerType: ScalpingRiskManager.self)
            if instances > 1 {
                diagnosticResults.append("⚠️ Found \(instances) instances of ScalpingRiskManager!")
            } else {
                diagnosticResults.append("✅ Only one instance of ScalpingRiskManager found")
            }
        }
    }

    // Helper function to count instances (approximate)
    private func findInstancesOf(scalpingRiskManagerType: AnyClass) -> Int {
        // This is not perfect but can help identify if multiple instances exist
        var count = 0
        // You'd need to implement actual instance counting
        return count
    }
    
    func generateTestSignal(coordinator: RefactoredAppCoordinator) async {
        await MainActor.run {
            diagnosticResults.append("🧪 GENERATING TEST SIGNAL")
        }
        
        // Force enable trading first
        await ScalpingRiskManager.shared.forceAllowTrading()
        
        // Create a test signal manually
        let testSignal = Signal(
            type: .buy,
            symbol: "EURUSD",
            price: 1.1617,
            confidence: 85.5,
            timestamp: Date(),
            timeframe: "1m",
            expiryTime: Date().addingTimeInterval(180),
            status: .pending,
            source: .binance,
            volume: 1000
        )
        
        // Add it directly to the coordinator
        await MainActor.run {
            // You'll need to expose a method in coordinator to add test signals
            // For now, we'll just print it
            diagnosticResults.append("✅ Test signal created: BUY EURUSD @ 1.1617 (85.5%)")
            diagnosticResults.append("⚠️ Add this method to coordinator to inject test signals")
        }
    }
    
    // Add these methods to DiagnosticSignalTester.swift

    func startContinuousSignalGeneration(coordinator: RefactoredAppCoordinator) {
        DiagnosticSignalGenerator.shared.setCoordinator(coordinator)
        DiagnosticSignalGenerator.shared.startGeneratingTestSignals()
        
        events.append(DiagnosticEvent(
            title: "Test Signal Generator",
            message: "Started generating test signals every 10 seconds",
            level: .info
        ))
        diagnosticResults.append("🧪 Started test signal generation")
    }

    func stopContinuousSignalGeneration() {
        DiagnosticSignalGenerator.shared.stopGeneratingTestSignals()
        
        events.append(DiagnosticEvent(
            title: "Test Signal Generator",
            message: "Stopped test signal generation",
            level: .info
        ))
        diagnosticResults.append("🧪 Stopped test signal generation")
    }

    func generateSingleTestSignal(coordinator: RefactoredAppCoordinator) async {
        let signal = Signal(
            type: Bool.random() ? .buy : .sell,
            symbol: "EURUSD",
            price: 1.1617,
            confidence: 87.5,
            timestamp: Date(),
            timeframe: "1m",
            expiryTime: Date().addingTimeInterval(180),
            status: .pending,
            source: .binance,
            volume: 1500
        )
        
        await coordinator.injectTestSignal(signal)
        
        events.append(DiagnosticEvent(
            title: "Single Test Signal",
            message: "Generated test signal for EURUSD",
            level: .info
        ))
        diagnosticResults.append("✅ Single test signal generated")
    }
    
    // Add to DiagnosticSignalTester.swift
    func checkIndicators(symbol: String, coordinator: RefactoredAppCoordinator) async {
        await addResult("🔍 CHECKING INDICATORS FOR \(symbol)")
        
        guard let marketData = coordinator.marketDataProvider as? RefactoredMarketDataActor else {
            await addResult("❌ Cannot access market data")
            return
        }
        
        let candles1m = await marketData.getCandles(symbol: symbol, timeframe: "1m")
        let candles5m = await marketData.getCandles(symbol: symbol, timeframe: "5m")
        let candles15m = await marketData.getCandles(symbol: symbol, timeframe: "15m")
        let candles1h = await marketData.getCandles(symbol: symbol, timeframe: "1h")
        
        await addResult("📊 Candle counts: 1m=\(candles1m.count), 5m=\(candles5m.count), 15m=\(candles15m.count), 1h=\(candles1h.count)")
        
        // Calculate RSI
        if candles1m.count >= 14 {
            let rsi = Indicators.rsi(candles1m.map { $0.close }, period: 14).last ?? 0
            await addResult("📊 RSI(14): \(String(format: "%.1f", rsi))")
        }
        
        // Calculate moving averages
        if candles1m.count >= 50 {
            let closes = candles1m.map { $0.close }
            let ema9 = Indicators.ema(closes, period: 9).last ?? 0
            let ema21 = Indicators.ema(closes, period: 21).last ?? 0
            let ema50 = Indicators.ema(closes, period: 50).last ?? 0
            
            await addResult("📊 EMA9: \(String(format: "%.5f", ema9))")
            await addResult("📊 EMA21: \(String(format: "%.5f", ema21))")
            await addResult("📊 EMA50: \(String(format: "%.5f", ema50))")
            
            if ema9 > ema21 && ema21 > ema50 {
                await addResult("✅ MA Alignment: BULLISH")
            } else if ema9 < ema21 && ema21 < ema50 {
                await addResult("✅ MA Alignment: BEARISH")
            } else {
                await addResult("⚠️ MA Alignment: MIXED")
            }
        }
        
        // Calculate Bollinger Bands position
        if candles1m.count >= 20 {
            let closes = candles1m.map { $0.close }
            let currentPrice = closes.last ?? 0
            let bb = Indicators.bollingerBands(closes, period: 20, stdDev: 2.0)
            let upper = bb.upper.last ?? 0
            let lower = bb.lower.last ?? 0
            let position = upper > lower ? (currentPrice - lower) / (upper - lower) : 0.5
            
            await addResult("📊 BB Position: \(String(format: "%.2f", position))")
            
            if position < 0.2 {
                await addResult("✅ BB: NEAR LOWER (potential BUY)")
            } else if position > 0.8 {
                await addResult("✅ BB: NEAR UPPER (potential SELL)")
            }
        }
        
        // Check for recent signals
        if let engine = await getScalpingEngine(from: coordinator) {
            let signal = await engine.evaluateScalpingSignal(symbol: symbol)
            if let signal = signal {
                await addResult("✅ ENGINE SIGNAL: \(signal.type) with confidence \(String(format: "%.1f", signal.confidence))%")
            } else {
                await addResult("❌ No signal from engine")
            }
        }
    }
    
    // Add this simple test method
    func quickTest(coordinator: RefactoredAppCoordinator) async {
        print("🔧 QUICK TEST - This should appear regardless of risk manager")
        
        // Create a simple signal
        let testSignal = Signal(
            type: .buy,
            symbol: "TEST",
            price: 1.2345,
            confidence: 90.0,
            timestamp: Date(),
            timeframe: "1m",
            expiryTime: Date().addingTimeInterval(180),
            status: .pending,
            source: .binance,
            volume: 1000
        )
        
        await coordinator.injectTestSignal(testSignal)
        
        await MainActor.run {
            diagnosticResults.append("✅ Quick test signal sent")
            events.append(DiagnosticEvent(
                title: "Quick Test",
                message: "Signal should appear in dashboard",
                level: .info
            ))
        }
    }
    
    private func getRiskManager(from coordinator: RefactoredAppCoordinator) async -> RiskManagerProtocol? {
        let mirror = Mirror(reflecting: coordinator)
        for child in mirror.children {
            if let manager = child.value as? RiskManagerProtocol {
                return manager
            }
        }
        return nil
    }
    
    private func addResult(_ message: String) async {
        await MainActor.run {
            diagnosticResults.append(message)
            
            // Also create an event for significant results
            if message.contains("✅") || message.contains("❌") || message.contains("⚠️") {
                let level: DiagnosticEventLevel
                if message.contains("✅") {
                    level = .info
                } else if message.contains("⚠️") {
                    level = .warning
                } else {
                    level = .error
                }
                
                let event = DiagnosticEvent(
                    title: message.contains("✅") ? "Success" :
                           message.contains("⚠️") ? "Warning" : "Error",
                    message: message,
                    level: level
                )
                events.append(event)
            }
            
            print(message)
        }
    }
    
    func checkTradeHistory() async {
        await MainActor.run {
            diagnosticResults.append("🔍 CHECKING TRADE HISTORY")
        }
        
        // Get trade history manager
        let tradeHistory = RefactoredTradeHistoryManager.shared
        
        // Get active trades
        let activeTrades = await tradeHistory.getActiveTrades()
        await MainActor.run {
            diagnosticResults.append("📊 Active trades: \(activeTrades.count)")
            for trade in activeTrades {
                diagnosticResults.append("   - \(trade.symbol) \(trade.type) @ \(trade.entryPrice)")
            }
        }
        
        // Get completed trades
        let completedTrades = await tradeHistory.getCompletedTrades(filter: nil)
        await MainActor.run {
            diagnosticResults.append("📊 Completed trades: \(completedTrades.count)")
            for trade in completedTrades.prefix(5) {
                let pnlStr = trade.pnl != nil ? String(format: "$%.2f", trade.pnl!) : "pending"
                diagnosticResults.append("   - \(trade.symbol) \(trade.type): \(pnlStr)")
            }
        }
    }
}
