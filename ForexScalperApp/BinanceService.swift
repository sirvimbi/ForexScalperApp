// BinanceService.swift - REFACTORED FOR RELIABILITY
import Foundation

actor BinanceService: MarketDataProvider {
    private var symbols: [String] = []
    private var timeframes: [String] = []
    private var webSocketTask: URLSessionWebSocketTask?
    private var onKlineReceived: ((String, String, Kline) -> Void)?
    private var pingTimer: Task<Void, Never>?
    
    private let baseURL = "https://api.binance.com/api/v3"
    private let wsURL = "wss://stream.binance.com:9443/stream?streams="
    
    func connect(symbols: [String], timeframes: [String], onKline: @escaping (String, String, Kline) -> Void) {
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
            for timeframe in timeframes {
                await fetchKlines(symbol: symbol, interval: convertToBinanceInterval(timeframe), limit: 200)
                // Add a small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        print("✅ Historical data fetch complete")
    }
    
    private func fetchKlines(symbol: String, interval: String, limit: Int) async {
        let binanceSymbol = convertToBinanceSymbol(symbol)
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
                        return Kline(open: open, high: high, low: low, close: close, volume: volume, closeTime: Int(closeTime))
                    }
                    
                    // Call the handler for each kline
                    for kline in klines {
                        onKlineReceived?(symbol, interval, kline)
                    }
                }
            } else {
                print("⚠️ Failed to fetch historical data for \(symbol) \(interval): \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("❌ Error fetching historical data for \(symbol) \(interval): \(error)")
        }
    }
    
    private func connectWebSocket() {
        // Binance requires lowercase symbols and specific stream naming
        let streams = symbols.flatMap { symbol in
            timeframes.map { timeframe in
                let binanceSymbol = convertToBinanceSymbol(symbol).lowercased()
                let binanceInterval = convertToBinanceInterval(timeframe)
                return "\(binanceSymbol)@kline_\(binanceInterval)"
            }
        }.joined(separator: "/")
        
        guard let url = URL(string: wsURL + streams) else { return }
        
        print("🌐 Connecting to Binance WebSocket: \(url.absoluteString)")
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
        print("✅ WebSocket connected for real-time updates")
        print("📡 Now monitoring \(symbols.count) symbols in real-time")
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
                self.receiveMessage()
                
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
            closeTime: detail.T
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
        // 1. Precise mappings for known pairs
        let forexToBinance = [
            "EURUSD": "EURUSDT",
            "GBPUSD": "GBPUSDT",
            "AUDUSD": "AUDUSDT",
            "NZDUSD": "NZDUSDT",
            "USDJPY": "USDJPY",   // Some Binance regions have this
            "USDCAD": "USDCAD",
            "USDCHF": "USDCHF",
            "EURGBP": "EURGBP",
            "EURJPY": "EURJPY",
            "GBPJPY": "GBPJPY"
        ]
        
        if let mapped = forexToBinance[symbol] {
            return mapped
        }
        
        // 2. Crypto mappings
        let cryptoMajors = ["BTC", "ETH", "XRP", "ADA", "SOL", "DOT", "DOGE", "AVAX", "LINK", "LTC"]
        for crypto in cryptoMajors {
            if symbol.starts(with: crypto) && !symbol.hasSuffix("USDT") {
                return "\(crypto)USDT"
            }
        }

        // 3. If it already has USDT, return as is
        if symbol.hasSuffix("USDT") { return symbol }
        
        // 4. Default: try appending USDT if it's a 3-letter crypto or common major
        if symbol.count <= 4 {
            return "\(symbol)USDT"
        }
        
        return symbol
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
        switch timeframe {
        case "1m": return "1m"
        case "5m": return "5m"
        case "15m": return "15m"
        case "30m": return "30m"
        case "1h": return "1h"
        case "4h": return "4h"
        case "1d": return "1d"
        default: return "1m"
        }
    }
    
    private func convertFromBinanceInterval(_ interval: String) -> String {
        return interval // They are usually the same in this app's logic
    }
}

// MARK: - Stream Models
struct BinanceStreamResponse: Codable {
    let stream: String
    let data: BinanceKlineData
}

struct BinanceKlineData: Codable {
    let e: String // Event type
    let E: Int64  // Event time
    let s: String // Symbol
    let k: BinanceKlineDetail
}

struct BinanceKlineDetail: Codable {
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
