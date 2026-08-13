import Foundation

actor MT5WebSocketService {
    static let shared = MT5WebSocketService()

    private var webSocket: URLSessionWebSocketTask?
    private var symbols: [String] = []
    private var isConnected = false

    // L2 Data Cache: [Symbol: (buyVol: Double, sellVol: Double, timestamp: Date)]
    private var l2Cache: [String: (buyVol: Double, sellVol: Double, timestamp: Date)] = [:]

    func connect(symbols: [String]) {
        self.symbols = symbols
        // Connect directly to the EA's WebSocket server
        let urlString = "ws://127.0.0.1:8890"
        guard let url = URL(string: urlString) else { return }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.webSocket = task
        task.resume()
        self.isConnected = true

        receiveMessage()

        // Request tracking via the REST bridge to ensure EA starts sending updates
        Task {
            await startMbookTracking()
            await startTradeEventTracking()
        }
    }

    private func startMbookTracking() async {
        // Use the REST bridge to enable MBook tracking in the EA
        let urlString = "http://127.0.0.1:8890/v1/track/mbook"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["symbols": symbols]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ MT5 WS: L2 Tracking enabled for \(symbols.joined(separator: ", "))")
            }
        } catch {
            print("❌ MT5 WS: Failed to enable L2 tracking: \(error)")
        }
    }

    private func startTradeEventTracking() async {
        // Use the REST bridge to enable Trade Event tracking in the EA
        let urlString = "http://127.0.0.1:8890/v1/track/orders"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["enabled": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ MT5 WS: Trade Event tracking enabled")
            }
        } catch {
            print("❌ MT5 WS: Failed to enable trade event tracking: \(error)")
        }
    }

    private func receiveMessage() {
        guard let task = webSocket else { return }

        task.receive { [weak self] result in
            guard let self = self else { return }

            Task {
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        await self.handleMessage(text)
                    default: break
                    }
                    // Recursive call within the task to maintain isolation
                    await self.receiveMessage()
                case .failure(let error):
                    print("❌ MT5 WS: Error: \(error)")
                    await self.setDisconnected()
                }
            }
        }
    }

    private func setDisconnected() {
        self.isConnected = false
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "track_mbook":
            handleMbookUpdate(json)
        case "price_update":
            handlePriceUpdate(json)
        case "ohlc_update":
            handleOhlcUpdate(json)
        case "trade_event":
            handleTradeEvent(json)
        default:
            break
        }
    }

    private func handleTradeEvent(_ json: [String: Any]) {
        guard let ticket = json["ticket"] as? Int64,
              let symbol = json["symbol"] as? String else {
            return
        }

        let userInfo: [String: Any] = [
            "ticket": String(ticket),
            "symbol": symbol,
            "profit": json["profit"] as? Double ?? 0.0,
            "swap": json["swap"] as? Double ?? 0.0,
            "commission": json["commission"] as? Double ?? 0.0,
            "reason": json["reason"] as? String ?? "Unknown"
        ]

        NotificationCenter.default.post(name: .mt5TradeClosed, object: nil, userInfo: userInfo)
    }

    private func handleMbookUpdate(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String,
              let mbook = json["market_book"] as? [[String: Any]] else {
            return
        }

        var buyVol = 0.0
        var sellVol = 0.0

        for entry in mbook {
            let type = entry["type"] as? String ?? ""
            let vol = entry["volume"] as? Double ?? 0.0

            if type == "BOOK_TYPE_BUY" {
                buyVol += vol
            } else if type == "BOOK_TYPE_SELL" {
                sellVol += vol
            }
        }

        l2Cache[symbol] = (buyVol: buyVol, sellVol: sellVol, timestamp: Date())
    }

    private func handlePriceUpdate(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String,
              let bid = json["bid"] as? Double,
              let ask = json["ask"] as? Double else {
            return
        }

        let priceData: [String: Any] = [
            "symbol": symbol,
            "bid": bid,
            "ask": ask,
            "timestamp": json["timestamp"] ?? Date().timeIntervalSince1970
        ]

        NotificationCenter.default.post(name: .mt5PriceUpdated, object: nil, userInfo: priceData)
    }

    private func handleOhlcUpdate(_ json: [String: Any]) {
        guard let symbol = json["symbol"] as? String,
              let timeframe = json["timeframe"] as? String,
              let bars = json["bars"] as? [[String: Any]],
              let lastBar = bars.last else {
            return
        }

        let open = lastBar["open"] as? Double ?? 0
        let high = lastBar["high"] as? Double ?? 0
        let low = lastBar["low"] as? Double ?? 0
        let close = lastBar["close"] as? Double ?? 0
        let vol = Double(lastBar["volume"] as? Int ?? 0)
        let now = Int(Date().timeIntervalSince1970)

        // Convert to Kline model and notify
        let kline = Kline(
            open: open,
            high: high,
            low: low,
            close: close,
            volume: vol,
            closeTime: now,
            spread: 0,
            isClosed: true
        )

        let userInfo: [String: Any] = [
            "symbol": symbol,
            "timeframe": timeframe,
            "kline": kline
        ]

        NotificationCenter.default.post(name: .mt5OhlcUpdated, object: nil, userInfo: userInfo)
    }

    func getDeltaVolume(for symbol: String) -> Double {
        guard let cache = l2Cache[symbol],
              Date().timeIntervalSince(cache.timestamp) < 5.0 else {
            return 0.0
        }
        return cache.buyVol - cache.sellVol
    }
}
