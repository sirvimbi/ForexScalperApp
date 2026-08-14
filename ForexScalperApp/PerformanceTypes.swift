// PerformanceTypes.swift
// MARK: - Performance Types
import Foundation

struct SymbolPerformance {
    let symbol: String
    let totalTrades: Int
    let wins: Int
    let winRate: Double
    let totalPnL: Double
}

// MARK: - Array extension for batching - REMOVED (moved to BinanceService.swift)
// extension Array {
//     func chunked(into size: Int) -> [[Element]] {
//         return stride(from: 0, to: count, by: size).map {
//             Array(self[$0 ..< Swift.min($0 + size, count)])
//         }
//     }
// }