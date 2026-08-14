import Foundation

/// V10.6 MT5 event consumer.
/// Swift owns strategy/decision making; this actor only transports and reports broker state.
actor MT5WebSocketService {
    static let shared = MT5WebSocketService()

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var symbols: [String] = []
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var stopped = false
    private var seenEventIDs: [String: Date] = [:]
    private var lastPriceTimestamp: [String: Int64] = [:]
    private var l2Cache: [String: (buyVol: Double, sellVol: Double, timestamp: Date)] = [:]
    private var failureWasReported = false

    private let maxReconnectDelay: UInt64 = 30
    private let wsURL = URL(string: "ws://127.0.0.1:8890")!

    func connect(symbols: [String]) {
        self.symbols = symbols
        stopped = false
        reconnectAttempt = 0
        failureWasReported = false
        reconnectTask?.cancel()
        reconnectTask = nil
        godLog("🌐 MT5 WS: connect requested → \(wsURL.absoluteString) | symbols=\(symbols.count)", level: .diagnostic)
        openSocket()
    }

    func disconnect() {
        stopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        failureWasReported = false
        godLog("🌐 MT5 WS: disconnected by application", level: .diagnostic)
    }

    func connected() -> Bool { isConnected }

    private func openSocket() {
        guard !stopped else { return }

        webSocket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()

        let configuration = URLSessionConfiguration.default
        // This is a local loopback endpoint. Waiting for a general network path can
        // produce noisy nw_path diagnostics and delays failure detection.
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20

        let newSession = URLSession(configuration: configuration)
        session = newSession
        let task = newSession.webSocketTask(with: wsURL)
        webSocket = task
        task.resume()
        godLog("🌐 MT5 WS: socket task started (attempt \(max(reconnectAttempt, 1)))", level: .diagnostic)
        receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            Task {
                await self.handleReceive(result, task: task)
            }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, task: URLSessionWebSocketTask) {
        guard !stopped else { return }
        guard webSocket === task else { return }

        switch result {
        case .success(let message):
            let wasConnected = isConnected
            isConnected = true
            reconnectAttempt = 0
            if !wasConnected {
                godLog("🟢 MT5 WS: connection established/recovered", level: .success)
            }
            failureWasReported = false

            switch message {
            case .string(let text): handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) { handleMessage(text) }
            @unknown default: break
            }
            receiveLoop(task)

        case .failure(let error):
            isConnected = false

            // Keep the first failure prominent, but don't turn a broken local bridge
            // into a wall of identical warnings while the backoff loop is working.
            if !failureWasReported {
                godLog("❌ MT5 WS: receive failed [\(error._nsError.code)] \(error.localizedDescription)", level: .warning)
                failureWasReported = true
            } else {
                godLog("🔁 MT5 WS: reconnect cycle continues — \(error.localizedDescription)", level: .diagnostic)
            }

            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !stopped, reconnectTask == nil else { return }

        reconnectAttempt += 1
        let exponent = min(reconnectAttempt - 1, 5)
        let delay = min(UInt64(1 << exponent), maxReconnectDelay)

        godLog("🔄 MT5 WS: scheduling reconnect #\(reconnectAttempt) in \(delay)s", level: .diagnostic)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.clearReconnectTask()
            await self.openSocket()
        }
    }

    private func clearReconnectTask() { reconnectTask = nil }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            godLog("⚠️ MT5 WS: received non-JSON/unknown payload (\(text.prefix(120)))", level: .warning)
            return
        }

        if let version = json["version"] as? String, !version.isEmpty,
           !version.hasPrefix("10.") { return }

        if let eventID = string(json["event_id"]) {
            pruneSeenEvents()
            if seenEventIDs[eventID] != nil { return }
            seenEventIDs[eventID] = Date()
        }

        switch type {
        case "price_update": handlePriceUpdate(json)
        case "trade_event": handleTradeEvent(json)
        case "track_mbook": handleMbookUpdate(json)
        case "ohlc_update": handleOhlcUpdate(json)
        case "pong": godLog("🏓 MT5 WS: pong received", level: .diagnostic)
        default:
            godLog("🔍 MT5 WS: unhandled event type=\(type)", level: .diagnostic)
        }
    }

    private func handlePriceUpdate(_ json: [String: Any]) {
        let items = (json["data"] as? [[String: Any]]) ?? [json]
        for item in items {
            guard let symbol = string(item["symbol"]),
                  let bid = number(item["bid"]),
                  let ask = number(item["ask"]) else { continue }
            let timestamp = int64(item["time_msc"] ?? item["timestamp"] ?? item["time"]) ?? Int64(Date().timeIntervalSince1970 * 1000)
            if let previous = lastPriceTimestamp[symbol], timestamp < previous { continue }
            lastPriceTimestamp[symbol] = timestamp
            NotificationCenter.default.post(name: .mt5PriceUpdated, object: nil, userInfo: [
                "symbol": symbol, "bid": bid, "ask": ask,
                "last": number(item["last"]) ?? 0,
                "timestamp": timestamp,
                "time_msc": timestamp
            ])
        }
    }

    private func handleTradeEvent(_ json: [String: Any]) {
        let ticket = int64(json["ticket"] ?? json["position"] ?? json["position_id"] ?? json["deal"] ?? json["order"]) ?? 0
        let symbol = string(json["symbol"]) ?? ""
        guard ticket > 0, !symbol.isEmpty else { return }

        let userInfo: [String: Any] = [
            "event_id": string(json["event_id"]) ?? "",
            "ticket": ticket,
            "position_id": int64(json["position_id"] ?? json["position"]) ?? ticket,
            "deal": int64(json["deal"]) ?? 0,
            "order": int64(json["order"]) ?? 0,
            "symbol": symbol,
            "volume": number(json["volume"]) ?? 0,
            "price": number(json["price"]) ?? 0,
            "profit": number(json["profit"]) ?? 0,
            "swap": number(json["swap"]) ?? 0,
            "commission": number(json["commission"]) ?? 0,
            "entry": int64(json["entry"]) ?? 0,
            "deal_type": int64(json["deal_type"]) ?? 0,
            "reason": string(json["reason"]) ?? "Unknown",
            "time": int64(json["time"]) ?? Int64(Date().timeIntervalSince1970)
        ]
        godLog("📥 MT5 WS: trade_event ticket=\(ticket) symbol=\(symbol)", level: .diagnostic)
        NotificationCenter.default.post(name: .mt5TradeClosed, object: nil, userInfo: userInfo)
    }

    private func handleMbookUpdate(_ json: [String: Any]) {
        guard let symbol = string(json["symbol"]),
              let entries = json["market_book"] as? [[String: Any]] else { return }
        var buy = 0.0, sell = 0.0
        for entry in entries {
            let volume = number(entry["volume"]) ?? 0
            switch string(entry["type"]) {
            case "BOOK_TYPE_BUY": buy += volume
            case "BOOK_TYPE_SELL": sell += volume
            default: break
            }
        }
        l2Cache[symbol] = (buy, sell, Date())
    }

    private func handleOhlcUpdate(_ json: [String: Any]) {
        guard let symbol = string(json["symbol"]),
              let timeframe = string(json["timeframe"]),
              let bars = json["bars"] as? [[String: Any]],
              let bar = bars.last,
              let open = number(bar["open"]), let high = number(bar["high"]),
              let low = number(bar["low"]), let close = number(bar["close"]) else { return }
        let volume = number(bar["volume"]) ?? 0
        let closeTime = Int(int64(bar["time_msc"] ?? bar["time"]) ?? Int64(Date().timeIntervalSince1970))
        let kline = Kline(open: open, high: high, low: low, close: close, volume: volume, closeTime: closeTime, spread: number(bar["spread"]), isClosed: true)
        NotificationCenter.default.post(name: .mt5OhlcUpdated, object: nil, userInfo: ["symbol": symbol, "timeframe": timeframe, "kline": kline])
    }

    func getDeltaVolume(for symbol: String) -> Double {
        guard let cache = l2Cache[symbol], Date().timeIntervalSince(cache.timestamp) < 5 else { return 0 }
        return cache.buyVol - cache.sellVol
    }

    private func pruneSeenEvents() {
        let cutoff = Date().addingTimeInterval(-300)
        seenEventIDs = seenEventIDs.filter { $0.value >= cutoff }
    }

    private func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private func string(_ value: Any?) -> String? { value as? String }
}
