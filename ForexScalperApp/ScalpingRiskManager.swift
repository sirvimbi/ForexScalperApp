// ScalpingRiskManager.swift - GOD MODE 2.0 (FIXED)
import Foundation

// MARK: - Calendar Extension
extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}

actor ScalpingRiskManager: RiskManagerProtocol {
    static let shared = ScalpingRiskManager()

    private var parameters = RiskParameters(
        accountBalance: 10000,
        riskPerTrade: 0.005, // 0.5% risk per trade for scalping
        maxDailyRisk: 0.02,   // 2% max daily loss
        maxConcurrentTrades: 2 // Max 2 concurrent scalps
    )

    private var dailyPnL: [Date: Double] = [:]
    private var activeTrades: Set<String> = []
    private var tradeOpenTime: [String: Date] = [:]
    private var consecutiveLosses: [String: Int] = [:]
    private var hourlyTradeCount: [Date: Int] = [:]

    // FIXED: Hardcoded pip values for consistency
    private let fixedSLPips: Double = 10  // 10 pips stop loss
    private let fixedTPPips: Double = 20  // 20 pips take profit (2:1 R:R)

    func updateParameters(_ params: RiskParameters) {
        self.parameters = params
        print("🛡 Risk Manager: Updated parameters. Balance: KES \(params.accountBalance)")
    }

    func canOpenTrade(for symbol: String) async -> Bool {
        let now = Date()
        let calendar = Calendar.current

        // Check daily loss limit
        let today = calendar.startOfDay(for: now)
        let todayPnL = dailyPnL[today] ?? 0

        if todayPnL <= -parameters.accountBalance * parameters.maxDailyRisk {
            print("⚠️ Daily loss limit reached: \(String(format: "%.2f", todayPnL))")
            return false
        }

        // Hourly trade limit
        let currentHour = calendar.startOfHour(for: now)
        let hourlyTrades = hourlyTradeCount[currentHour] ?? 0
        let baseHourlyLimit = max(2, parameters.maxConcurrentTrades)
        let maxHourlyTrades = max(2, min(10, baseHourlyLimit * 2))

        if hourlyTrades >= maxHourlyTrades {
            print("⚠️ Hourly trade limit reached: \(hourlyTrades)/\(maxHourlyTrades)")
            return false
        }

        // Check concurrent trades
        if activeTrades.count >= parameters.maxConcurrentTrades {
            print("⚠️ Max concurrent trades reached: \(activeTrades.count)/\(parameters.maxConcurrentTrades)")
            return false
        }

        // Check consecutive losses - REDUCED tolerance
        let losses = consecutiveLosses[symbol] ?? 0
        if losses >= 3 { // FIXED: Reduced from 5 to 3
            print("⚠️ Too many consecutive losses (\(losses)) for \(symbol) - COOLDOWN ACTIVATED")
            return false
        }

        // Check cooldown per symbol (3 minutes for scalping - FIXED)
        if let lastTrade = tradeOpenTime[symbol],
           now.timeIntervalSince(lastTrade) < 180 { // FIXED: 120 -> 180 seconds
            print("⚠️ Cooldown active for \(symbol): \(Int(now.timeIntervalSince(lastTrade)))s/180s")
            return false
        }

        print("✅ Risk check PASSED for \(symbol)")
        return true
    }

    func calculatePositionSize(for signal: Signal) async -> PositionSize? {
        let balance = parameters.accountBalance
        let riskAmount = balance * parameters.riskPerTrade

        // FIXED: DECOUPLED FROM ATR - Use fixed pip values
        let pipSize: Double

        // Determine pip size based on symbol
        let symbol = signal.symbol
        if symbol.contains("JPY") {
            pipSize = 0.01  // JPY pairs use 0.01 per pip
        } else {
            pipSize = 0.0001 // Standard pairs use 0.0001 per pip
        }

        // FIXED: Fixed stop loss in price terms
        let slDistance = pipSize * fixedSLPips
        let tpDistance = pipSize * fixedTPPips

        // FIXED: POSITION SIZE CALCULATION FOR KES ACCOUNTS
        // 1 lot of EURUSD at 10 pips risk = $100 USD.
        // For a KES account, we must convert the risk amount to USD base for lot calculation.
        let kesToUsdRate = 130.0 // Institutional estimate for KES/USD
        let riskInUsd = riskAmount / kesToUsdRate
        
        var lotSize = riskInUsd / (slDistance * 100000)

        // MANUAL LOT OVERRIDE
        let (useManual, manualSize) = await MainActor.run {
            (ScalpingConfig.shared.useManualLot, ScalpingConfig.shared.manualLotSize)
        }
        
        if useManual {
            lotSize = manualSize
        }

        // Adjust for crypto or non-forex symbols
        let isCrypto = symbol.contains("BTC") || symbol.contains("ETH") ||
            symbol.contains("SOL") || symbol.contains("XRP") ||
            symbol.contains("DOGE") || symbol.contains("ADA") ||
            symbol.contains("LTC") || symbol.contains("AVAX")

        if isCrypto {
            lotSize = riskAmount / slDistance
        }

        // Validate with broker limits
        let limits = await MT5Service.shared.getVolumeLimits(for: signal.symbol)

        // Align with volume_step
        let steps = round(lotSize / limits.step)
        var finalLotSize = max(limits.min, min(steps * limits.step, limits.max))

        // Force 2 decimal places for standard brokers
        finalLotSize = Double(String(format: "%.2f", finalLotSize)) ?? finalLotSize

        // FIXED: Calculate SL and TP based on fixed pip values
        let sl = signal.type == .buy ? signal.price - slDistance : signal.price + slDistance
        let tp = signal.type == .buy ? signal.price + tpDistance : signal.price - tpDistance

        // FIXED: Validate R:R ratio (must be >= 1.5:1)
        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let rrRatio = reward / max(risk, 0.00001)

        guard rrRatio >= 1.5 else {
            print("❌ R:R ratio \(String(format: "%.2f", rrRatio)) < 1.5 - REJECTING")
            return nil
        }

        print("""
              📐 GOD MODE POSITION (FIXED):
                 Lot: \(String(format: "%.2f", finalLotSize))
                 SL: \(String(format: "%.5f", sl)) (\(Int(fixedSLPips)) pips)
                 TP: \(String(format: "%.5f", tp)) (\(Int(fixedTPPips)) pips)
                 R:R: \(String(format: "%.2f", rrRatio)):1
                 Risk: KES \(String(format: "%.2f", riskAmount))
              """)

        return PositionSize(
            units: finalLotSize,
            stopLoss: sl,
            takeProfit: tp,
            riskAmount: riskAmount,
            potentialReward: riskAmount * rrRatio
        )
    }

    func resetDailyLimits() async {
        dailyPnL.removeAll()
        hourlyTradeCount.removeAll()
        consecutiveLosses.removeAll()
        print("✅ Risk limits reset")
    }

    func registerTrade(_ trade: TradeRecord) async {
        activeTrades.insert(trade.symbol)
        tradeOpenTime[trade.symbol] = Date()

        let now = Date()
        let currentHour = Calendar.current.startOfHour(for: now)
        hourlyTradeCount[currentHour] = (hourlyTradeCount[currentHour] ?? 0) + 1
    }

    func closeTrade(_ trade: TradeRecord) async {
        activeTrades.remove(trade.symbol)

        if let pnl = trade.pnl {
            let today = Calendar.current.startOfDay(for: Date())
            dailyPnL[today] = (dailyPnL[today] ?? 0) + pnl

            // Track consecutive losses
            if pnl < 0 {
                consecutiveLosses[trade.symbol] = (consecutiveLosses[trade.symbol] ?? 0) + 1
            } else {
                consecutiveLosses[trade.symbol] = 0 // Reset on win
            }
        }
    }

    func getCurrentRiskMetrics() async -> RiskMetrics {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let currentHour = calendar.startOfHour(for: now)

        let baseHourlyLimit = max(2, parameters.maxConcurrentTrades)
        let maxHourlyTrades = max(2, min(10, baseHourlyLimit * 2))

        return RiskMetrics(
            dailyPnL: dailyPnL[today] ?? 0,
            dailyLossLimit: -parameters.accountBalance * parameters.maxDailyRisk,
            hourlyTrades: hourlyTradeCount[currentHour] ?? 0,
            maxHourlyTrades: maxHourlyTrades,
            activeTrades: activeTrades.count,
            maxConcurrentTrades: parameters.maxConcurrentTrades,
            consecutiveLosses: consecutiveLosses
        )
    }
}

// RiskMetrics struct (unchanged but included for completeness)
struct RiskMetrics {
    let dailyPnL: Double
    let dailyLossLimit: Double
    let hourlyTrades: Int
    let maxHourlyTrades: Int
    let activeTrades: Int
    let maxConcurrentTrades: Int
    let consecutiveLosses: [String: Int]
}