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
    case mt5 = "MT5"
    case both = "BOTH"
    
    var displayName: String {
        switch self {
        case .auto: return "AUTO"
        case .binance: return "BINANCE"
        case .ig: return "IG"
        case .mt5: return "MT5"
        case .both: return "BOTH"
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "bolt.horizontal.circle.fill"
        case .binance: return "bitcoinsign.circle.fill"
        case .ig: return "network"
        case .mt5: return "chart.bar.fill"
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

// MARK: - MT5 Execution Types
enum MT5OrderType: String, Codable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
    case buyLimit = "BUY_LIMIT"
    case sellLimit = "SELL_LIMIT"
    case buyStop = "BUY_STOP"
    case sellStop = "SELL_STOP"
    case buyStopLimit = "BUY_STOP_LIMIT"
    case sellStopLimit = "SELL_STOP_LIMIT"
}

enum MT5FillingType: String, Codable, Sendable {
    case fok = "FOK"
    case ioc = "IOC"
    case any = "RETURN"
}

enum MT5ExecutionMode: String, Codable, Sendable {
    case request = "REQUEST"
    case instant = "INSTANT"
    case market = "MARKET"
    case exchange = "EXCHANGE"
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
    
    // MT5 Specific fields for "God Mode"
    var magicNumber: Int?
    var comment: String?
    var deviation: Int?
    var filler: MT5FillingType?
    var orderType: MT5OrderType?
    var executionMode: MT5ExecutionMode?

    private enum CodingKeys: String, CodingKey {
        case id, type, symbol, price, confidence, timestamp, timeframe, expiryTime, status, acceptedAt, acceptedPrice, closedAt, closedPrice, pnl, pnlPercent, positionSize, stopLoss, takeProfit, source, volume, tradeId, externalDealId
        case magicNumber, comment, deviation, filler, orderType, executionMode
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
        
        // MT5
        self.magicNumber = try container.decodeIfPresent(Int.self, forKey: .magicNumber)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        self.deviation = try container.decodeIfPresent(Int.self, forKey: .deviation)
        self.filler = try container.decodeIfPresent(MT5FillingType.self, forKey: .filler)
        self.orderType = try container.decodeIfPresent(MT5OrderType.self, forKey: .orderType)
        self.executionMode = try container.decodeIfPresent(MT5ExecutionMode.self, forKey: .executionMode)
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
        
        // MT5
        try container.encodeIfPresent(magicNumber, forKey: .magicNumber)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(deviation, forKey: .deviation)
        try container.encodeIfPresent(filler, forKey: .filler)
        try container.encodeIfPresent(orderType, forKey: .orderType)
        try container.encodeIfPresent(executionMode, forKey: .executionMode)
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
         externalDealId: String? = nil,
         magicNumber: Int? = nil,
         comment: String? = nil,
         deviation: Int? = nil,
         filler: MT5FillingType? = .ioc,
         orderType: MT5OrderType? = nil,
         executionMode: MT5ExecutionMode? = .market) {
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
        self.magicNumber = magicNumber
        self.comment = comment
        self.deviation = deviation
        self.filler = filler
        self.orderType = orderType ?? (type == .buy ? .buy : .sell)
        self.executionMode = executionMode
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
    // Forex Majors
    case eurusd = "EURUSD"
    case gbpusd = "GBPUSD"
    case usdjpy = "USDJPY"
    case usdchf = "USDCHF"
    case audusd = "AUDUSD"
    case usdcad = "USDCAD"
    case nzdusd = "NZDUSD"
    
    // Forex Minors/Crosses
    case eurgbp = "EURGBP"
    case eurjpy = "EURJPY"
    case gbpjpy = "GBPJPY"
    case audjpy = "AUDJPY"
    case cadjpy = "CADJPY"
    case chfjpy = "CHFJPY"
    case euraud = "EURAUD"
    case eurcad = "EURCAD"
    case gbpaud = "GBPAUD"
    case audcad = "AUDCAD"
    
    // Forex Exotics
    case usdmxn = "USDMXN"
    case usdzar = "USDZAR"
    case usdtry = "USDTRY"
    case usdhkd = "USDHKD"
    case usdsgd = "USDSGD"
    case usdnok = "USDNOK"
    case usdsek = "USDSEK"
    case usddkk = "USDDKK"
    case usdpln = "USDPLN"
    case usdcnh = "USDCNH"
    case eurczk = "EURCZK"
    case eurhuf = "EURHUF"
    case eurpln = "EURPLN"
    case eurtry = "EURTRY"
    
    // Crypto
    case btcusdt = "BTCUSDT"
    case ethusdt = "ETHUSDT"
    case xrpusdt = "XRPUSDT"
    case adausdt = "ADAUSDT"
    case solusdt = "SOLUSDT"
    case dotusdt = "DOTUSDT"
    case dogeusdt = "DOGEUSDT"
    case avaxusdt = "AVAXUSDT"
    case linkusdt = "LINKUSDT"
    case ltcusdt = "LTCUSDT"
    
    var displayName: String {
        switch self {
        case .eurusd: return "EUR/USD"
        case .gbpusd: return "GBP/USD"
        case .usdjpy: return "USD/JPY"
        case .usdchf: return "USD/CHF"
        case .audusd: return "AUD/USD"
        case .usdcad: return "USD/CAD"
        case .nzdusd: return "NZD/USD"
        case .eurgbp: return "EUR/GBP"
        case .eurjpy: return "EUR/JPY"
        case .gbpjpy: return "GBP/JPY"
        case .audjpy: return "AUD/JPY"
        case .cadjpy: return "CAD/JPY"
        case .chfjpy: return "CHF/JPY"
        case .euraud: return "EUR/AUD"
        case .eurcad: return "EUR/CAD"
        case .gbpaud: return "GBP/AUD"
        case .audcad: return "AUD/CAD"
        case .usdmxn: return "USD/MXN"
        case .usdzar: return "USD/ZAR"
        case .usdtry: return "USD/TRY"
        case .usdhkd: return "USD/HKD"
        case .usdsgd: return "USD/SGD"
        case .usdnok: return "USD/NOK"
        case .usdsek: return "USD/SEK"
        case .usddkk: return "USD/DKK"
        case .usdpln: return "USD/PLN"
        case .usdcnh: return "USD/CNH"
        case .eurczk: return "EUR/CZK"
        case .eurhuf: return "EUR/HUF"
        case .eurpln: return "EUR/PLN"
        case .eurtry: return "EUR/TRY"
        case .btcusdt: return "BTC/USDT"
        case .ethusdt: return "ETH/USDT"
        case .xrpusdt: return "XRP/USDT"
        case .adausdt: return "ADA/USDT"
        case .solusdt: return "SOL/USDT"
        case .dotusdt: return "DOT/USDT"
        case .dogeusdt: return "DOGE/USDT"
        case .avaxusdt: return "AVAX/USDT"
        case .linkusdt: return "LINK/USDT"
        case .ltcusdt: return "LTC/USDT"
        }
    }
    
    var category: String {
        switch self {
        case .eurusd, .gbpusd, .usdjpy, .usdchf, .audusd, .usdcad, .nzdusd,
             .eurgbp, .eurjpy, .gbpjpy, .audjpy, .cadjpy, .chfjpy, .euraud, .eurcad, .gbpaud, .audcad,
             .usdmxn, .usdzar, .usdtry, .usdhkd, .usdsgd, .usdnok, .usdsek, .usddkk, .usdpln, .usdcnh,
             .eurczk, .eurhuf, .eurpln, .eurtry:
            return "Forex"
        case .btcusdt, .ethusdt, .xrpusdt, .adausdt, .solusdt, .dotusdt, .dogeusdt, .avaxusdt, .linkusdt, .ltcusdt:
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

// MARK: - MT5 Types
struct MT5AccountInfo: Codable {
    let login: Int
    let balance: Double
    let equity: Double
    let margin: Double
    let marginFree: Double
    let profit: Double
    let currency: String
    let server: String
}

struct MT5Position: Codable {
    let ticket: Int
    let symbol: String
    let type: String
    let volume: Double
    let priceOpen: Double
    let sl: Double
    let tp: Double
    let priceCurrent: Double
    let profit: Double
    let magic: Int?
    let comment: String?
}

struct MT5TradeResult: Codable {
    let retcode: Int
    let order: Int?
    let deal: Int?
    let volume: Double
    let price: Double
    let bid: Double
    let ask: Double
    let comment: String?
    let request_id: Int?
    let retcode_external: Int?
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
    static let mt5AccountUpdated = Notification.Name("mt5AccountUpdated")
    static let mt5TradeExecuted = Notification.Name("mt5TradeExecuted")
    static let signalSourceChanged = Notification.Name("signalSourceChanged")
    static let sourceMetricsUpdated = Notification.Name("sourceMetricsUpdated")
}
