import Foundation
import Starscream
import Combine

actor BinanceService {
    private var socket: WebSocket?
    private var isConnected = false
    private var symbols: [String] = []
    private var timeframes: [String] = []
    private var onKlineReceived: ((String, String, Kline) -> Void)?
    private var reconnectTask: Task<Void, Never>?
    private var lastKlineTime: [String: Date] = [:]
    private var klineCounter = 0
    private var pingTimer: Task<Void, Never>?
    
    @Published var connectionStatus: String = "Disconnected"
    private var statusContinuation: AsyncStream<String>.Continuation?
    
    // Add symbol conversion for forex pairs
    private func convertToBinanceSymbol(_ symbol: String) -> String {
        // Handle forex pairs (convert to Binance format)
        let forexMap: [String: String] = [
            "EURUSD": "EURUSDT",     // EUR/USD -> EURUSDT on Binance
            "GBPUSD": "GBPUSDT",     // GBP/USD -> GBPUSDT on Binance
            "USDJPY": "USDJPYUSDT",  // USD/JPY -> USDJPYUSDT on Binance
            "USDCHF": "USDCHFUSDT",  // USD/CHF -> USDCHFUSDT on Binance
            "CADCHF": "CADCHFUSDT",  // CAD/CHF -> CADCHFUSDT on Binance
            "TRYJPY": "TRYJPYUSDT",  // TRY/JPY -> TRYJPYUSDT on Binance
            "EURCZK": "EURCZKUSDT",   // EUR/CZK -> EURCZKUSDT on Binance
            // Crypto pairs
            "XRPUSDT": "XRPUSDT",
            "ADAUSDT": "ADAUSDT",
            "DOGEUSDT": "DOGEUSDT",
            "LTCUSDT": "LTCUSDT",
            "BCHUSDT": "BCHUSDT",
            "EOSUSDT": "EOSUSDT",
            "XLMUSDT": "XLMUSDT",
            "NEOUSDT": "NEOUSDT",
            "BTGUSDT": "BTGUSDT"
        ]
        
        // If it's a forex pair, convert to Binance format
        if let binanceSymbol = forexMap[symbol] {
            return binanceSymbol
        }
        
        // For crypto pairs, ensure they have USDT suffix if they don't already
        if !symbol.hasSuffix("USDT") && !symbol.contains("/") {
            return symbol + "USDT"
        }
        
        // Remove any slashes if present
        return symbol.replacingOccurrences(of: "/", with: "")
    }
    
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
    
    private func fetchHistoricalData() async {
        print("📥 Fetching historical data for \(symbols.count) symbols...")
        
        for symbol in symbols {
            for timeframe in timeframes {
                await fetchKlines(symbol: symbol, interval: convertToBinanceInterval(timeframe), limit: 200)
                // Add a small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second
            }
        }
        
        print("✅ Historical data fetch complete")
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
    
    private func fetchKlines(symbol: String, interval: String, limit: Int) async {
        let binanceSymbol = convertToBinanceSymbol(symbol)
        let urlString = "https://api.binance.com/api/v3/klines?symbol=\(binanceSymbol)&interval=\(interval)&limit=\(limit)"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for historical data: \(symbol) \(interval)")
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    print("📥 Received \(jsonArray.count) historical \(interval) candles for \(symbol) (Binance symbol: \(binanceSymbol))")
                    
                    for item in jsonArray {
                        guard item.count >= 11,
                              let openTime = item[0] as? Int64,
                              let closeTime = item[6] as? Int64,
                              let open = Double(item[1] as? String ?? "0"),
                              let high = Double(item[2] as? String ?? "0"),
                              let low = Double(item[3] as? String ?? "0"),
                              let close = Double(item[4] as? String ?? "0"),
                              let volume = Double(item[5] as? String ?? "0") else {
                            continue
                        }
                        
                        let kline = Kline(
                            open: open,
                            high: high,
                            low: low,
                            close: close,
                            volume: volume,
                            closeTime: Int(closeTime)
                        )
                        
                        // Process historical kline - use original symbol for callback
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
        
        // Use the correct WebSocket URL format
        guard let url = URL(string: "wss://stream.binance.com:9443/stream?streams=\(streams)") else {
            print("❌ Invalid WebSocket URL")
            connectionStatus = "Invalid URL"
            return
        }
        
        print("🌐 Connecting to Binance WebSocket: \(url)")
        connectionStatus = "Connecting..."
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        socket = WebSocket(request: request)
        
        socket?.onEvent = { [weak self] event in
            Task { [weak self] in
                await self?.handleWebSocketEvent(event)
            }
        }
        
        socket?.connect()
    }
    
    private func startPingTimer() {
        pingTimer?.cancel()
        pingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                await self?.sendPing()
            }
        }
    }
    
    private func sendPing() {
        if isConnected {
            socket?.write(ping: Data())
        }
    }
    
    private func handleWebSocketEvent(_ event: WebSocketEvent) {
        switch event {
        case .connected(let headers):
            isConnected = true
            connectionStatus = "Connected"
            print("✅ WebSocket connected for real-time updates")
            print("📡 Now monitoring \(symbols.count) symbols in real-time")
            
        case .disconnected(let reason, let code):
            isConnected = false
            connectionStatus = "Disconnected"
            print("❌ WebSocket disconnected: \(reason) (\(code))")
            scheduleReconnect()
            
        case .text(let text):
            parseKlineMessage(text)
            
        case .binary(let data):
            print("📦 Received binary data: \(data.count) bytes")
            
        case .pong:
            print("🏓 Received pong")
            
        case .ping(let data):
            // Respond to ping to keep connection alive
            socket?.write(pong: data ?? Data())
            
        case .viabilityChanged(let viable):
            if !viable && isConnected {
                connectionStatus = "Connection unstable"
                scheduleReconnect()
            }
            
        case .reconnectSuggested(let shouldReconnect):
            if shouldReconnect {
                connectionStatus = "Reconnecting..."
                scheduleReconnect()
            }
            
        case .cancelled:
            isConnected = false
            connectionStatus = "Cancelled"
            scheduleReconnect()
            
        case .error(let error):
            isConnected = false
            connectionStatus = "Error: \(error?.localizedDescription ?? "unknown")"
            print("❌ WebSocket error: \(error?.localizedDescription ?? "unknown")")
            scheduleReconnect()
            
        case .peerClosed:
            isConnected = false
            connectionStatus = "Peer closed"
            scheduleReconnect()
        }
    }
    
    private func parseKlineMessage(_ text: String) {
        struct StreamMessage: Decodable {
            let stream: String
            let data: KlineData
        }
        struct KlineData: Decodable {
            let k: KlineDetail
        }
        struct KlineDetail: Decodable {
            let t: Int      // start time
            let T: Int      // close time
            let s: String   // symbol
            let i: String   // interval
            let o: String   // open
            let h: String   // high
            let l: String   // low
            let c: String   // close
            let v: String   // volume
            let x: Bool     // is closed
        }
        
        guard let data = try? JSONDecoder().decode(StreamMessage.self, from: Data(text.utf8)) else {
            return
        }
        
        let detail = data.data.k
        // Need to map back to original symbol
        let binanceSymbol = detail.s.uppercased()
        let originalSymbol = findOriginalSymbol(for: binanceSymbol)
        let timeframe = convertFromBinanceInterval(detail.i)
        
        klineCounter += 1
        if klineCounter % 10 == 0 {
            print("📊 Real-time kline #\(klineCounter) for \(originalSymbol) \(timeframe)")
        }
        
        // Only process closed klines
        if detail.x {
            guard let open = Double(detail.o),
                  let high = Double(detail.h),
                  let low = Double(detail.l),
                  let close = Double(detail.c),
                  let volume = Double(detail.v) else {
                return
            }
            
            let kline = Kline(
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                closeTime: detail.T
            )
            
            onKlineReceived?(originalSymbol, timeframe, kline)
        }
    }
    
    private func findOriginalSymbol(for binanceSymbol: String) -> String {
        // Reverse mapping from Binance format to original symbols
        let reverseMap: [String: String] = [
            "EURUSDT": "EURUSD",
            "GBPUSDT": "GBPUSD",
            "USDJPYUSDT": "USDJPY",
            "USDCHFUSDT": "USDCHF",
            "CADCHFUSDT": "CADCHF",
            "TRYJPYUSDT": "TRYJPY",
            "EURCZKUSDT": "EURCZK"
        ]
        
        // If it's a forex pair, return the original format
        if let original = reverseMap[binanceSymbol] {
            return original
        }
        
        // For crypto, return as is (they already have USDT)
        return binanceSymbol
    }
    
    private func convertFromBinanceInterval(_ interval: String) -> String {
        switch interval {
        case "1m": return "1m"
        case "5m": return "5m"
        case "15m": return "15m"
        case "30m": return "30m"
        case "1h": return "1h"
        case "4h": return "4h"
        case "1d": return "1d"
        default: return interval
        }
    }
    
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            print("🔄 Attempting to reconnect...")
            await self?.connectWebSocket()
        }
    }
    
    func disconnect() {
        print("🔌 Disconnecting WebSocket")
        pingTimer?.cancel()
        reconnectTask?.cancel()
        socket?.disconnect()
        socket = nil
        connectionStatus = "Disconnected"
    }
}
