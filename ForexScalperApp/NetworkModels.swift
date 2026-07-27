// NetworkModels.swift - THREAD-SAFE NON-ISOLATED MODELS
import Foundation

// MARK: - MT5 Models

struct MT5AccountInfo: Codable, Sendable {
    let login: Int
    let balance, equity, margin, margin_free, profit: Double
    let currency, server: String
    
    enum CodingKeys: String, CodingKey {
        case login, balance, equity, margin, margin_free, profit, currency, server
    }
}

struct MT5Position: Codable, Sendable {
    let ticket: Int64
    let symbol, type: String
    let volume, priceOpen, sl, tp, priceCurrent, profit: Double
    let magic: Int64?
    let comment: String?
    let openTime: Int64?
    
    enum CodingKeys: String, CodingKey {
        case ticket, symbol, type, volume, sl, tp, magic, comment, profit
        case priceOpen = "price_open", priceCurrent = "price_current", openTime = "open_time"
    }
}

struct MT5TradeResult: Codable, Sendable {
    let retcode: Int
    let order, deal: Int64?
    let volume, price, bid, ask: Double
    let comment: String?
}

struct MT5StatusResponse: Codable, Sendable {
    let connected: Bool
    let status: String?
    let message: String?
}

struct MT5PriceHistoryResponse: Codable, Sendable {
    let data: [MT5Candle]
}

struct MT5Candle: Codable, Sendable {
    let time: TimeInterval
    let open, high, low, close: Double
    let volume, tick_volume: Double?
    let spread: Int?
    let real_volume: Double?
    
    var totalVolume: Double {
        return volume ?? tick_volume ?? 0
    }
}

struct MT5OrderListResponse: Codable, Sendable {
    let opened: [MT5Position]
    let pending: [MT5Position]
}

struct MT5HistoryResponse: Codable, Sendable {
    let data: [MT5HistoryPosition]
}

struct MT5HistoryPosition: Codable, Sendable {
    let symbol: String
    let ticket: Int64
    let type: String
    let volume: Double
    let open_price, close_price: Double
    let open_time, close_time: Int64
    let profit, commission, swap: Double
    let comment: String?
    let magic: Int64?
}

struct MT5SymbolInfo: Codable, Sendable {
    let name: String
    let trade_mode: Int
    let spread: Int
    let digits: Int
    let volume_min: Double?
    let volume_max: Double?
    let volume_step: Double?
}

// MARK: - IG Models

struct IGAuthResponse: Codable, Sendable {
    let success: Bool
    let data: IGAuthData?
    let error: String?
}

struct IGAuthData: Codable, Sendable {
    let cst: String
    let xSecurityToken: String
    let accountId: String
    let lightstreamerEndpoint: String?
    let sessionId: String?
}

struct IGAPIResponse<T: Codable & Sendable>: Codable, Sendable {
    let success: Bool
    let data: T?
    let error: String?
}

struct AccountInfo: Codable, Sendable {
    let accountId: String
    let accountName: String
    let balance: Double
    let deposit: Double
    let profitLoss: Double
    let available: Double
    let currency: String
}

struct TradeResult: Codable, Sendable {
    let dealReference: String
    let dealId: String?
    let symbol: String
    let direction: String
    let size: Double
    let status: String?
    let timestamp: String?
}

struct Position: Codable, Sendable {
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

enum TradingError: Error, LocalizedError {
    case invalidURL
    case apiError(String)
    case decodingError
    case serverNotRunning
    case notAuthenticated
    case insufficientFunds
    case marketClosed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .apiError(let message):
            return "API Error: \(message)"
        case .decodingError:
            return "Failed to decode response"
        case .serverNotRunning:
            return "Backend server is not running at http://localhost:3000"
        case .notAuthenticated:
            return "Not authenticated. Please connect to IG first."
        case .insufficientFunds:
            return "Insufficient funds in account"
        case .marketClosed:
            return "Market is closed for this instrument"
        }
    }
}
