// MARK: - Fixed TradeHistoryManager with Proper Concurrency
import Foundation
import SwiftUI

actor RefactoredTradeHistoryManager {
    static let shared = RefactoredTradeHistoryManager()
    private var trades: [UUID: TradeRecord] = [:] // Use dictionary for O(1) access
    private let savePath: URL
    
    private init() {
        savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trade_history.json")
        
        // Inline load logic to avoid isolation warnings in init
        do {
            let data = try Data(contentsOf: savePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedTrades = try decoder.decode([TradeRecord].self, from: data)
            self.trades = Dictionary(uniqueKeysWithValues: loadedTrades.map { ($0.id, $0) })
            print("📊 Trade history: Loaded \(self.trades.count) trades")
        } catch {
            print("📝 No existing trade history")
        }
    }
    
    func addTrade(_ trade: TradeRecord) {
        trades[trade.id] = trade
        saveTrades()
        notifyUpdate()
        notifyTradeUpdate()
        print("📊 Trade history: Added trade for \(trade.symbol) (Status: \(trade.status))")
    }
    
    func updateTrade(_ trade: TradeRecord) {
        trades[trade.id] = trade
        saveTrades()
        notifyUpdate()
        notifyTradeUpdate()
        
        print("📊 Trade history: Updated trade for \(trade.symbol) (Status: \(trade.status))")
        
        // If trade is completed, post specific notification with the trade object
        if trade.status == .completed {
            Task { @MainActor in
                NotificationCenter.default.post(name: Notification.Name.tradeUpdated, object: trade)
                print("📢 Posted trade completed notification for \(trade.symbol)")
            }
        }
    }
    
    func getTrade(id: UUID) -> TradeRecord? {
        return trades[id]
    }
    
    func getTradeByExternalId(_ externalId: String) -> TradeRecord? {
        return trades.values.first { $0.externalDealId == externalId }
    }
    
    func getAllTrades() -> [TradeRecord] {
        return Array(trades.values)
    }
    
    func getActiveTrades() -> [TradeRecord] {
        return trades.values.filter { $0.status == .active }.sorted { $0.entryTime > $1.entryTime }
    }
    
    func getCompletedTrades(filter: DashboardTimeFilter? = nil) -> [TradeRecord] {
        var filtered = trades.values.filter { $0.status == .completed }
        
        if let filter = filter {
            let cutoffDate: Date?
            switch filter {
            case .today:
                cutoffDate = Calendar.current.startOfDay(for: Date())
            case .yesterday:
                cutoffDate = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
            case .last7Days:
                cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .thisMonth:
                cutoffDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
            case .allTime:
                cutoffDate = nil
            }
            
            if let cutoffDate = cutoffDate {
                filtered = filtered.filter { $0.entryTime >= cutoffDate }
            }
        }
        
        return filtered.sorted { $0.entryTime > $1.entryTime }
    }
    
    func notifyTradeUpdate() {
        Task { @MainActor in
            NotificationCenter.default.post(name: Notification.Name.tradeUpdated, object: nil)
            print("📢 Posted trade update notification")
        }
    }
    
    func getSymbolPerformance(symbol: String, days: Int) async -> SymbolPerformance {
        let cutoffDate = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let relevantTrades = trades.values.filter {
            $0.symbol == symbol &&
            $0.entryTime >= cutoffDate &&
            $0.status == .completed
        }
        
        let wins = relevantTrades.filter { $0.pnl ?? 0 > 0 }.count
        let totalPnL = relevantTrades.compactMap { $0.pnl }.reduce(0, +)
        
        return SymbolPerformance(
            symbol: symbol,
            totalTrades: relevantTrades.count,
            wins: wins,
            winRate: relevantTrades.isEmpty ? 0 : Double(wins) / Double(relevantTrades.count) * 100,
            totalPnL: totalPnL
        )
    }
    
    func clearHistory(keepActive: Bool) async {
        if keepActive {
            let active = trades.values.filter { $0.status == .active }
            trades = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        } else {
            trades.removeAll()
        }
        saveTrades()
        notifyUpdate()
    }
    
    func clearAllHistory() async {
        trades.removeAll()
        saveTrades()
        notifyUpdate()
    }
    
    // MARK: - CSV Export
    
    func generateCSV() async -> String {
        // Run on a background thread to prevent UI freezing
        return await Task.detached(priority: .userInitiated) {
            let sortedTrades = self.trades.values.sorted { $0.entryTime > $1.entryTime }
            
            let header = "Symbol,Type,Signal Generated,Time Filled,Accepted,Volume/Lot,Open Price,Exit Price,T/P,S/L,Swap (KES),P/L (KES),Result\n"
            
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            var csvRows: [String] = []
            csvRows.reserveCapacity(sortedTrades.count)
            
            for (index, trade) in sortedTrades.enumerated() {
                // Yield occasionally to keep system responsive if the list is massive
                if index % 500 == 0 {
                    await Task.yield()
                }
                
                let signalTimeStr = df.string(from: trade.signalTime ?? trade.entryTime)
                let filledTimeStr = df.string(from: trade.entryTime)
                
                let pnlValue = trade.pnl ?? 0
                let result: String
                if trade.status == .active || trade.status == .pending {
                    result = trade.status.rawValue.uppercased()
                } else {
                    result = pnlValue > 0 ? "WIN" : (pnlValue < 0 ? "LOSS" : "BREAKEVEN")
                }
                
                let volumeStr = String(format: "%.2f", trade.positionSize ?? 0)
                
                let row = [
                    trade.symbol,
                    trade.type.displayName,
                    signalTimeStr,
                    filledTimeStr,
                    trade.isAccepted ? "YES" : "NO",
                    volumeStr,
                    String(format: "%.5f", trade.entryPrice),
                    String(format: "%.5f", trade.exitPrice ?? 0),
                    String(format: "%.5f", trade.takeProfit ?? 0),
                    String(format: "%.5f", trade.stopLoss ?? 0),
                    String(format: "%.2f", trade.swap ?? 0),
                    String(format: "%.2f", pnlValue),
                    result
                ].joined(separator: ",")
                
                csvRows.append(row)
            }
            
            return header + csvRows.joined(separator: "\n")
        }.value
    }
    
    // MARK: - Private methods
    
    private func saveTrades() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(trades.values))
            try data.write(to: savePath)
            print("📊 Trade history: Saved \(trades.count) trades")
        } catch {
            print("❌ Failed to save trades: \(error)")
        }
    }
    
    private func loadTrades() {
        do {
            let data = try Data(contentsOf: savePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedTrades = try decoder.decode([TradeRecord].self, from: data)
            trades = Dictionary(uniqueKeysWithValues: loadedTrades.map { ($0.id, $0) })
            print("📊 Trade history: Loaded \(trades.count) trades")
        } catch {
            print("📝 No existing trade history")
        }
    }
    
    private func notifyUpdate() {
        Task { @MainActor in
            NotificationCenter.default.post(name: Notification.Name.tradeHistoryUpdated, object: nil)
            print("📢 Posted trade history update notification")
        }
    }
}
