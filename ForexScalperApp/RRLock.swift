// RRLock.swift - Risk/Reward Validation + final signal safety gate
import Foundation

private actor RRExecutionLedger {
    private var accepted: [String: Date] = [:]

    func shouldAccept(key: String, cooldown: TimeInterval) -> Bool {
        let now = Date()
        accepted = accepted.filter { now.timeIntervalSince($0.value) < cooldown }
        if accepted[key] != nil {
            return false
        }
        accepted[key] = now
        return true
    }
}

struct RRLock {
    private static let executionLedger = RRExecutionLedger()

    static func validate(signal: ScalpingSignal) async -> Bool {
        // 1. Fetch User Settings
        let (enabled, minRatio, cooldown) = await MainActor.run {
            (ScalpingConfig.shared.enableRRCheck,
             ScalpingConfig.shared.minRRRatio,
             max(ScalpingConfig.shared.cooldownSeconds, 1.0))
        }

        // 2. Direction is authoritative: H4 + D1 must agree with the executable signal.
        // This is intentionally a final safety gate so no downstream caller can publish
        // a counter-trend BUY/SELL even if an earlier score calculation flips direction.
        let h4 = signal.indicators.h4Trend
        let d1 = signal.indicators.d1Trend
        let expectedDirection: SignalType?
        if h4 == .buy && d1 == .buy {
            expectedDirection = .buy
        } else if h4 == .sell && d1 == .sell {
            expectedDirection = .sell
        } else {
            expectedDirection = nil
        }

        guard let expectedDirection, signal.type == expectedDirection else {
            print("🛑 RRLock: Direction guard rejected \(signal.symbol) | signal=\(signal.type) | H4=\(h4) D1=\(d1)")
            return false
        }

        let priceBucket = Int((signal.price * 100000.0).rounded())
        let slBucket = Int(((signal.stopLoss ?? 0) * 100000.0).rounded())
        let tpBucket = Int(((signal.takeProfit ?? 0) * 100000.0).rounded())
        let executionKey = "\(signal.symbol)|\(signal.type)|\(priceBucket)|\(slBucket)|\(tpBucket)"

        // If R:R is disabled, the safety direction + duplicate gates still apply.
        if !enabled {
            let unique = await executionLedger.shouldAccept(key: executionKey, cooldown: cooldown)
            guard unique else {
                print("🛑 RRLock: Duplicate execution blocked \(signal.symbol) | \(signal.type) | key=\(executionKey)")
                return false
            }
            print("ℹ️ RRLock: Check disabled by user")
            return true
        }

        guard let sl = signal.stopLoss, let tp = signal.takeProfit else {
            print("❌ RRLock: Missing SL or TP")
            return false
        }

        let risk = abs(signal.price - sl)
        let reward = abs(tp - signal.price)
        let ratio = reward / max(risk, 0.00001)

        if ratio < minRatio {
            print("❌ RRLock: R:R ratio \(String(format: \"%.2f\", ratio)) < \(String(format: \"%.1f\", minRatio))")
            return false
        }

        // V10.0 Precision: Validate minimum price movement (hard floor)
        let minMovePips: Double = 1.0
        let pipSize = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        let minPriceMove = pipSize * minMovePips

        if risk < minPriceMove || reward < minPriceMove {
            print("❌ RRLock: Price move too small (\(risk) / \(reward))")
            return false
        }

        // Final duplicate-execution gate. The same symbol/direction/price/SL/TP
        // cannot be accepted again during the configured cooldown window, even if
        // multiple callers invoke RRLock concurrently or reuse the same signal object.
        let unique = await executionLedger.shouldAccept(key: executionKey, cooldown: cooldown)
        guard unique else {
            print("🛑 RRLock: Duplicate execution blocked \(signal.symbol) | \(signal.type) | key=\(executionKey)")
            return false
        }

        print("✅ RRLock: R:R \(String(format: \"%.2f\", ratio)):1 PASSED (Threshold: \(minRatio))")
        return true
    }
}
