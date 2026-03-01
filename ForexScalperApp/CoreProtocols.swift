// MARK: - Core Protocols
import Foundation

protocol SignalGenerator: Sendable {
    func generateSignal(for symbol: String, marketData: MarketDataProvider) async -> Signal?
}

protocol RiskManagerProtocol: Sendable {
    func canOpenTrade(for symbol: String) async -> Bool
    func calculatePositionSize(for signal: Signal) async -> PositionSize?
    func registerTrade(_ trade: TradeRecord) async
    func closeTrade(_ trade: TradeRecord) async
}

protocol MarketDataProvider: Sendable {
    func getCandles(symbol: String, timeframe: String) async -> [Kline]
    func getLatestPrice(symbol: String) async -> Double?
}

// Namespaced to avoid duplicate symbols across modules/files
enum Core {
    enum MarketRegime: String, Sendable {
        case strongUptrend
        case strongDowntrend
        case ranging
        case volatile
        case quiet
    }

    protocol RegimeDetector: Sendable {
        func currentRegime(symbol: String) async -> MarketRegime
    }
}
