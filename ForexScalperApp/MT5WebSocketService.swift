import Foundation

/// V10.6 MT5 event transport.
/// Authority boundary: Swift decides; MT5 executes; MT5 reports.
actor MT5WebSocketService {
    static let shared = MT5WebSocketService()

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var symbols: [String] = []
    private(set) var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var lastEventIDs: [String: Date] = [:]
    private var l2Cache: [String: (buyVol: Double, sellVol: Double, timestamp: Date)] = [:]

    private let maxReconnectDelay: UInt64 = 30

    func connect(symbols: [String]) {
        self.symbols = symbols
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        openSocket()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    private func openSocket() {
        guard webSocket == nil else { return }
        guard let url = URL(string: "ws://127.0.0.1:8890") else { return }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.webSocket = task
        task.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        guard let task = webSocket else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .success(let message):
                    await self.markConnected()
                    if case .string(let text) = message {
                        await self.handleMessage(text)
                    }
                    await self.receiveMessage()
                case .failure(let error):
                    await self.handleSocketFailure(error)
                }
            }
        }
    }

    private func markConnected() {
        isConnected = true
        reconnectAttempt = 0
    }

    private func handleSocketFailure(_ error: Error) {
        print("❌ MT5 WS: \(error.localizedDescription)")
        webSocket = nil
        isConnected = false
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectAttempt += 1
        let exponent = min(reconnectAttempt - 1, 5)
        let delay = min(maxReconnectDelay, UInt64(1 << exponent))
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self.finishReconnectWait()
        }
    }

    private func finishReconnectWait() {
        reconnectTask = nil
        openSocket()
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        if let eventID = json["event_id"] as? String {
            if lastEventIDs[eventID] != nil { return }
            lastEventIDs[eventID] = Date()
            if lastEventIDs.count > 2048 {
                let cutoff = Date().addingTimeInterval(-300)
                lastEventIDs = lastEventIDs.filter { $0.value >= cutoff }
            }
        }

        switch type {
        case "price_update": handlePriceUpdate(json)
        case "trade_event": handleTradeEvent(json)
        case "track_mbook": handleMbookUpdate(json)
        case "ohlc_update": handleOhlcUpdate(json)
        default: break
        }
    }

    private func handlePriceUpdate(_ json: [String: Any]) {
        if let items = json["data"] as? [[String: Any]] {
            for item in items { publishPrice(item) }
        } else {
            publishPrice(json)
        }
    }

    private func publishPrice(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String,
              let bid = Self.doubleValue(json["bid"]),
              let ask = Self.doubleValue(json["ask"]) else { return }

        let timestamp = Self.doubleValue(json["time_msc"])
            ?? Self.doubleValue(json["time"])
            ?? Self.doubleValue(json["timestamp"])
            ?? Date().timeIntervalSince1970

        NotificationCenter.default.post(
            name: .mt5PriceUpdated,
            object: nil,
            userInfo: ["symbol": symbol, "bid": bid, "ask": ask, "timestamp": timestamp]
        )
    }

    private func handleTradeEvent(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String else { return }
        let ticket = Self.int64Value(json["ticket"])
            ?? Self.int64Value(json["position"])
            ?? Self.int64Value(json["order"])
            ?? Self.int64Value(json["deal"])
        guard let ticket else { return }

        let userInfo: [String: Any] = [
            "ticket": String(ticket),
            "symbol": symbol,
            "deal": String(Self.int64Value(json["deal"]) ?? 0),
            "order": String(Self.int64Value(json["order"]) ?? 0),
            "position": String(Self.int64Value(json["position"]) ?? 0),
            "position_id": String(Self.int64Value(json["position_id"]) ?? 0),
            "profit": Self.doubleValue(json["profit"]) ?? 0.0,
            "swap": Self.doubleValue(json["swap"]) ?? 0.0,
            "commission": Self.doubleValue(json["commission"]) ?? 0.0,
            "price": Self.doubleValue(json["price"]) ?? 0.0,
            "volume": Self.doubleValue(json["volume"]) ?? 0.0,
            "entry": Self.int64Value(json["entry"]) ?? 0,
            "deal_type": Self.int64Value(json["deal_type"]) ?? 0,
            "magic": Self.int64Value(json["magic"]) ?? 0,
            "comment": json["comment"] as? String ?? "",
            "event_id": json["event_id"] as? String ?? ""
        ]
        NotificationCenter.default.post(name: .mt5TradeClosed, object: nil, userInfo: userInfo)
    }

    private func handleMbookUpdate(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String,
              let mbook = json["market_book"] as? [[String: Any]] else { return }
        var buyVol = 0.0
        var sellVol = 0.0
        for entry in mbook {
            let type = entry["type"] as? String ?? ""
            let vol = Self.doubleValue(entry["volume"]) ?? 0.0
            if type == "BOOK_TYPE_BUY" { buyVol += vol }
            if type == "BOOK_TYPE_SELL" { sellVol += vol }
        }
        l2Cache[symbol] = (buyVol, sellVol, Date())
    }

    private func handleOhlcUpdate(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String,
              let timeframe = json["timeframe"] as? String,
              let bars = json["bars"] as? [[String: Any]],
              let lastBar = bars.last else { return }
        let kline = Kline(
            open: Self.doubleValue(lastBar["open"]) ?? 0,
            high: Self.doubleValue(lastBar["high"]) ?? 0,
            low: Self.doubleValue(lastBar["low"]) ?? 0,
            close: Self.doubleValue(lastBar["close"]) ?? 0,
            volume: Self.doubleValue(lastBar["volume"]) ?? 0,
            closeTime: Int(Self.doubleValue(lastBar["time"]) ?? Date().timeIntervalSince1970),
            spread: 0,
            isClosed: true
        )
        NotificationCenter.default.post(name: .mt5OhlcUpdated, object: nil,
                                        userInfo: ["symbol": symbol, "timeframe": timeframe, "kline": kline])
    }

    func getDeltaVolume(for symbol: String) -> Double {
        guard let cache = l2Cache[symbol], Date().timeIntervalSince(cache.timestamp) < 5 else { return 0 }
        return cache.buyVol - cache.sellVol
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}
