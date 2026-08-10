// RRLock.swift - Risk/Reward Validation
import Foundation

struct RRLock {
    static func validate(signal: ScalpingSignal) async -> Bool {
        // 1. Fetch User Settings
        let (enabled, minRatio) = await MainActor.run {
            (ScalpingConfig.shared.enableRRCheck, ScalpingConfig.shared.minRRRatio)
        }
        
        // 2. Bypass if disabled
        guard enabled else {
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
            print("❌ RRLock: R:R ratio \(String(format: "%.2f", ratio)) < \(String(format: "%.1f", minRatio))")
            return false
        }
        
        // V10.0 Precision: Validate minimum price movement (hard floor)
        let minMovePips: Double = 1.0 // Minimal institutional floor
        let pipSize = signal.symbol.contains("JPY") ? 0.01 : 0.0001
        let minPriceMove = pipSize * minMovePips
        
        if risk < minPriceMove || reward < minPriceMove {
            print("❌ RRLock: Price move too small (\(risk) / \(reward))")
            return false
        }
        
        print("✅ RRLock: R:R \(String(format: "%.2f", ratio)):1 PASSED (Threshold: \(minRatio))")
        return true
    }
}
