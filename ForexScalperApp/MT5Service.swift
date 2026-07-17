// MT5Service.swift - MetaTrader 5 "God Mode" Integration
import Foundation

class MT5Service {
    static let shared = MT5Service()
    
    private var baseURL: String {
        let savedURL = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://localhost:5000"
        return "\(savedURL)/api/mt5"
    }
    
    private init() {}
    
    // MARK: - Connection & Status
    
    func checkConnection() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/status") else { throw TradingError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(MT5StatusResponse.self, from: data)
        return response.connected
    }
    
    // MARK: - Market Data (God Mode Charts)
    
    func getCandles(symbol: String, timeframe: String, count: Int = 1000) async throws -> [Kline] {
        guard let url = URL(string: "\(baseURL)/candles?symbol=\(symbol)&timeframe=\(timeframe)&count=\(count)") else {
            throw TradingError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let mt5Candles = try JSONDecoder().decode([MT5Candle].self, from: data)
        
        return mt5Candles.map { candle in
            Kline(
                open: candle.open,
                high: candle.high,
                low: candle.low,
                close: candle.close,
                volume: candle.tick_volume,
                closeTime: Int(candle.time)
            )
        }
    }
    
    // MARK: - Trading (God Mode Execution)
    
    func executeTrade(signal: Signal) async throws -> MT5TradeResult {
        guard let url = URL(string: "\(baseURL)/trade") else { throw TradingError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // MT5 precise options for God Mode
        let body: [String: Any] = [
            "action": "market",
            "symbol": signal.symbol,
            "type": signal.type == .buy ? "BUY" : "SELL",
            "volume": signal.positionSize ?? 0.1,
            "price": signal.price,
            "sl": signal.stopLoss ?? 0,
            "tp": signal.takeProfit ?? 0,
            "magic": signal.magicNumber ?? 123456,
            "comment": signal.comment ?? "Scalper God Mode",
            "deviation": signal.deviation ?? 10,
            "filler": signal.filler ?? "IOC" // Immediate or Cancel for precise execution
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw TradingError.apiError("MT5 Bridge returned status \(httpResponse.statusCode)")
        }
        
        let tradeResult = try JSONDecoder().decode(MT5TradeResult.self, from: data)
        
        if tradeResult.retcode != 10009 && tradeResult.retcode != 10008 { // 10009 is TRADE_RETCODE_DONE
            throw TradingError.apiError("MT5 Execution Failed: Code \(tradeResult.retcode)")
        }
        
        return tradeResult
    }
    
    // MARK: - Order History & Positions
    
    func getOpenPositions() async throws -> [MT5Position] {
        guard let url = URL(string: "\(baseURL)/positions") else { throw TradingError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([MT5Position].self, from: data)
    }
    
    func getAccountInfo() async throws -> MT5AccountInfo {
        guard let url = URL(string: "\(baseURL)/account") else { throw TradingError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(MT5AccountInfo.self, from: data)
    }
    
    func closePosition(ticket: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/close") else { throw TradingError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ticket": ticket])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(MT5TradeResult.self, from: data)
        return result.retcode == 10009
    }
}

// MARK: - Internal MT5 Helper Models
struct MT5StatusResponse: Codable {
    let connected: Bool
    let terminal: String
}

struct MT5Candle: Codable {
    let time: TimeInterval
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let tick_volume: Double
    let spread: Int
    let real_volume: Double
}
