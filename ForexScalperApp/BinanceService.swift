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
    private var isWebSocketConnected = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

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
        }
    }

    func disconnect() {
        isWebSocketConnected = false
        pingTimer?.cancel()
        pingTimer = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        onKlineReceived = nil
        isReconnecting = false
        godLog("🔌 Binance: Disconnected", level: .info)
    }

    func getCandles(symbol: String, timeframe: String) async -> [Kline] {
        return []
    }

    func getLatestPrice(symbol: String) async -> Double? {
        return nil
    }

    // MARK: - Private Methods

    private func fetchHistoricalData() async {
        godLog("📥 Fetching historical data for \(symbols.count) symbols...", level: .info)

        for symbol in symbols {
            let binanceSymbol = convertToBinanceSymbol(symbol)
            if binanceSymbol.isEmpty { continue }

            for timeframe in timeframes {
                await fetchKlines(symbol: symbol, interval: convertToBinanceInterval(timeframe), limit: 1000)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        godLog("✅ Historical data fetch complete", level: .success)
    }

    private func fetchKlines(symbol: String, interval: String, limit: Int) async {
        let binanceSymbol = convertToBinanceSymbol(symbol)
        guard !binanceSymbol.isEmpty else { return }

        let urlString = "\(baseURL)/klines?symbol=\(binanceSymbol)&interval=\(interval)&limit=\(limit)"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    godLog("📥 Received \(jsonArray.count) historical \(interval) candles for \(symbol)", level: .info)

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
                godLog("⚠️ Failed to fetch Binance historical data for \(symbol) (\(binanceSymbol)) \(interval): \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            godLog("❌ Error fetching historical data for \(symbol) \(interval): \(error)")
        }
    }

    // Use one combined WebSocket connection for the 1m and 5m streams.
    private func connectWebSocket() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTimer?.cancel()
        pingTimer = nil
        isWebSocketConnected = false

        let streams = buildStreams()

        if streams.isEmpty {
            godLog("ℹ️ No symbols available for Binance WebSocket")
            return
        }

        let filteredStreams = streams.filter { stream in
            stream.contains("@kline_1m") || stream.contains("@kline_5m")
        }

        godLog("📊 Subscribing to \(filteredStreams.count) streams (1m & 5m only)")

        if filteredStreams.isEmpty {
            godLog("ℹ️ No 1m or 5m streams available for Binance WebSocket")
            return
        }

        // Binance's combined-stream endpoint is /stream?streams=...
        let streamString = filteredStreams.joined(separator: "/")
        let urlString = "\(wsBaseURL)?streams=\(streamString)"

        guard let url = URL(string: urlString) else {
            godLog("❌ Failed to create Binance WebSocket URL")
            return
        }

        godLog("🌐 Connecting to Binance WebSocket: \(url.absoluteString.prefix(200))...")
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveMessage(task: task)
        godLog("⏳ Binance WebSocket task started; awaiting handshake (1m & 5m)", level: .info)
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

    private func receiveMessage(task: URLSessionWebSocketTask) {
        Task { [weak self] in
            guard let self else { return }
            await self.receiveMessages(task: task)
        }
    }

    private func receiveMessages(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()

                guard webSocketTask === task else {
                    return
                }

                if !isWebSocketConnected {
                    isWebSocketConnected = true
                    godLog("✅ Binance WebSocket connected — receiving market data", level: .success)
                    startPingTimer()
                }

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
                guard webSocketTask === task else {
                    return
                }

                isWebSocketConnected = false
                pingTimer?.cancel()
                pingTimer = nil

                let nsError = error as NSError
                if nsError.code == NSURLErrorCancelled {
                    return
                }

                godLog("⚠️ Binance WebSocket disconnected — \(error.localizedDescription)", level: .warning)
                await scheduleReconnect()
                return
            }
        }
    }

    private func scheduleReconnect() async {
        guard !isReconnecting else { return }
        isReconnecting = true

        godLog("🔄 Binance: scheduling reconnect in 5s", level: .info)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }

            await self.connectWebSocket()
            await self.setReconnecting(false)
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
                guard !Task.isCancelled, let self else { break }
                await self.sendPing()
            }
        }
    }

    private func sendPing() {
        guard isWebSocketConnected, let task = webSocketTask, task.state == .running else {
            return
        }

        task.sendPing { error in
            if let error {
                godLog("🏓 Binance ping failed — connection will be evaluated by receive loop: \(error.localizedDescription)", level: .info)
            } else {
                godLog("🏓 Binance pong received", level: .info)
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
