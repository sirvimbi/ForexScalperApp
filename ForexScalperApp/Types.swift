// Types.swift
import Foundation
import SwiftUI

// MARK: - Signal Types
enum SignalType: String, Codable, Sendable, CaseIterable {
    case buy, sell, none
    
    var displayName: String {
        switch self {
        case .buy: return "BUY"
        case .sell: return "SELL"
        case .none: return "NONE"
        }
    }
    
    var color: Color {
        switch self {
        case .buy: return .green
        case .sell: return .red
        case .none: return .gray
        }
    }
}

// MARK: - Signal Source
enum SignalSource: String, Codable, Sendable, CaseIterable {
    case auto = "AUTO"
    case binance = "BINANCE"
    case ig = "IG"
    case both = "BOTH"
    
    var displayName: String {
        switch self {
        case .auto: return "AUTO"
        case .binance: return "BINANCE"
        case .ig: return "IG"
        case .both: return "BOTH"
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "bolt.horizontal.circle.fill"
        case .binance: return "bitcoinsign.circle.fill"
        case .ig: return "network"
        case .both: return "link.circle.fill"
        }
    }
}

// MARK: - Signal Status
enum SignalStatus: String, Codable {
    case pending
    case accepted
    case denied
    case expired
    case completed
}

// MARK: - Signal struct with Codable conformance
struct Signal: Identifiable, Sendable, Codable {
    let id: UUID
    let type: SignalType
    let symbol: String
    let price: Double
    let confidence: Double
    let timestamp: Date
    let timeframe: String
    var expiryTime: Date
    var status: SignalStatus
    var acceptedAt: Date?
    var acceptedPrice: Double?
    var closedAt: Date?
    var closedPrice: Double?
    var pnl: Double?
    var pnlPercent: Double?
    var positionSize: Double?
    var stopLoss: Double?
    var takeProfit: Double?
    var source: SignalSource
    var volume: Double
    var tradeId: UUID?
    var externalDealId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case symbol
        case price
        case confidence
        case timestamp
        case timeframe
        case expiryTime
        case status
        case acceptedAt
        case acceptedPrice
        case closedAt
        case closedPrice
        case pnl
        case pnlPercent
        case positionSize
        case stopLoss
        case takeProfit
        case source
        case volume
        case tradeId
        case externalDealId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(SignalType.self, forKey: .type)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.price = try container.decode(Double.self, forKey: .price)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.timeframe = try container.decode(String.self, forKey: .timeframe)
        self.expiryTime = try container.decode(Date.self, forKey: .expiryTime)
        self.status = try container.decode(SignalStatus.self, forKey: .status)
        self.acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt)
        self.acceptedPrice = try container.decodeIfPresent(Double.self, forKey: .acceptedPrice)
        self.closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        self.closedPrice = try container.decodeIfPresent(Double.self, forKey: .closedPrice)
        self.pnl = try container.decodeIfPresent(Double.self, forKey: .pnl)
        self.pnlPercent = try container.decodeIfPresent(Double.self, forKey: .pnlPercent)
        self.positionSize = try container.decodeIfPresent(Double.self, forKey: .positionSize)
        self.stopLoss = try container.decodeIfPresent(Double.self, forKey: .stopLoss)
        self.takeProfit = try container.decodeIfPresent(Double.self, forKey: .takeProfit)
        let sourceRawValue = try container.decode(String.self, forKey: .source)
        self.source = SignalSource(rawValue: sourceRawValue) ?? .binance
        self.volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0
        self.tradeId = try container.decodeIfPresent(UUID.self, forKey: .tradeId)
        self.externalDealId = try container.decodeIfPresent(String.self, forKey: .externalDealId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(price, forKey: .price)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(timeframe, forKey: .timeframe)
        try container.encode(expiryTime, forKey: .expiryTime)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(acceptedAt, forKey: .acceptedAt)
        try container.encodeIfPresent(acceptedPrice, forKey: .acceptedPrice)
        try container.encodeIfPresent(closedAt, forKey: .closedAt)
        try container.encodeIfPresent(closedPrice, forKey: .closedPrice)
        try container.encodeIfPresent(pnl, forKey: .pnl)
        try container.encodeIfPresent(pnlPercent, forKey: .pnlPercent)
        try container.encodeIfPresent(positionSize, forKey: .positionSize)
        try container.encodeIfPresent(stopLoss, forKey: .stopLoss)
        try container.encodeIfPresent(takeProfit, forKey: .takeProfit)
        try container.encode(source.rawValue, forKey: .source)
        try container.encode(volume, forKey: .volume)
        try container.encodeIfPresent(tradeId, forKey: .tradeId)
        try container.encodeIfPresent(externalDealId, forKey: .externalDealId)
    }
    
    init(id: UUID = UUID(),
         type: SignalType,
         symbol: String,
         price: Double,
         confidence: Double,
         timestamp: Date,
         timeframe: String,
         expiryTime: Date,
         status: SignalStatus = .pending,
         acceptedAt: Date? = nil,
         acceptedPrice: Double? = nil,
         closedAt: Date? = nil,
         closedPrice: Double? = nil,
         pnl: Double? = nil,
         pnlPercent: Double? = nil,
         positionSize: Double? = nil,
         stopLoss: Double? = nil,
         takeProfit: Double? = nil,
         source: SignalSource = .binance,
         volume: Double = 0,
         tradeId: UUID? = nil,
         externalDealId: String? = nil) {
        self.id = id
        self.type = type
        self.symbol = symbol
        self.price = price
        self.confidence = confidence
        self.timestamp = timestamp
        self.timeframe = timeframe
        self.expiryTime = expiryTime
        self.status = status
        self.acceptedAt = acceptedAt
        self.acceptedPrice = acceptedPrice
        self.closedAt = closedAt
        self.closedPrice = closedPrice
        self.pnl = pnl
        self.pnlPercent = pnlPercent
        self.positionSize = positionSize
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.source = source
        self.volume = volume
        self.tradeId = tradeId
        self.externalDealId = externalDealId
    }
    
    var isActive: Bool {
        status == .pending || status == .accepted
    }
    
    var timeRemaining: TimeInterval {
        max(0, expiryTime.timeIntervalSinceNow)
    }
}

// MARK: - Signal Extension for Expiry
extension Signal {
    var expiryDuration: TimeInterval {
        switch timeframe {
        case "1m": return 180 // 3 minutes
        case "5m": return 900 // 15 minutes
        case "15m": return 2700 // 45 minutes
        case "1h": return 10800 // 3 hours
        default: return 300 // 5 minutes default
        }
    }
    
    var isExpiringSoon: Bool {
        timeRemaining < 60
    }
    
    var progressPercentage: Double {
        let total = expiryDuration
        let elapsed = total - timeRemaining
        return min(max(elapsed / total, 0), 1)
    }
}

// MARK: - Kline
struct Kline: Sendable, Codable {
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let closeTime: Int
}

// MARK: - Trade Record
struct TradeRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let signalId: UUID
    let symbol: String
    let type: SignalType
    let entryPrice: Double
    let entryTime: Date
    var exitPrice: Double?
    var exitTime: Date?
    let confidence: Double
    let takeProfit: Double?
    let stopLoss: Double?
    let positionSize: Double?
    var pnl: Double?
    var pnlPercent: Double?
    var status: TradeStatus
    var externalDealId: String?
    
    enum TradeStatus: String, Codable {
        case active
        case completed
        case stopped
        case expired
    }
    
    init(id: UUID = UUID(),
         signalId: UUID,
         symbol: String,
         type: SignalType,
         entryPrice: Double,
         entryTime: Date,
         exitPrice: Double? = nil,
         exitTime: Date? = nil,
         confidence: Double,
         takeProfit: Double? = nil,
         stopLoss: Double? = nil,
         positionSize: Double? = nil,
         pnl: Double? = nil,
         pnlPercent: Double? = nil,
         status: TradeStatus = .active,
         externalDealId: String? = nil) {
        self.id = id
        self.signalId = signalId
        self.symbol = symbol
        self.type = type
        self.entryPrice = entryPrice
        self.entryTime = entryTime
        self.exitPrice = exitPrice
        self.exitTime = exitTime
        self.confidence = confidence
        self.takeProfit = takeProfit
        self.stopLoss = stopLoss
        self.positionSize = positionSize
        self.pnl = pnl
        self.pnlPercent = pnlPercent
        self.status = status
        self.externalDealId = externalDealId
    }
    
    var isActive: Bool { status == .active }
    var isWin: Bool? {
        guard let pnl = pnl else { return nil }
        return pnl > 0
    }
}

// MARK: - Trading Pair Enum for better type safety
enum TradingPair: String, CaseIterable {
    // Existing
    case eurusdt = "EURUSDT"
    case gbpusdt = "GBPUSDT"
    case audusdt = "AUDUSDT"
    case btcusdt = "BTCUSDT"
    case ethusdt = "ETHUSDT"
    
    // New Forex
    case eurusd = "EURUSD"
    case gbpusd = "GBPUSD"
    case usdjpy = "USDJPY"
    case usdchf = "USDCHF"
    case cadchf = "CADCHF"
    case tryjpy = "TRYJPY"
    case eurczk = "EURCZK"
    
    // New Crypto
    case xrpusdt = "XRPUSDT"
    case adausdt = "ADAUSDT"
    case dogeusdt = "DOGEUSDT"
    case ltcusdt = "LTCUSDT"
    case bchusdt = "BCHUSDT"
    case eosusdt = "EOSUSDT"
    case xlmusdt = "XLMUSDT"
    case neousdt = "NEOUSDT"
    case btgusdt = "BTGUSDT"
    
    var displayName: String {
        switch self {
        case .eurusdt: return "EUR/USDT"
        case .gbpusdt: return "GBP/USDT"
        case .audusdt: return "AUD/USDT"
        case .btcusdt: return "BTC/USDT"
        case .ethusdt: return "ETH/USDT"
        case .eurusd: return "EUR/USD"
        case .gbpusd: return "GBP/USD"
        case .usdjpy: return "USD/JPY"
        case .usdchf: return "USD/CHF"
        case .cadchf: return "CAD/CHF"
        case .tryjpy: return "TRY/JPY"
        case .eurczk: return "EUR/CZK"
        case .xrpusdt: return "XRP/USDT"
        case .adausdt: return "ADA/USDT"
        case .dogeusdt: return "DOGE/USDT"
        case .ltcusdt: return "LTC/USDT"
        case .bchusdt: return "BCH/USDT"
        case .eosusdt: return "EOS/USDT"
        case .xlmusdt: return "XLM/USDT"
        case .neousdt: return "NEO/USDT"
        case .btgusdt: return "BTG/USDT"
        }
    }
    
    var category: String {
        switch self {
        case .eurusdt, .gbpusdt, .audusdt:
            return "Forex"
        case .eurusd, .gbpusd, .usdjpy, .usdchf, .cadchf, .tryjpy, .eurczk:
            return "Forex"
        case .btcusdt, .ethusdt, .xrpusdt, .adausdt, .dogeusdt, .ltcusdt, .bchusdt, .eosusdt, .xlmusdt, .neousdt, .btgusdt:
            return "Crypto"
        }
    }
}

// MARK: - Time Filter
enum TimeFilter: String, CaseIterable {
    case oneHour = "1h"
    case sixHours = "6h"
    case twelveHours = "12h"
    case twentyFourHours = "24h"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case allTime = "All"
    
    var hours: TimeInterval? {
        switch self {
        case .oneHour: return 1
        case .sixHours: return 6
        case .twelveHours: return 12
        case .twentyFourHours: return 24
        case .oneWeek: return 24 * 7
        case .oneMonth: return 24 * 30
        case .allTime: return nil
        }
    }
}

// MARK: - Risk Management
struct RiskParameters {
    let accountBalance: Double
    let riskPerTrade: Double
    let maxDailyRisk: Double
    let maxConcurrentTrades: Int
}

struct PositionSize {
    let units: Double
    let stopLoss: Double
    let takeProfit: Double
    let riskAmount: Double
    let potentialReward: Double
}

// MARK: - Trade Stats
struct TradeStats {
    let totalTrades: Int
    let activeTrades: Int
    let closedTrades: Int
    let wins: Int
    let losses: Int
    let winRate: Double
    let totalPnL: Double
    let averageWin: Double
    let averageLoss: Double
    let profitFactor: Double
    let symbolPerformance: [String: (trades: Int, wins: Int, pnl: Double)]
    let confidencePerformance: [(range: String, trades: Int, wins: Int, winRate: Double)]
}

// MARK: - Backtest Result
struct BacktestResultData {
    let symbol: String
    let totalTrades: Int
    let wins: Int
    let losses: Int
    let winRate: Double
    let totalPnL: Double
    let maxDrawdown: Double
    let sharpeRatio: Double
    let profitFactor: Double
    
    var avgWin: Double = 0
    var avgLoss: Double = 0
    var startBalance: Double = 10000
    var endBalance: Double = 0
    var equityCurve: [Double] = []
    var sampleTrades: [BacktestTrade] = []
    var netPnL: Double { totalPnL }
}

struct BacktestTrade {
    let symbol: String
    let direction: String
    let entryPrice: Double
    let exitPrice: Double
    let pnl: Double
}

// MARK: - IG Types for API Integration
struct IGAccountInfo: Codable {
    let accountId: String
    let accountName: String
    let balance: Double
    let deposit: Double
    let profitLoss: Double
    let available: Double
    let currency: String
}

struct IGPosition: Codable {
    let dealId: String
    let epic: String
    let marketName: String
    let direction: String
    let size: Double
    let level: Double
    let limitLevel: Double?
    let stopLevel: Double?
    let createdDate: String
    let currency: String
    let profitLoss: Double?
}

struct IGMarketSnapshot: Codable {
    let symbol: String
    let epic: String
    let bid: Double
    let offer: Double
    let high: Double
    let low: Double
    let change: Double
    let changePct: Double
    let volume: Double
    let updateTime: String
    let marketStatus: String
}

struct IGCandle: Codable {
    let openTime: String
    let openPrice: Double
    let highPrice: Double
    let lowPrice: Double
    let closePrice: Double
    let lastTradedVolume: Double
}

// MARK: - API Response Wrapper
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
    let message: String?
}

// MARK: - Notification Names
extension Notification.Name {
    static let acceptSignal = Notification.Name("acceptSignal")
    static let denySignal = Notification.Name("denySignal")
    static let showSignalDashboard = Notification.Name("showSignalDashboard")
    static let tradeHistoryUpdated = Notification.Name("tradeHistoryUpdated")
    static let tradeUpdated = Notification.Name("tradeUpdated")
    static let igAccountUpdated = Notification.Name("igAccountUpdated")
    static let igTradeExecuted = Notification.Name("igTradeExecuted")
    static let signalSourceChanged = Notification.Name("signalSourceChanged")
    static let sourceMetricsUpdated = Notification.Name("sourceMetricsUpdated")
}
