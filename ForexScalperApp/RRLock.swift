// RRLock.swift - Risk/Reward Validation + final signal safety gate
import Foundation

private actor RRExecutionLedger {
    private var accepted: [String: Date] = [:]

    func shouldAccept(key: String, cooldown: TimeInterval) -> Bool {
        let now = Date()
        accepted = accepted.filter { now.timeIntervalSince($0.value) < cooldown }
        if accepted[key] != nil { return false }
        accepted[key] = now
        return true
    }
}

struct RRLock {
    private static let executionLedger = RRExecutionLedger()

    static func validate(signal: ScalpingSignal) async -> Bool {
        let (enabled, minRatio, cooldown, runnerConfiguration) = await MainActor.run {
            (
                ScalpingConfig.shared.enableRRCheck,
                ScalpingConfig.shared.minRRRatio,
                max(ScalpingConfig.shared.cooldownSeconds, 1.0),
                ScalpingConfig.shared.runnerContinuationConfiguration
            )
        }

        let h4 = signal.indicators.h4Trend
        let d1 = signal.indicators.d1Trend

        // SYMMETRIC FIX: Allow BOTH buy AND sell alignment
        let expectedDirection: SignalType?
        if h4 == .buy && d1 == .buy {
            expectedDirection = .buy
        } else if h4 == .sell && d1 == .sell {
            expectedDirection = .sell
        } else {
            expectedDirection = nil
        }

        // Allow signals that match OR if no clear HTF trend (flexible but logged)
        if let expected = expectedDirection {
            guard signal.type == expected else {
                print("🛑 RRLock: Direction guard rejected \(signal.symbol) | signal=\(signal.type) | H4=\(h4) D1=\(d1)")
                return false
            }
        } else {
            // Mixed trend — we allow but log as lower probability
            print("⚖️ RRLock: Mixed HTF Trend (\(h4)/\(d1)) for \(signal.symbol) — evaluating short-term momentum")
        }

        let priceBucket = Int((signal.price * 100000.0).rounded())
        let slBucket = Int(((signal.stopLoss ?? 0) * 100000.0).rounded())
        let tpBucket = Int(((signal.takeProfit ?? 0) * 100000.0).rounded())
        let executionKey = "\(signal.symbol)|\(signal.type)|\(priceBucket)|\(slBucket)|\(tpBucket)"

        if runnerConfiguration.enabled {
            let required = max(runnerConfiguration.candleLookback + 20, runnerConfiguration.atrLookback + 5)
            do {
                let raw = try await MT5Service.shared.getCandles(symbol: signal.symbol, timeframe: "1m", count: max(required, 100))
                let closed = raw.filter(\.isClosed)
                let runnerCandles = closed.map { RunnerCandle(open: $0.open, high: $0.high, low: $0.low, close: $0.close) }
                guard runnerCandles.count >= required else {
                    print("🛑 RRLock: Runner gate rejected \(signal.symbol) | insufficient closed candles=\(runnerCandles.count) need=\(required)")
                    return false
                }

                let lookback = min(max(runnerConfiguration.candleLookback, 2), 8)
                let levelWindow = Array(runnerCandles.dropLast(lookback).suffix(20))
                let keyLevel: Double?
                switch signal.type {
                case .buy: keyLevel = levelWindow.map(\.high).max()
                case .sell: keyLevel = levelWindow.map(\.low).min()
                case .none: keyLevel = nil
                }
                let atrWindow = Array(runnerCandles.suffix(max(runnerConfiguration.atrLookback + 1, 6)))
                let atr = calculateATR(atrWindow, period: runnerConfiguration.atrLookback)
                let result = RunnerContinuationGate(configuration: runnerConfiguration).evaluate(
                    direction: signal.type.displayName,
                    candles: runnerCandles,
                    keyLevel: keyLevel,
                    atr: atr
                )
                print("🏃 RUNNER GATE | \(signal.symbol) | \(signal.type.displayName) | aligned=\(result.alignedCandles) | accel=\(String(format: "%.2f", result.accelerationRatio))x | extension=\(String(format: "%.2f", result.extensionATR))ATR | body=\(String(format: "%.2f", result.latestBodyToRange)) | wick=\(String(format: "%.2f", result.latestOpposingWickRatio)) | result=\(result.passed ? "PASS" : "BLOCK") | reason=\(result.reason)")
                guard result.passed else { return false }
            } catch {
                print("🛑 RRLock: Runner gate rejected \(signal.symbol) | candle fetch failed: \(error.localizedDescription)")
                return false
            }
        }

        if !enabled {
            let unique = await executionLedger.shouldAccept(key: executionKey, cooldown: cooldown)
            guard unique else {
                print("🛑 RRLock: Duplicate execution blocked \(signal.symbol) | \(signal.type) | key=\(executionKey)")
                return false
            }
            print("ℹ️ RRLock: R:R check disabled by user")
            return true
        }

        guard let sl = signal.stopLoss, let tp = signal.takeProfit else {
            print("❌ RRLock: Missing SL or TP")
            return false
        }

        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let ratio = reward / max(risk, 0.00001)
        guard ratio >= minRatio else {
            print("❌ RRLock: R:R ratio \(String(format: "%.2f", ratio)) < \(String(format: "%.1f", minRatio))")
            return false
        }

        // ASSET-AWARE MIN MOVE: Don't use hardcoded 0.0001 for indices
        let pointSize = try? await MT5Service.shared.getSymbolInfo(signal.symbol).point ?? 0.00001
        let minPriceMove = (pointSize ?? 0.00001) * 2.0
        guard risk >= minPriceMove && reward >= minPriceMove else {
            print("❌ RRLock: Price move too small (\(risk) / \(reward)) | min required=\(minPriceMove)")
            return false
        }

        let unique = await executionLedger.shouldAccept(key: executionKey, cooldown: cooldown)
        guard unique else {
            print("🛑 RRLock: Duplicate execution blocked \(signal.symbol) | \(signal.type) | key=\(executionKey)")
            return false
        }

        print("✅ RRLock: R:R \(String(format: "%.2f", ratio)):1 PASSED (Threshold: \(minRatio))")
        return true
    }

    private static func calculateATR(_ candles: [RunnerCandle], period: Int) -> Double {
        guard candles.count >= 2 else { return 0 }
        let trueRanges = candles.dropFirst().enumerated().map { index, candle -> Double in
            let previous = candles[index]
            return max(candle.high - candle.low, abs(candle.high - previous.close), abs(candle.low - previous.close))
        }
        let window = trueRanges.suffix(max(1, min(period, trueRanges.count)))
        return window.reduce(0, +) / Double(window.count)
    }
}
