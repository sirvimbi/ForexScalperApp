// BinanceService.swift - REFACTORED FOR RELIABILITY
import Foundation

actor BinanceService: MarketDataProvider {
    private var symbols: [String] = []
    private var timeframes: [String] = []
    private var webSocketTask: URLSessionWebSocketTask?
    private var onKlineReceived: (@Sendable (String, String, Kline) -> Void)?
    private var pingTimer: Task<Void, Never>?
    
    private let baseURL = "https://api.binance.com/api/v3"
    private let wsURL = "wss://stream.binance.com:9443/stream?streams="
    
    func connect(symbols: [String], timeframes: [String], onKline: @escaping @Sendable (String, String, Kline) -> Void) {
        self.symbols = symbols
        self.timeframes = timeframes
        self.onKlineReceived = onKline
        
        Task {
            // First fetch historical data
            await fetchHistoricalData()
            // Then connect to WebSocket for real-time updates
            connectWebSocket()
            // Start ping timer to keep connection alive
            startPingTimer()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        pingTimer?.cancel()
        onKlineReceived = nil
        print("🔌 Binance: Disconnected")
    }
    
    func getCandles(symbol: String, timeframe: String) async -> [Kline] {
        // This is handled via the RefactoredMarketDataActor
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
            
            // Collect all timeframes first before firing any "recent" callbacks
            for timeframe in timeframes {
                // ELITE DEPTH: 1000 bars for better trend analysis
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
                    
                    // Compact map to process valid klines only
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
                        return Kline(open: open, high: high, low: low, close: close, volume: volume, closeTime: Int(closeTime / 1000), spread: nil)
                    }
                    
                    // Call the handler for each kline
                    for kline in klines {
                        onKlineReceived?(symbol, interval, kline)
                    }
                }
            } else {
                print("⚠️ Failed to fetch Binance historical data for \(symbol) (\(binanceSymbol)) \(interval): \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("❌ Error fetching historical data for \(symbol) \(interval): \(error)")
        }
    }
    
    private func connectWebSocket() {
        // Binance requires lowercase symbols and specific stream naming
        let streams = symbols.compactMap { symbol -> [String]? in
            let binanceSymbol = convertToBinanceSymbol(symbol).lowercased()
            if binanceSymbol.isEmpty { return nil }
            
            return timeframes.map { timeframe in
                let binanceInterval = convertToBinanceInterval(timeframe)
                return "\(binanceSymbol)@kline_\(binanceInterval)"
            }
        }.flatMap { $0 }.joined(separator: "/")
        
        if streams.isEmpty {
            print("ℹ️ No symbols available for Binance WebSocket")
            return
        }
        
        guard let url = URL(string: wsURL + streams) else { return }
        
        print("🌐 Connecting to Binance WebSocket: \(url.absoluteString)")
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
        print("✅ WebSocket connected for real-time updates")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Task { await self.parseKlineMessage(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        Task { await self.parseKlineMessage(text) }
                    }
                @unknown default:
                    break
                }
                Task { [weak self] in
                    await self?.receiveMessage()
                }
                
            case .failure(let error):
                print("❌ WebSocket Error: \(error.localizedDescription)")
                // Reconnect after delay
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    await self.connectWebSocket()
                }
            }
        }
    }
    
    private func parseKlineMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONDecoder().decode(BinanceStreamResponse.self, from: data) else {
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
            spread: nil
        )
        
        onKlineReceived?(symbol, timeframe, kline)
    }
    
    private func startPingTimer() {
        pingTimer?.cancel()
        pingTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                webSocketTask?.sendPing { error in
                    if let error = error {
                        print("❌ WebSocket Ping Error: \(error.localizedDescription)")
                    } else {
                        print("🏓 Received pong")
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func convertToBinanceSymbol(_ symbol: String) -> String {
        // PRODUCTION WHITELIST: Only return symbols verified to exist on Binance Spot API
        // This prevents 400 errors for Forex pairs that Binance doesn't support as Spot.
        
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
        
        // If it's a crypto symbol already ending in USDT, allow it
        if symbol.hasSuffix("USDT") {
            return symbol
        }
        
        // For all other symbols (Exotic Forex, specialized crosses), return empty
        // to force the app to use MT5 for historical data and real-time updates.
        return ""
    }
    
    private func findOriginalSymbol(for binanceSymbol: String) -> String {
        // Search in our symbols list to see if we have a match
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
        return interval // They are usually the same in this app's logic
    }
}

// MARK: - Stream Models
struct BinanceStreamResponse: Codable, Sendable {
    let stream: String
    let data: BinanceKlineData
}

struct BinanceKlineData: Codable, Sendable {
    let e: String // Event type
    let E: Int64  // Event time
    let s: String // Symbol
    let k: BinanceKlineDetail
}

struct BinanceKlineDetail: Codable, Sendable {
    let t: Int64  // Kline start time
    let T: Int    // Kline close time
    let s: String // Symbol
    let i: String // Interval
    let f: Int64  // First trade ID
    let L: Int64  // Last trade ID
    let o: String // Open price
    let c: String // Close price
    let h: String // High price
    let l: String // Low price
    let v: String // Base asset volume
    let n: Int    // Number of trades
    let x: Bool   // Is this kline closed?
    let q: String // Quote asset volume
    let V: String // Taker buy base asset volume
    let Q: String // Taker buy quote asset volume
    let B: String // Ignore
}
