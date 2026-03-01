// SignalComparator.swift
import Foundation
import Combine // Add this import

class SignalComparator {
    
    struct SignalComparison {
        let bestSignal: Signal?
        let shouldReplace: Bool
        let sourcePriority: SignalSource
    }
    
    func compareSignals(binanceSignal: Signal?, igSignal: Signal?, newSignal: Signal) -> SignalComparison {
        // If we only have one signal, use it
        guard let binance = binanceSignal, let ig = igSignal else {
            if binanceSignal != nil {
                return SignalComparison(bestSignal: binanceSignal, shouldReplace: true, sourcePriority: .binance)
            }
            if igSignal != nil {
                return SignalComparison(bestSignal: igSignal, shouldReplace: true, sourcePriority: .ig)
            }
            return SignalComparison(bestSignal: newSignal, shouldReplace: true, sourcePriority: newSignal.source)
        }
        
        // If signals conflict, prioritize based on multiple factors
        if binance.type != ig.type {
            print("⚠️ Signal conflict: Binance says \(binance.type), IG says \(ig.type)")
            
            // Factor 1: Confidence (higher confidence wins)
            if abs(binance.confidence - ig.confidence) > 10 {
                let higherConfidence = binance.confidence > ig.confidence ? binance : ig
                print("📊 Resolving by confidence: \(higherConfidence.source.rawValue) wins")
                return SignalComparison(
                    bestSignal: higherConfidence,
                    shouldReplace: true,
                    sourcePriority: higherConfidence.source
                )
            }
            
            // Factor 2: Check for confirmation from other indicators
            if let confirmedSource = getConfirmedSource(binance: binance, ig: ig) {
                return SignalComparison(
                    bestSignal: confirmedSource == .binance ? binance : ig,
                    shouldReplace: true,
                    sourcePriority: confirmedSource
                )
            }
            
            // Factor 3: Default to the more recent signal
            let moreRecent = binance.timestamp > ig.timestamp ? binance : ig
            print("📊 Resolving by recency: \(moreRecent.source.rawValue) wins")
            return SignalComparison(
                bestSignal: moreRecent,
                shouldReplace: true,
                sourcePriority: moreRecent.source
            )
        }
        
        // Signals agree on direction
        if binance.type == ig.type {
            print("✅ Both sources agree on \(binance.type)")
            
            // Use the signal with higher confidence
            let bestSignal = binance.confidence > ig.confidence ? binance : ig
            return SignalComparison(
                bestSignal: bestSignal,
                shouldReplace: true,
                sourcePriority: .both
            )
        }
        
        // Default: keep existing if new signal is older
        if newSignal.timestamp < binance.timestamp && newSignal.timestamp < ig.timestamp {
            return SignalComparison(bestSignal: nil, shouldReplace: false, sourcePriority: .both)
        }
        
        return SignalComparison(bestSignal: newSignal, shouldReplace: true, sourcePriority: newSignal.source)
    }
    
    private func getConfirmedSource(binance: Signal, ig: Signal) -> SignalSource? {
        // Check which signal has stronger supporting factors
        
        // Factor: Timeframe alignment
        let binanceTimeframes = ["1m", "5m", "1h"]
        let igTimeframes = ["tick", "1m", "5m"]
        
        // If one signal is from a higher timeframe, it might be more reliable
        if binance.timeframe == "1h" && ig.timeframe == "1m" {
            return .binance
        }
        if ig.timeframe == "1h" && binance.timeframe == "1m" {
            return .ig
        }
        
        // Factor: Volume confirmation (Binance has volume data)
        if binance.volume > 0 && ig.volume == 0 {
            return .binance
        }
        
        return nil
    }
    
    func validateSignal(_ signal: Signal, with otherSource: Signal?) -> Bool {
        guard let other = otherSource else {
            // If no other source, still consider it valid if confidence is high enough
            return signal.confidence >= 75
        }
        
        // If both sources exist and agree, it's very strong
        if signal.type == other.type {
            return true
        }
        
        // If they disagree, require higher confidence
        return signal.confidence >= 85
    }
    
    func getCompositeConfidence(binance: Signal?, ig: Signal?) -> Double {
        guard let b = binance, let i = ig else {
            return binance?.confidence ?? ig?.confidence ?? 0
        }
        
        if b.type == i.type {
            // Both agree - boost confidence
            return min((b.confidence + i.confidence) / 2 + 10, 100)
        } else {
            // Disagree - reduce confidence
            return min(b.confidence, i.confidence) * 0.8
        }
    }
}
