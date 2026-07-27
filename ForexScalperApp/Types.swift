// Types.swift
import Foundation
import SwiftUI

import UniformTypeIdentifiers

// MARK: - CSV Document for Export
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Log Document for Export
struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Signal Types
enum SignalType: String, Codable, Sendable, CaseIterable {
    case buy, sell, none
    
    nonisolated var displayName: String {
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

// MARK: - News Models
enum NewsImpact: String, Codable, Sendable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case none = "None"
    
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .none: return .gray
        }
    }
}

struct NewsEvent: Identifiable, Codable, Sendable {
    var id: String { "\(title)_\(time.timeIntervalSince1970)" }
    let title: String
    let currency: String
    let impact: NewsImpact
    let time: Date
    let actual: String?
    let forecast: String?
    let previous: String?
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

// MARK: - Signal struct
struct Signal: Identifiable, Sendable, Codable {
    let id: UUID
    let type: SignalType
    var symbol: String
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
        
        try container.encodeIfPresent(magicNumber, forKey: .magicNumber)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(deviation, forKey: .deviation)
        try container.encodeIfPresent(filler, forKey: .filler)
        try container.encodeIfPresent(orderType, forKey: .orderType)
        try container.encodeIfPresent(executionMode, forKey: .executionMode)
    }
    
    nonisolated init(id: UUID = UUID(),
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

// MARK: - Signal Extension
extension Signal {
    var expiryDuration: TimeInterval {
        switch timeframe {
        case "1m": return 180 
        case "5m": return 900 
        case "15m": return 2700 
        case "1h": return 10800 
        default: return 300 
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
    let spread: Double?
}

// MARK: - Trade Record
struct TradeRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let signalId: UUID
    var symbol: String
    let type: SignalType
    let entryPrice: Double
    let entryTime: Date
    var exitPrice: Double?
    var exitTime: Date?
    let confidence: Double
    var takeProfit: Double?
    var stopLoss: Double?
    let positionSize: Double?
    var pnl: Double?
    var pnlPercent: Double?
    var status: TradeStatus
    var externalDealId: String?
    
    // God Mode Enhanced Fields
    var swap: Double?
    var commission: Double?
    var signalTime: Date?
    var isAccepted: Bool = true
    
    enum TradeStatus: String, Codable {
        case active, completed, stopped, expired, pending
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
         externalDealId: String? = nil,
         swap: Double? = nil,
         commission: Double? = nil,
         signalTime: Date? = nil) {
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
        self.swap = swap
        self.commission = commission
        self.signalTime = signalTime ?? entryTime
    }
    
    var isActive: Bool { status == .active }
    var isWin: Bool? {
        guard let pnl = pnl else { return nil }
        return pnl > 0
    }
}

// MARK: - Trading Pair Enum (Strict Forex Only)
enum TradingPair: String, CaseIterable {
    // Majors
    case eurusd = "EURUSD", gbpusd = "GBPUSD", usdjpy = "USDJPY", usdchf = "USDCHF", audusd = "AUDUSD", usdcad = "USDCAD", nzdusd = "NZDUSD"
    // Minors
    case eurgbp = "EURGBP", eurjpy = "EURJPY", gbpjpy = "GBPJPY", audjpy = "AUDJPY", cadjpy = "CADJPY", chfjpy = "CHFJPY", euraud = "EURAUD", eurcad = "EURCAD", eurchf = "EURCHF", eurnzd = "EURNZD", gbpaud = "GBPAUD", gbpcad = "GBPCAD", gbpchf = "GBPCHF", gbpnzd = "GBPNZD", audcad = "AUDCAD", audchf = "AUDCHF", audnzd = "AUDNZD", cadchf = "CADCHF", nzdcad = "NZDCAD", nzdchf = "NZDCHF", nzdjpy = "NZDJPY"
    // Exotics
    case usdsek = "USDSEK", usdnok = "USDNOK", usdpln = "USDPLN", usdmxn = "USDMXN", usdzar = "USDZAR", usdhkd = "USDHKD", usdsgd = "USDSGD", usdtry = "USDTRY", usdils = "USDILS", usdcnh = "USDCNH", usdthb = "USDTHB", usddkk = "USDDKK", eursek = "EURSEK", eurnok = "EURNOK", eurpln = "EURPLN", eurmxn = "EURMXN", eurzar = "EURZAR", eurtry = "EURTRY", eurdkk = "EURDKK", eurhkd = "EURHKD", eurczk = "EURCZK", eurhuf = "EURHUF", gbptry = "GBPTRY"
    
    var displayName: String {
        return self.rawValue.prefix(3) + "/" + self.rawValue.suffix(3)
    }
    
    var category: String {
        return "Forex"
    }
    
    var isExotic: Bool {
        let exotics: Set<TradingPair> = [
            .usdsek, .usdnok, .usdpln, .usdmxn, .usdzar, .usdhkd, .usdsgd, .usdtry, .usdils, .usdcnh, .usdthb, .usddkk,
            .eursek, .eurnok, .eurpln, .eurmxn, .eurzar, .eurtry, .eurdkk, .eurhkd, .eurczk, .eurhuf, .gbptry
        ]
        return exotics.contains(self)
    }
}

// MARK: - Scalping Supporting Types
enum PricePattern: String, Codable, Sendable {
    case none
    case bullishEngulfing
    case bearishEngulfing
    case hammer
    case invertedHammer
    case morningStar
    case eveningStar
    case shootingStar
}

enum MarketRegime: String, Codable, Sendable {
    case trending
    case ranging
    case volatile
}

struct IndicatorSet: Sendable {
    let rsi: Double
    let stochasticK: Double
    let stochasticD: Double
    let cci: Double
    let sar: Double
    let atr: Double
    let spread: Double?
    let ema9: Double
    let ema21: Double
    let ema50: Double
    let ema9_5m: Double
    let ema21_5m: Double
    let ema50_5m: Double
    let bbPosition: Double
    let volumeRatio: Double
    let volumeProfilePOC: Double
    let support: Double
    let resistance: Double
    let sessions: (asiaRange: (high: Double, low: Double),
                   londonRange: (high: Double, low: Double),
                   usRange: (high: Double, low: Double))
    let trendStrength: Double
    let pricePattern: PricePattern
    let regime: MarketRegime
    let currentPrice: Double
    let h4Trend: SignalType
    let d1Trend: SignalType
    let w1Trend: SignalType
}

struct ScalpingSignal: Sendable {
    var type: SignalType
    var symbol: String
    var price: Double
    var confidence: Double
    var score: Int
    var sellScore: Int
    var indicators: IndicatorSet
    var confidenceFactors: [String: Double]
    var timestamp: Date
    
    // God Mode Fields
    var stopLoss: Double?
    var takeProfit: Double?
    var volume: Double?
    var orderType: MT5OrderType?
    var fillingType: MT5FillingType?
    var executionMode: MT5ExecutionMode?
    
    func withConfidence(_ newConfidence: Double) -> ScalpingSignal {
        ScalpingSignal(
            type: type,
            symbol: symbol,
            price: price,
            confidence: newConfidence,
            score: score,
            sellScore: sellScore,
            indicators: indicators,
            confidenceFactors: confidenceFactors,
            timestamp: timestamp,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            volume: volume,
            orderType: orderType,
            fillingType: fillingType,
            executionMode: executionMode
        )
    }
}

struct SignalQuality: Sendable {
    let type: SignalType
    let confidence: Double
    let timestamp: Date
    var wasWin: Bool?
}

// MARK: - Supporting Structs
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
}

// MARK: - Risk Metrics
struct RiskMetrics: Sendable {
    let dailyPnL: Double
    let dailyLossLimit: Double
    let hourlyTrades: Int
    let maxHourlyTrades: Int
    let activeTrades: Int
    let maxConcurrentTrades: Int
    let consecutiveLosses: [String: Int]
}

// MARK: - Extensions
extension Double {
    func rounded(to places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
// MARK: - Notifications
extension Notification.Name {
    static let newSignalGenerated = Notification.Name("newSignalGenerated")
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
    static let newLogEntry = Notification.Name("newLogEntry")
}
