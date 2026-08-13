// NetworkModels.swift - THREAD-SAFE NON-ISOLATED MODELS
import Foundation

// MARK: - MT5 Models

struct MT5AccountInfo: Codable, Sendable {
    let login: Int
    let balance: Double
    let equity: Double
    let margin: Double
    let margin_free: Double
    let profit: Double
    let currency: String
    let server: String
    let algo_trading_enabled: Int?

    enum CodingKeys: String, CodingKey {
        case login, balance, equity, margin, margin_free, profit, currency, server, algo_trading_enabled
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.login = try container.decode(Int.self, forKey: .login)
        self.balance = try container.decode(Double.self, forKey: .balance)
        self.equity = try container.decode(Double.self, forKey: .equity)
        self.margin = try container.decode(Double.self, forKey: .margin)
        self.margin_free = try container.decode(Double.self, forKey: .margin_free)
        self.profit = try container.decode(Double.self, forKey: .profit)
        self.currency = try container.decode(String.self, forKey: .currency)
        self.server = try container.decode(String.self, forKey: .server)
        self.algo_trading_enabled = try container.decodeIfPresent(Int.self, forKey: .algo_trading_enabled)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(login, forKey: .login)
        try container.encode(balance, forKey: .balance)
        try container.encode(equity, forKey: .equity)
        try container.encode(margin, forKey: .margin)
        try container.encode(margin_free, forKey: .margin_free)
        try container.encode(profit, forKey: .profit)
        try container.encode(currency, forKey: .currency)
        try container.encode(server, forKey: .server)
        try container.encodeIfPresent(algo_trading_enabled, forKey: .algo_trading_enabled)
    }

    // Swift 6: explicit construction must be nonisolated because this model
    // is used from the MT5Service actor and from decoding/background contexts.
    nonisolated init(
        login: Int,
        balance: Double,
        equity: Double,
        margin: Double,
        margin_free: Double,
        profit: Double,
        currency: String,
        server: String,
        algo_trading_enabled: Int?
    ) {
        self.login = login
        self.balance = balance
        self.equity = equity
        self.margin = margin
        self.margin_free = margin_free
        self.profit = profit
        self.currency = currency
        self.server = server
        self.algo_trading_enabled = algo_trading_enabled
    }
}

struct MT5Position: Codable, Sendable {
    let ticket: Int64
    let symbol: String
    let type: String
    let volume: Double
    let priceOpen: Double
    let sl: Double
    let tp: Double
    let priceCurrent: Double
    let profit: Double
    let magic: Int64?
    let comment: String?
    let openTime: Int64?

    enum CodingKeys: String, CodingKey {
        case ticket, symbol, type, volume, sl, tp, magic, comment, profit
        case priceOpen = "price_open", priceCurrent = "price_current", openTime = "open_time"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ticket = try container.decode(Int64.self, forKey: .ticket)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.type = try container.decode(String.self, forKey: .type)
        self.volume = try container.decode(Double.self, forKey: .volume)
        self.priceOpen = try container.decode(Double.self, forKey: .priceOpen)
        self.sl = try container.decode(Double.self, forKey: .sl)
        self.tp = try container.decode(Double.self, forKey: .tp)
        self.priceCurrent = try container.decode(Double.self, forKey: .priceCurrent)
        self.profit = try container.decode(Double.self, forKey: .profit)
        self.magic = try container.decodeIfPresent(Int64.self, forKey: .magic)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        self.openTime = try container.decodeIfPresent(Int64.self, forKey: .openTime)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ticket, forKey: .ticket)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(type, forKey: .type)
        try container.encode(volume, forKey: .volume)
        try container.encode(priceOpen, forKey: .priceOpen)
        try container.encode(sl, forKey: .sl)
        try container.encode(tp, forKey: .tp)
        try container.encode(priceCurrent, forKey: .priceCurrent)
        try container.encode(profit, forKey: .profit)
        try container.encodeIfPresent(magic, forKey: .magic)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(openTime, forKey: .openTime)
    }

    // ✅ CUSTOM INITIALIZER - MUST BE NONISOLATED
    nonisolated init(
        ticket: Int64,
        symbol: String,
        type: String,
        volume: Double,
        priceOpen: Double,
        sl: Double,
        tp: Double,
        priceCurrent: Double,
        profit: Double,
        magic: Int64?,
        comment: String?,
        openTime: Int64?
    ) {
        self.ticket = ticket
        self.symbol = symbol
        self.type = type
        self.volume = volume
        self.priceOpen = priceOpen
        self.sl = sl
        self.tp = tp
        self.priceCurrent = priceCurrent
        self.profit = profit
        self.magic = magic
        self.comment = comment
        self.openTime = openTime
    }
}

struct MT5TradeResult: Codable, Sendable {
    let retcode: Int
    let order: Int64?
    let deal: Int64?
    let volume: Double
    let price: Double
    let bid: Double
    let ask: Double
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case retcode, order, deal, volume, price, bid, ask, comment
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.retcode = try container.decode(Int.self, forKey: .retcode)
        self.order = try container.decodeIfPresent(Int64.self, forKey: .order)
        self.deal = try container.decodeIfPresent(Int64.self, forKey: .deal)
        self.volume = try container.decode(Double.self, forKey: .volume)
        self.price = try container.decode(Double.self, forKey: .price)
        self.bid = try container.decode(Double.self, forKey: .bid)
        self.ask = try container.decode(Double.self, forKey: .ask)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(retcode, forKey: .retcode)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encodeIfPresent(deal, forKey: .deal)
        try container.encode(volume, forKey: .volume)
        try container.encode(price, forKey: .price)
        try container.encode(bid, forKey: .bid)
        try container.encode(ask, forKey: .ask)
        try container.encodeIfPresent(comment, forKey: .comment)
    }
}

struct MT5StatusResponse: Codable, Sendable {
    let connected: Bool
    let status: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case connected, status, message
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.connected = try container.decode(Bool.self, forKey: .connected)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connected, forKey: .connected)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

struct MT5PriceHistoryResponse: Codable, Sendable {
    let data: [MT5Candle]

    enum CodingKeys: String, CodingKey {
        case data
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([MT5Candle].self, forKey: .data)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }
}

struct MT5Candle: Codable, Sendable {
    let time: TimeInterval
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?
    let tick_volume: Double?
    let spread: Int?
    let real_volume: Double?

    nonisolated var totalVolume: Double {
        return volume ?? tick_volume ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case time, open, high, low, close, volume, tick_volume, spread, real_volume
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.time = try container.decode(TimeInterval.self, forKey: .time)
        self.open = try container.decode(Double.self, forKey: .open)
        self.high = try container.decode(Double.self, forKey: .high)
        self.low = try container.decode(Double.self, forKey: .low)
        self.close = try container.decode(Double.self, forKey: .close)
        self.volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        self.tick_volume = try container.decodeIfPresent(Double.self, forKey: .tick_volume)
        self.spread = try container.decodeIfPresent(Int.self, forKey: .spread)
        self.real_volume = try container.decodeIfPresent(Double.self, forKey: .real_volume)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(open, forKey: .open)
        try container.encode(high, forKey: .high)
        try container.encode(low, forKey: .low)
        try container.encode(close, forKey: .close)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(tick_volume, forKey: .tick_volume)
        try container.encodeIfPresent(spread, forKey: .spread)
        try container.encodeIfPresent(real_volume, forKey: .real_volume)
    }
}

struct MT5OrderListResponse: Codable, Sendable {
    let opened: [MT5Position]
    let pending: [MT5Position]

    enum CodingKeys: String, CodingKey {
        case opened, pending
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.opened = try container.decode([MT5Position].self, forKey: .opened)
        self.pending = try container.decode([MT5Position].self, forKey: .pending)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opened, forKey: .opened)
        try container.encode(pending, forKey: .pending)
    }
}

struct MT5HistoryResponse: Codable, Sendable {
    let data: [MT5HistoryPosition]

    enum CodingKeys: String, CodingKey {
        case data
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([MT5HistoryPosition].self, forKey: .data)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }
}

struct MT5HistoryPosition: Codable, Sendable {
    let symbol: String
    let ticket: Int64
    let type: String
    let volume: Double
    let open_price: Double
    let close_price: Double
    let open_time: Int64
    let close_time: Int64
    let profit: Double
    let commission: Double
    let swap: Double
    let comment: String?
    let magic: Int64?

    enum CodingKeys: String, CodingKey {
        case symbol, ticket, type, volume, open_price, close_price, open_time, close_time, profit, commission, swap, comment, magic
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.ticket = try container.decode(Int64.self, forKey: .ticket)
        self.type = try container.decode(String.self, forKey: .type)
        self.volume = try container.decode(Double.self, forKey: .volume)
        self.open_price = try container.decode(Double.self, forKey: .open_price)
        self.close_price = try container.decode(Double.self, forKey: .close_price)
        self.open_time = try container.decode(Int64.self, forKey: .open_time)
        self.close_time = try container.decode(Int64.self, forKey: .close_time)
        self.profit = try container.decode(Double.self, forKey: .profit)
        self.commission = try container.decode(Double.self, forKey: .commission)
        self.swap = try container.decode(Double.self, forKey: .swap)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        self.magic = try container.decodeIfPresent(Int64.self, forKey: .magic)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(ticket, forKey: .ticket)
        try container.encode(type, forKey: .type)
        try container.encode(volume, forKey: .volume)
        try container.encode(open_price, forKey: .open_price)
        try container.encode(close_price, forKey: .close_price)
        try container.encode(open_time, forKey: .open_time)
        try container.encode(close_time, forKey: .close_time)
        try container.encode(profit, forKey: .profit)
        try container.encode(commission, forKey: .commission)
        try container.encode(swap, forKey: .swap)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(magic, forKey: .magic)
    }

    // ✅ CUSTOM INITIALIZER - MUST BE NONISOLATED
    nonisolated init(
        symbol: String,
        ticket: Int64,
        type: String,
        volume: Double,
        open_price: Double,
        close_price: Double,
        open_time: Int64,
        close_time: Int64,
        profit: Double,
        commission: Double,
        swap: Double,
        comment: String?,
        magic: Int64?
    ) {
        self.symbol = symbol
        self.ticket = ticket
        self.type = type
        self.volume = volume
        self.open_price = open_price
        self.close_price = close_price
        self.open_time = open_time
        self.close_time = close_time
        self.profit = profit
        self.commission = commission
        self.swap = swap
        self.comment = comment
        self.magic = magic
    }
}

struct MT5SymbolInfo: Codable, Sendable {
    let name: String
    let trade_mode: Int
    let spread: Int
    let digits: Int
    let volume_min: Double?
    let volume_max: Double?
    let volume_step: Double?
    let point: Double?

    enum CodingKeys: String, CodingKey {
        case name, trade_mode, spread, digits, volume_min, volume_max, volume_step, point
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.trade_mode = try container.decode(Int.self, forKey: .trade_mode)
        self.spread = try container.decode(Int.self, forKey: .spread)
        self.digits = try container.decode(Int.self, forKey: .digits)
        self.volume_min = try container.decodeIfPresent(Double.self, forKey: .volume_min)
        self.volume_max = try container.decodeIfPresent(Double.self, forKey: .volume_max)
        self.volume_step = try container.decodeIfPresent(Double.self, forKey: .volume_step)
        self.point = try container.decodeIfPresent(Double.self, forKey: .point)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(trade_mode, forKey: .trade_mode)
        try container.encode(spread, forKey: .spread)
        try container.encode(digits, forKey: .digits)
        try container.encodeIfPresent(volume_min, forKey: .volume_min)
        try container.encodeIfPresent(volume_max, forKey: .volume_max)
        try container.encodeIfPresent(volume_step, forKey: .volume_step)
        try container.encodeIfPresent(point, forKey: .point)
    }
}

// MARK: - IG Models

struct IGAuthResponse: Codable, Sendable {
    let success: Bool
    let data: IGAuthData?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decode(Bool.self, forKey: .success)
        self.data = try container.decodeIfPresent(IGAuthData.self, forKey: .data)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

struct IGAuthData: Codable, Sendable {
    let cst: String
    let xSecurityToken: String
    let accountId: String
    let lightstreamerEndpoint: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case cst, xSecurityToken, accountId, lightstreamerEndpoint, sessionId
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cst = try container.decode(String.self, forKey: .cst)
        self.xSecurityToken = try container.decode(String.self, forKey: .xSecurityToken)
        self.accountId = try container.decode(String.self, forKey: .accountId)
        self.lightstreamerEndpoint = try container.decodeIfPresent(String.self, forKey: .lightstreamerEndpoint)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cst, forKey: .cst)
        try container.encode(xSecurityToken, forKey: .xSecurityToken)
        try container.encode(accountId, forKey: .accountId)
        try container.encodeIfPresent(lightstreamerEndpoint, forKey: .lightstreamerEndpoint)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
    }
}

struct IGAPIResponse<T: Codable & Sendable>: Codable, Sendable {
    let success: Bool
    let data: T?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decode(Bool.self, forKey: .success)
        self.data = try container.decodeIfPresent(T.self, forKey: .data)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

struct IGAccountInfo: Codable, Sendable {
    let accountId: String
    let accountName: String
    let balance: Double
    let deposit: Double
    let profitLoss: Double
    let available: Double
    let currency: String

    enum CodingKeys: String, CodingKey {
        case accountId, accountName, balance, deposit, profitLoss, available, currency
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accountId = try container.decode(String.self, forKey: .accountId)
        self.accountName = try container.decode(String.self, forKey: .accountName)
        self.balance = try container.decode(Double.self, forKey: .balance)
        self.deposit = try container.decode(Double.self, forKey: .deposit)
        self.profitLoss = try container.decode(Double.self, forKey: .profitLoss)
        self.available = try container.decode(Double.self, forKey: .available)
        self.currency = try container.decode(String.self, forKey: .currency)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(accountName, forKey: .accountName)
        try container.encode(balance, forKey: .balance)
        try container.encode(deposit, forKey: .deposit)
        try container.encode(profitLoss, forKey: .profitLoss)
        try container.encode(available, forKey: .available)
        try container.encode(currency, forKey: .currency)
    }
}

struct IGTradeResult: Codable, Sendable {
    let dealReference: String
    let dealId: String?
    let symbol: String
    let direction: String
    let size: Double
    let status: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case dealReference, dealId, symbol, direction, size, status, timestamp
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dealReference = try container.decode(String.self, forKey: .dealReference)
        self.dealId = try container.decodeIfPresent(String.self, forKey: .dealId)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.direction = try container.decode(String.self, forKey: .direction)
        self.size = try container.decode(Double.self, forKey: .size)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dealReference, forKey: .dealReference)
        try container.encodeIfPresent(dealId, forKey: .dealId)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(direction, forKey: .direction)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
    }
}

struct IGPosition: Codable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case dealId, epic, marketName, direction, size, level, limitLevel, stopLevel, createdDate, currency, profitLoss
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dealId = try container.decode(String.self, forKey: .dealId)
        self.epic = try container.decode(String.self, forKey: .epic)
        self.marketName = try container.decode(String.self, forKey: .marketName)
        self.direction = try container.decode(String.self, forKey: .direction)
        self.size = try container.decode(Double.self, forKey: .size)
        self.level = try container.decode(Double.self, forKey: .level)
        self.limitLevel = try container.decodeIfPresent(Double.self, forKey: .limitLevel)
        self.stopLevel = try container.decodeIfPresent(Double.self, forKey: .stopLevel)
        self.createdDate = try container.decode(String.self, forKey: .createdDate)
        self.currency = try container.decode(String.self, forKey: .currency)
        self.profitLoss = try container.decodeIfPresent(Double.self, forKey: .profitLoss)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dealId, forKey: .dealId)
        try container.encode(epic, forKey: .epic)
        try container.encode(marketName, forKey: .marketName)
        try container.encode(direction, forKey: .direction)
        try container.encode(size, forKey: .size)
        try container.encode(level, forKey: .level)
        try container.encodeIfPresent(limitLevel, forKey: .limitLevel)
        try container.encodeIfPresent(stopLevel, forKey: .stopLevel)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(currency, forKey: .currency)
        try container.encodeIfPresent(profitLoss, forKey: .profitLoss)
    }
}

// MARK: - Shared Errors

enum TradingError: Error {
    case invalidURL
    case apiError(String)
    case decodingError
    case serverNotRunning
    case notAuthenticated
    case insufficientFunds
    case marketClosed
}

extension TradingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .apiError(let message):
            return "API Error: \(message)"
        case .decodingError:
            return "Failed to decode response"
        case .serverNotRunning:
            return "Backend server is not running"
        case .notAuthenticated:
            return "Not authenticated"
        case .insufficientFunds:
            return "Insufficient funds"
        case .marketClosed:
            return "Market is closed"
        }
    }
}