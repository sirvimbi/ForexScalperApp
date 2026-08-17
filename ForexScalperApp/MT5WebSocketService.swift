import Foundation

/// V10.6 MT5 event consumer.
/// Swift owns strategy/decision making; this actor transports broker state and provides
/// a deterministic price heartbeat so signal evaluation does not depend solely on push events.
actor MT5WebSocketService {
    static let shared = MT5WebSocketService()

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var symbols: [String] = []
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    private var signalHeartbeatTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var stopped = false
    private var seenEventIDs: [String: Date] = [:]
    private var lastPriceTimestamp: [String: Int64] = [:]
    private var l2Cache: [String: (buyVol: Double, sellVol: Double, timestamp: Date)] = [:]
    private var failureWasReported = false
    private var customWSURL: URL?
    private var brokerSuffix = ""

    private let maxReconnectDelay: UInt64 = 30
    private var wsURL: URL {
        if let custom = customWSURL { return custom }
        return URL(string: "ws://127.0.0.1:8890")!
    }

    func setBaseURL(_ urlString: String) {
        let wsUrlString = urlString.replacingOccurrences(of: "http://", with: "ws://")
                                    .replacingOccurrences(of: "https://", with: "wss://")
        if let url = URL(string: wsUrlString) {
            self.customWSURL = url
            godLog("🌐 MT5 WS: Base URL updated to \(wsUrlString)", level: .info)
        }
    }

    func connect(symbols: [String]) async {
        self.symbols = symbols
        self.brokerSuffix = await MainActor.run { ScalpingConfig.shared.brokerSuffix.trimmingCharacters(in: .whitespacesAndNewlines) }
        stopped = false
        reconnectAttempt = 0
        failureWasReported = false
        reconnectTask?.cancel()
        reconnectTask = nil
        signalHeartbeatTask?.cancel()
        signalHeartbeatTask = nil
        godLog("🌐 MT5 WS: connect requested → \(wsURL.absoluteString) | symbols=\(symbols.count) | brokerSuffix='\(brokerSuffix)'", level: .info)
        openSocket()
        startSignalEvaluationHeartbeat()
    }

    func disconnect() {
        stopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        signalHeartbeatTask?.cancel()
        signalHeartbeatTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        failureWasReported = false
        godLog("🌐 MT5 WS: disconnected by application", level: .info)
    }

    func connected() -> Bool { isConnected }

    private func startSignalEvaluationHeartbeat() {
        let settings = SignalRuntimeSettings.load()
        guard settings.heartbeatEnabled else {
            godLog("🧠 SIGNAL HEARTBEAT: disabled by settings", level: .info)
            return
        }

        signalHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.emitSignalEvaluationPrices()
                let interval = SignalRuntimeSettings.load().heartbeatIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        godLog("🧠 SIGNAL HEARTBEAT: started | interval=\(settings.heartbeatIntervalSeconds)s | candleCount=\(settings.heartbeatCandleCount)", level: .success)
    }

    private func emitSignalEvaluationPrices() async {
        guard !stopped else { return }
        let requestedSymbols = symbols
        guard !requestedSymbols.isEmpty else { return }
        let settings = SignalRuntimeSettings.load()
        let suffix = brokerSuffix

        for rawSymbol in requestedSymbols {
            if Task.isCancelled { return }
            let strategySymbol = normalizeStrategySymbol(rawSymbol, brokerSuffix: suffix)
            let brokerSymbol = resolveBrokerSymbol(rawSymbol, brokerSuffix: suffix)
            do {
                let candles = try await MT5Service.shared.getCandles(symbol: brokerSymbol, timeframe: "1m", count: settings.heartbeatCandleCount)
                guard let last = candles.last else {
                    godLog("🧠 SIGNAL HEARTBEAT | \(strategySymbol) | broker=\(brokerSymbol) | NO 1m candle returned", level: .warning)
                    continue
                }
                let timestamp = normalizeEpochMilliseconds(last.closeTime)
                let bid = last.close
                let ask = last.close
                godLog("🧠 SIGNAL HEARTBEAT | \(strategySymbol) | broker=\(brokerSymbol) | 1m candles=\(candles.count) | price=\(String(format: "%.5f", bid)) | ts=\(timestamp) | dispatch=evaluateFastSignal", level: .diagnostic)
                NotificationCenter.default.post(name: .mt5PriceUpdated, object: nil, userInfo: [
                    "symbol": strategySymbol,
                    "brokerSymbol": brokerSymbol,
                    "bid": bid,
                    "ask": ask,
                    "last": last.close,
                    "timestamp": timestamp,
                    "time_msc": timestamp,
                    "source": "signal_heartbeat"
                ])
            } catch {
                godLog("❌ SIGNAL HEARTBEAT | \(strategySymbol) | broker=\(brokerSymbol) | candle fetch failed: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    private func normalizeEpochMilliseconds(_ timestamp: Int) -> Int64 {
        if timestamp > 0 && timestamp < 100_000_000_000 { return Int64(timestamp) * 1_000 }
        return Int64(timestamp)
    }

    private func resolveBrokerSymbol(_ symbol: String, brokerSuffix: String) -> String {
        let cleaned = symbol.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brokerSuffix.isEmpty else { return cleaned }
        let lowerSymbol = cleaned.lowercased()
        let lowerSuffix = brokerSuffix.lowercased()
        return lowerSymbol.hasSuffix(lowerSuffix) ? cleaned : cleaned + brokerSuffix
    }

    private func normalizeStrategySymbol(_ symbol: String, brokerSuffix: String) -> String {
        var normalized = symbol.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = normalized.firstIndex(of: ".") { normalized = String(normalized[..<dot]) }
        if !brokerSuffix.isEmpty && normalized.lowercased().hasSuffix(brokerSuffix.lowercased()) {
            normalized = String(normalized.dropLast(brokerSuffix.count))
        }
        normalized = normalized.replacingOccurrences(of: "_", with: "")
        if normalized.uppercased() == "USTEC" || normalized.uppercased() == "US100" { return "US100" }
        return normalized.uppercased()
    }

    private func openSocket() {
        guard !stopped else { return }
        webSocket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20

        let newSession = URLSession(configuration: configuration)
        session = newSession
        let task = newSession.webSocketTask(with: wsURL)
        webSocket = task
        task.resume()
        godLog("🌐 MT5 WS: socket task started (attempt \(max(reconnectAttempt, 1)))", level: .info)
        receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            Task { await self.handleReceive(result, task: task) }
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
            if !wasConnected { godLog("🟢 MT5 WS: connection established/recovered", level: .success) }
            failureWasReported = false
            switch message {
            case .string(let text): handleMessage(text)
            case .data(let data): if let text = String(data: data, encoding: .utf8) { handleMessage(text) }
            @unknown default: break
            }
            receiveLoop(task)
        case .failure(let error):
            isConnected = false
            let nsError = error as NSError
            if !failureWasReported {
                godLog("❌ MT5 WS: receive failed [\(nsError.code)] \(error.localizedDescription)", level: .warning)
                failureWasReported = true
            } else { godLog("🔁 MT5 WS: reconnect cycle continues — \(error.localizedDescription)", level: .info) }
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !stopped, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let exponent = min(reconnectAttempt - 1, 5)
        let delay = min(UInt64(1 << exponent), maxReconnectDelay)
        godLog("🔄 MT5 WS: scheduling reconnect #\(reconnectAttempt) in \(delay)s", level: .info)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.clearReconnectTask()
            await self.openSocket()
        }
    }

    private func clearReconnectTask() { reconnectTask = nil }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = json["type"] as? String else {
            godLog("⚠️ MT5 WS: received non-JSON/unknown payload (\(text.prefix(120)))", level: .warning)
            return
        }
        if let version = json["version"] as? String, !version.isEmpty, !version.hasPrefix("10.") { return }
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
        case "pong": godLog("🏓 MT5 WS: pong received", level: .info)
        default: godLog("🔍 MT5 WS: unhandled event type=\(type)", level: .info)
        }
    }

    private func handlePriceUpdate(_ json: [String: Any]) {
        let items = (json["data"] as? [[String: Any]]) ?? [json]
        for item in items {
            guard let rawSymbol = string(item["symbol"]), let bid = number(item["bid"]), let ask = number(item["ask"]) else {
                godLog("⚠️ MT5 WS: malformed price_update — missing symbol/bid/ask", level: .warning)
                continue
            }
            let symbol = normalizeStrategySymbol(rawSymbol, brokerSuffix: brokerSuffix)
            let timestamp = int64(item["time_msc"] ?? item["timestamp"] ?? item["time"]) ?? Int64(Date().timeIntervalSince1970 * 1000)
            if let previous = lastPriceTimestamp[rawSymbol], timestamp < previous { continue }
            lastPriceTimestamp[rawSymbol] = timestamp
            godLog("💹 MT5 PRICE | broker=\(rawSymbol) strategy=\(symbol) bid=\(String(format: "%.5f", bid)) ask=\(String(format: "%.5f", ask)) | ts=\(timestamp)", level: .diagnostic)
            NotificationCenter.default.post(name: .mt5PriceUpdated, object: nil, userInfo: ["symbol": symbol, "brokerSymbol": rawSymbol, "bid": bid, "ask": ask, "last": number(item["last"]) ?? 0, "timestamp": timestamp, "time_msc": timestamp])
        }
    }

    private func handleTradeEvent(_ json: [String: Any]) {
        let ticket = int64(json["ticket"] ?? json["position"] ?? json["position_id"] ?? json["deal"] ?? json["order"]) ?? 0
        let rawSymbol = string(json["symbol"]) ?? ""
        guard ticket > 0, !rawSymbol.isEmpty else { return }
        let userInfo: [String: Any] = ["event_id": string(json["event_id"]) ?? "", "ticket": ticket, "position_id": int64(json["position_id"] ?? json["position"]) ?? ticket, "deal": int64(json["deal"]) ?? 0, "order": int64(json["order"]) ?? 0, "symbol": normalizeStrategySymbol(rawSymbol, brokerSuffix: brokerSuffix), "brokerSymbol": rawSymbol, "volume": number(json["volume"]) ?? 0, "price": number(json["price"]) ?? 0, "profit": number(json["profit"]) ?? 0, "swap": number(json["swap"]) ?? 0, "commission": number(json["commission"]) ?? 0, "entry": int64(json["entry"]) ?? 0, "deal_type": int64(json["deal_type"]) ?? 0, "reason": string(json["reason"]) ?? "Unknown", "time": int64(json["time"]) ?? Int64(Date().timeIntervalSince1970)]
        godLog("📥 MT5 WS: trade_event ticket=\(ticket) symbol=\(rawSymbol)", level: .info)
        NotificationCenter.default.post(name: .mt5TradeClosed, object: nil, userInfo: userInfo)
    }

    private func handleMbookUpdate(_ json: [String: Any]) {
        guard let rawSymbol = string(json["symbol"]), let entries = json["market_book"] as? [[String: Any]] else { return }
        let symbol = normalizeStrategySymbol(rawSymbol, brokerSuffix: brokerSuffix)
        var buy = 0.0, sell = 0.0
        for entry in entries {
            let volume = number(entry["volume"]) ?? 0
            switch string(entry["type"]) { case "BOOK_TYPE_BUY": buy += volume; case "BOOK_TYPE_SELL": sell += volume; default: break }
        }
        l2Cache[symbol] = (buy, sell, Date())
        godLog("📚 MT5 L2 | \(symbol) | buy=\(String(format: "%.2f", buy)) sell=\(String(format: "%.2f", sell)) delta=\(String(format: "%.2f", buy - sell))", level: .diagnostic)
    }

    private func handleOhlcUpdate(_ json: [String: Any]) {
        guard let rawSymbol = string(json["symbol"]), let timeframe = string(json["timeframe"]), let bars = json["bars"] as? [[String: Any]], let bar = bars.last, let open = number(bar["open"]), let high = number(bar["high"]), let low = number(bar["low"]), let close = number(bar["close"]) else { return }
        let symbol = normalizeStrategySymbol(rawSymbol, brokerSuffix: brokerSuffix)
        let volume = number(bar["volume"]) ?? 0
        let closeTime = Int(int64(bar["time_msc"] ?? bar["time"]) ?? Int64(Date().timeIntervalSince1970))
        let kline = Kline(open: open, high: high, low: low, close: close, volume: volume, closeTime: closeTime, spread: number(bar["spread"]), isClosed: true)
        godLog("🕯️ MT5 OHLC | \(symbol) | TF=\(timeframe) | close=\(String(format: "%.5f", close)) | bars=\(bars.count)", level: .diagnostic)
        NotificationCenter.default.post(name: .mt5OhlcUpdated, object: nil, userInfo: ["symbol": symbol, "brokerSymbol": rawSymbol, "timeframe": timeframe, "kline": kline])
    }

    func getDeltaVolume(for symbol: String) -> Double {
        let normalized = normalizeStrategySymbol(symbol, brokerSuffix: brokerSuffix)
        guard let cache = l2Cache[normalized], Date().timeIntervalSince(cache.timestamp) < 5 else { return 0 }
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
