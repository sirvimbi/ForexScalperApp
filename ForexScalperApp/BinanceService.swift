// BinanceService.swift - FIXED with single combined-stream connection
import Foundation

actor BinanceService: MarketDataProvider {
    private var symbols: [String] = []
    private var timeframes: [String] = []
    private var webSocketTask: URLSessionWebSocketTask?
    private var onKlineReceived: (@Sendable (String, String, Kline, Bool) -> Void)?
    private var pingTimer: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isReconnecting = false

    private let baseURL = "https://api.binance.com/api/v3"
    // Binance uses /stream for combined streams. /ws is for a single raw stream.
    private let wsBaseURL = "wss://stream.binance.com:9443/stream"

    func connect(symbols: [String], timeframes: [String], onKline: @escaping @Sendable (String, String, Kline, Bool) -> Void) {
        self.symbols = symbols
        self.timeframes = timeframes
        self.onKlineReceived = onKline

        Task {
            await fetchHistoricalData()
            connectWebSocket()
            startPingTimer()
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        pingTimer?.cancel()
        reconnectTask?.cancel()
        onKlineReceived = nil
        isReconnecting = false
        print("🔌 Binance: Disconnected")
    }

    func getCandles(symbol: String, timeframe: String) async -> [Kline] {
        return []
    }

    func getLatestPrice(symbol: String) async -> Double? {
        return nil
    }

    // MARK: - Private Methods

    private func fetchHistoricalData() async {
        print("📥 Fetching historical data for \(symbols.count) symbols...")

        for symbol in symbols {
            let binanceSymbol = convertToBinanceSymbol(symbol)
            if binanceSymbol.isEmpty { continue }

            for timeframe in timeframes {
                await fetchKlines(symbol: symbol, interval: convertToBinanceInterval(timeframe), limit: 1000)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        print("✅ Historical data fetch complete")
    }

    private func fetchKlines(symbol: String, interval: String, limit: Int) async {
        let binanceSymbol = convertToBinanceSymbol(symbol)
        guard !binanceSymbol.isEmpty else { return }

        let urlString = "\(baseURL)/klines?symbol=\(binanceSymbol)&interval=\(interval)&limit=\(limit)"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    print("📥 Received \(jsonArray.count) historical \(interval) candles for \(symbol)")

                    let klines = jsonArray.compactMap { item -> Kline? in
                        guard item.count >= 11,
                              let closeTime = item[6] as? Int64,
                              let open = Double(item[1] as? String ?? "0"),
                              let high = Double(item[2] as? String ?? "0"),
                              let low = Double(item[3] as? String ?? "0"),
                              let close = Double(item[4] as? String ?? "0"),
                              let volume = Double(item[5] as? String ?? "0") else {
                            return nil
                        }
                        return Kline(
                            open: open,
                            high: high,
                            low: low,
                            close: close,
                            volume: volume,
                            closeTime: Int(closeTime / 1000),
                            spread: nil,
                            isClosed: true
                        )
                    }

                    for kline in klines {
                        onKlineReceived?(symbol, interval, kline, false)
                    }
                }
            } else {
                print("⚠️ Failed to fetch Binance historical data for \(symbol) (\(binanceSymbol)) \(interval): \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("❌ Error fetching historical data for \(symbol) \(interval): \(error)")
        }
    }

    // Use one combined WebSocket connection for the 1m and 5m streams.
    private func connectWebSocket() {
        reconnectTask?.cancel()
        reconnectTask = nil

        let streams = buildStreams()

        if streams.isEmpty {
            print("ℹ️ No symbols available for Binance WebSocket")
            return
        }

        // Only include 1m and 5m for real-time updates.
        let filteredStreams = streams.filter { stream in
            stream.contains("@kline_1m") || stream.contains("@kline_5m")
        }

        print("📊 Subscribing to \(filteredStreams.count) streams (1m & 5m only)")

        if filteredStreams.isEmpty {
            print("ℹ️ No 1m or 5m streams available for Binance WebSocket")
            return
        }

        // IMPORTANT: Binance's combined-stream endpoint is /stream?streams=...
        // The /ws endpoint is for a single raw stream and returns 404 when used
        // with the combined-stream query parameter.
        let streamString = filteredStreams.joined(separator: "/")
        let urlString = "\(wsBaseURL)?streams=\(streamString)"

        guard let url = URL(string: urlString) else {
            print("❌ Failed to create Binance WebSocket URL")
            return
        }

        print("🌐 Connecting to Binance WebSocket: \(url.absoluteString.prefix(200))...")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()
        print("⏳ Binance WebSocket task started; awaiting handshake (1m & 5m)")
    }

    private func buildStreams() -> [String] {
        var streams: [String] = []

        for symbol in symbols {
            let binanceSymbol = convertToBinanceSymbol(symbol).lowercased()
            if binanceSymbol.isEmpty { continue }

            for timeframe in timeframes {
                let binanceInterval = convertToBinanceInterval(timeframe)
                streams.append("\(binanceSymbol)@kline_\(binanceInterval)")
            }
        }

        return streams
    }

    private func receiveMessage() {
        guard let task = webSocketTask else { return }

        Task {
            await receiveMessages(task: task)
        }
    }

    private func receiveMessages(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    await parseKlineMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await parseKlineMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                print("❌ WebSocket Error: \(error.localizedDescription)")
                await scheduleReconnect()
                break
            }
        }
    }

    private func scheduleReconnect() async {
        guard !isReconnecting else { return }
        isReconnecting = true

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, let self = self {
                await self.connectWebSocket()
                await self.setReconnecting(false)
            }
        }
    }

    private func setReconnecting(_ value: Bool) {
        isReconnecting = value
    }

    private func parseKlineMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        guard let json = try? decoder.decode(BinanceStreamResponse.self, from: data) else {
            return
        }

        let detail = json.data.k
        let symbol = findOriginalSymbol(for: json.data.s)
        let timeframe = convertFromBinanceInterval(detail.i)

        let kline = Kline(
            open: Double(detail.o) ?? 0,
            high: Double(detail.h) ?? 0,
            low: Double(detail.l) ?? 0,
            close: Double(detail.c) ?? 0,
            volume: Double(detail.v) ?? 0,
            closeTime: Int(detail.T / 1000),
            spread: nil,
            isClosed: detail.x
        )

        onKlineReceived?(symbol, timeframe, kline, true)
    }

    private func startPingTimer() {
        pingTimer?.cancel()
        pingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self = self else { break }
                await self.sendPing()
            }
        }
    }

    private func sendPing() {
        webSocketTask?.sendPing { error in
            if let error = error {
                print("❌ WebSocket Ping Error: \(error.localizedDescription)")
            } else {
                print("🏓 Received pong")
            }
        }
    }

    // MARK: - Helpers

    private func convertToBinanceSymbol(_ symbol: String) -> String {
        let whitelist = [
            "EURUSD": "EURUSDT",
            "GBPUSD": "GBPUSDT",
            "AUDUSD": "AUDUSDT",
            "BTCUSDT": "BTCUSDT",
            "ETHUSDT": "ETHUSDT",
            "XRPUSDT": "XRPUSDT",
            "LTCUSDT": "LTCUSDT",
            "ADAUSDT": "ADAUSDT",
            "SOLUSDT": "SOLUSDT"
        ]

        if let mapped = whitelist[symbol] {
            return mapped
        }

        if symbol.hasSuffix("USDT") {
            return symbol
        }

        return ""
    }

    private func findOriginalSymbol(for binanceSymbol: String) -> String {
        for sym in symbols {
            if convertToBinanceSymbol(sym) == binanceSymbol {
                return sym
            }
        }
        return binanceSymbol
    }

    private func convertToBinanceInterval(_ timeframe: String) -> String {
        switch timeframe.uppercased() {
        case "1M": return "1m"
        case "5M": return "5m"
        case "15M": return "15m"
        case "30M": return "30m"
        case "1H": return "1h"
        case "4H": return "4h"
        case "D1": return "1d"
        case "W1": return "1w"
        default: return "1m"
        }
    }

    private func convertFromBinanceInterval(_ interval: String) -> String {
        return interval
    }
}
