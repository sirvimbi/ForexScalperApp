// IGService.swift
import Foundation
import Starscream
import Combine

actor IGService {
    private var socket: WebSocket?
    private var isConnected = false
    private var symbols: [String] = []
    private var igSymbols: [String] = []
    private var timeframes: [String] = []
    private var onPriceReceived: ((String, String, IGTick) -> Void)?
    private var reconnectTask: Task<Void, Never>?
    private var lightstreamerSessionId: String?
    private var cst: String?
    private var xSecurityToken: String?
    
    @Published var connectionStatus: String = "IG Disconnected"
    
    // IG API Credentials
    private let apiKey = "23ca12562ccdbef0e9ab24d55c4f423b604bddd9"
    private let identifier = "kiptoo.bryan@gmail.com" // Add your IG identifier
    private let password = "Kenya@254" // Add your IG password
    
    // Convert symbol to IG format
    private func convertToIGSymbol(_ symbol: String) -> String {
        // IG uses different format for forex pairs
        let igMap: [String: String] = [
            // Forex pairs
            "EURUSD": "CS.D.EURUSD.TODAYIP",
            "GBPUSD": "CS.D.GBPUSD.TODAYIP",
            "USDJPY": "CS.D.USDJPY.TODAYIP",
            "USDCHF": "CS.D.USDCHF.TODAYIP",
            "CADCHF": "CS.D.CADCHF.TODAYIP",
            "TRYJPY": "CS.D.TRYJPY.TODAYIP",
            "EURCZK": "CS.D.EURCZK.TODAYIP",
            // Crypto on IG
            "BTCUSDT": "CS.D.BTCUSD.TODAYIP",
            "ETHUSDT": "CS.D.ETHUSD.TODAYIP",
            "XRPUSDT": "CS.D.XRPUSD.TODAYIP",
            "ADAUSDT": "CS.D.ADAUSD.TODAYIP",
            "DOGEUSDT": "CS.D.DOGEUSD.TODAYIP",
            "LTCUSDT": "CS.D.LTCUSD.TODAYIP",
            "BCHUSDT": "CS.D.BCHUSD.TODAYIP",
            "EOSUSDT": "CS.D.EOSUSD.TODAYIP",
            "XLMUSDT": "CS.D.XLMUSD.TODAYIP",
            "NEOUSDT": "CS.D.NEOUSD.TODAYIP",
            "BTGUSDT": "CS.D.BTGUSD.TODAYIP",
            // Existing pairs
            "EURUSDT": "CS.D.EURUSD.TODAYIP",
            "GBPUSDT": "CS.D.GBPUSD.TODAYIP",
            "AUDUSDT": "CS.D.AUDUSD.TODAYIP"
        ]
        
        return igMap[symbol] ?? "CS.D.\(symbol.replacingOccurrences(of: "USDT", with: "USD")).TODAYIP"
    }
    
    func connect(symbols: [String], timeframes: [String], onPrice: @escaping (String, String, IGTick) -> Void) {
        // Convert symbols to IG format
        self.igSymbols = symbols.map { convertToIGSymbol($0) }
        self.symbols = symbols // Keep original symbols for callbacks
        self.timeframes = timeframes
        self.onPriceReceived = onPrice
        
        Task {
            // First authenticate with IG
            await authenticate()
            // Then connect to Lightstreamer for real-time updates
            await connectLightstreamer()
        }
    }
    
    private func authenticate() async {
        print("🔐 Authenticating with IG...")
        
        let url = URL(string: "https://api.ig.com/gateway/deal/session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-IG-API-KEY")
        request.setValue("TESTER", forHTTPHeaderField: "_method") // Use DEMO or LIVE
        
        let body: [String: Any] = [
            "identifier": identifier,
            "password": password
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                self.cst = httpResponse.allHeaderFields["CST"] as? String
                self.xSecurityToken = httpResponse.allHeaderFields["X-SECURITY-TOKEN"] as? String
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sessionId = json["lightstreamerEndpoint"] as? String {
                    self.lightstreamerSessionId = sessionId
                    print("✅ IG authentication successful")
                }
            }
        } catch {
            print("❌ IG authentication failed: \(error)")
            connectionStatus = "IG Auth Failed"
        }
    }
    
    private func connectLightstreamer() async {
        // Lightstreamer connection URL
        guard let url = URL(string: "https://push.ig.com/lightstreamer") else {
            print("❌ Invalid Lightstreamer URL")
            return
        }
        
        print("🌐 Connecting to IG Lightstreamer...")
        connectionStatus = "IG Connecting..."
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        socket = WebSocket(request: request)
        
        socket?.onEvent = { [weak self] event in
            Task { [weak self] in
                await self?.handleLightstreamerEvent(event)
            }
        }
        
        socket?.connect()
    }
    
    private func handleLightstreamerEvent(_ event: WebSocketEvent) {
        switch event {
        case .connected:
            isConnected = true
            connectionStatus = "IG Connected"
            print("✅ IG Lightstreamer connected")
            subscribeToPrices()
            
        case .text(let text):
            parseLightstreamerMessage(text)
            
        case .disconnected:
            isConnected = false
            connectionStatus = "IG Disconnected"
            scheduleReconnect()
            
        case .error(let error):
            isConnected = false
            connectionStatus = "IG Error"
            print("❌ IG Lightstreamer error: \(error?.localizedDescription ?? "unknown")")
            scheduleReconnect()
            
        default:
            break
        }
    }
    
    private func subscribeToPrices() {
        guard isConnected, let sessionId = lightstreamerSessionId else { return }
        
        // Use igSymbols for subscription
        let subscribeMsg = [
            "type": "subscribe",
            "session": sessionId,
            "subscription": [
                "mode": "MERGE",
                "items": igSymbols.map { "L1:\($0)" },
                "fields": ["BID", "OFFER", "HIGH", "LOW", "CHANGE", "CHANGE_PCT"],
                "dataAdapter": "QUOTE_ADAPTER"
            ]
        ] as [String : Any]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: subscribeMsg),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            socket?.write(string: jsonString)
            print("📡 Subscribed to \(igSymbols.count) IG symbols")
        }
    }
    
    private func parseLightstreamerMessage(_ text: String) {
        struct IGUpdate: Decodable {
            let item: String
            let values: [String: String]
        }
        
        guard let data = text.data(using: .utf8),
              let update = try? JSONDecoder().decode(IGUpdate.self, from: data) else {
            return
        }
        
        if let bid = update.values["BID"],
           let offer = update.values["OFFER"],
           let bidValue = Double(bid),
           let offerValue = Double(offer) {
            
            let tick = IGTick(
                symbol: update.item,
                bid: bidValue,
                ask: offerValue,
                timestamp: Date()
            )
            
            // Find original symbol from IG symbol
            let originalSymbol = findOriginalSymbol(for: update.item)
            
            onPriceReceived?(originalSymbol, "tick", tick)
        }
    }
    
    private func findOriginalSymbol(for igSymbol: String) -> String {
        // Reverse mapping from IG format to original symbols
        let reverseMap: [String: String] = [
            "CS.D.EURUSD.TODAYIP": "EURUSD",
            "CS.D.GBPUSD.TODAYIP": "GBPUSD",
            "CS.D.USDJPY.TODAYIP": "USDJPY",
            "CS.D.USDCHF.TODAYIP": "USDCHF",
            "CS.D.CADCHF.TODAYIP": "CADCHF",
            "CS.D.TRYJPY.TODAYIP": "TRYJPY",
            "CS.D.EURCZK.TODAYIP": "EURCZK",
            "CS.D.BTCUSD.TODAYIP": "BTCUSDT",
            "CS.D.ETHUSD.TODAYIP": "ETHUSDT",
            "CS.D.XRPUSD.TODAYIP": "XRPUSDT",
            "CS.D.ADAUSD.TODAYIP": "ADAUSDT",
            "CS.D.DOGEUSD.TODAYIP": "DOGEUSDT",
            "CS.D.LTCUSD.TODAYIP": "LTCUSDT",
            "CS.D.BCHUSD.TODAYIP": "BCHUSDT",
            "CS.D.EOSUSD.TODAYIP": "EOSUSDT",
            "CS.D.XLMUSD.TODAYIP": "XLMUSDT",
            "CS.D.NEOUSD.TODAYIP": "NEOUSDT",
            "CS.D.BTGUSD.TODAYIP": "BTGUSDT"
        ]
        
        return reverseMap[igSymbol] ?? igSymbol
    }
    
    func fetchHistoricalData(symbol: String, resolution: String = "MINUTE", numPoints: Int = 200) async -> [IGKline]? {
        guard let cst = cst, let token = xSecurityToken else {
            print("❌ Not authenticated with IG")
            return nil
        }
        
        // Convert symbol to IG epic format
        let epic = convertToIGSymbol(symbol)
        
        let url = URL(string: "https://api.ig.com/gateway/deal/prices/\(epic)/\(resolution)/\(numPoints)")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-IG-API-KEY")
        request.setValue(cst, forHTTPHeaderField: "CST")
        request.setValue(token, forHTTPHeaderField: "X-SECURITY-TOKEN")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let prices = json["prices"] as? [[String: Any]] {
                
                var klines: [IGKline] = []
                for price in prices {
                    if let snapshot = price["snapshot"] as? [String: Any],
                       let open = snapshot["openPrice"] as? [String: Any],
                       let close = snapshot["closePrice"] as? [String: Any],
                       let high = snapshot["highPrice"] as? [String: Any],
                       let low = snapshot["lowPrice"] as? [String: Any],
                       let openBid = open["bid"] as? Double,
                       let closeBid = close["bid"] as? Double,
                       let highBid = high["bid"] as? Double,
                       let lowBid = low["bid"] as? Double,
                       let lastTradedVolume = snapshot["lastTradedVolume"] as? Int,
                       let snapshotTime = snapshot["snapshotTime"] as? String {
                        
                        let kline = IGKline(
                            open: openBid,
                            high: highBid,
                            low: lowBid,
                            close: closeBid,
                            volume: Double(lastTradedVolume),
                            timestamp: snapshotTime
                        )
                        klines.append(kline)
                    }
                }
                return klines
            }
        } catch {
            print("❌ Failed to fetch IG historical data: \(error)")
        }
        
        return nil
    }
    
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            print("🔄 Attempting to reconnect to IG...")
            await self?.connectLightstreamer()
        }
    }
    
    func disconnect() {
        print("🔌 Disconnecting IG Lightstreamer")
        reconnectTask?.cancel()
        socket?.disconnect()
        socket = nil
        connectionStatus = "IG Disconnected"
    }
}

// MARK: - IG Types
struct IGTick {
    let symbol: String
    let bid: Double
    let ask: Double
    let timestamp: Date
    
    var mid: Double { (bid + ask) / 2 }
}

struct IGKline {
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let timestamp: String
}
