// MT5Service.swift - MetaTrader 5 "God Mode" Integration
import Foundation

class MT5Service {
    static let shared = MT5Service()
    
    private var customBaseURL: String?
    private var customAuthToken: String?
    
    private var authBuffer: String {
        if let custom = customAuthToken { return "Bearer \(custom)" }
        let savedToken = UserDefaults.standard.string(forKey: "mt5AuthToken") ?? "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
        return savedToken.hasPrefix("Bearer ") ? savedToken : "Bearer \(savedToken)"
    }
    
    private var baseURL: String {
        if let custom = customBaseURL { return custom }
        let savedURL = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://localhost:8891"
        return savedURL.hasSuffix("/") ? String(savedURL.dropLast()) : savedURL
    }
    
    func setBaseURL(_ url: String) {
        self.customBaseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        print("🌐 MT5: Base URL set to \(self.customBaseURL!)")
    }
    
    func setAuthToken(_ token: String) {
        self.customAuthToken = token
        print("🔐 MT5: Auth token updated")
    }
    
    private init() {}
    
    // MARK: - Connection & Status
    
    func initialize(login: Int, password: String, server: String) async throws {
        // Try multiple possible endpoints for initialization to avoid 404
        // NOTE: Our current bridge implementation does NOT require initialization from the client side
        // as the EA handles the login. We will try it but not throw if it's a 404.
        let paths = ["/api/mt5/initialize", "/v1/initialize", "/initialize"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            let body: [String: Any] = [
                "login": login,
                "password": password,
                "server": server
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                print("🌐 MT5: Attempting optional initialization at \(url.absoluteString)...")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("✅ MT5: Initialization successful at \(path)")
                        return
                    } else if httpResponse.statusCode == 404 {
                        print("ℹ️ MT5: Path \(path) not found (404), trying next...")
                        continue
                    } else if httpResponse.statusCode == 403 {
                        print("❌ MT5: 403 Forbidden at \(path). Check Bearer token.")
                        throw TradingError.apiError("403 Forbidden: Check Auth Token")
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("❌ MT5: \(path) returned \(httpResponse.statusCode): \(errorMsg)")
                    }
                }
            } catch let error as TradingError {
                throw error
            } catch {
                print("⚠️ MT5: Failed to connect to \(path): \(error.localizedDescription)")
            }
        }
        
        print("ℹ️ MT5: Bridge does not have /initialize endpoint. Proceeding to status check...")
    }
    
    func checkConnection() async throws -> Bool {
        // We added a /v1/status endpoint to the bridge
        let paths = ["/v1/status", "/v1/account", "/status"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
                
                print("🔍 MT5: Checking connection at \(path)...")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if path.contains("status") {
                        let status = try JSONDecoder().decode(MT5StatusResponse.self, from: data)
                        if status.connected {
                            print("✅ MT5: Connected via \(url.absoluteString)")
                            return true
                        }
                    } else {
                        // For /v1/account, 200 means we're connected
                        print("✅ MT5: Connected via \(url.absoluteString)")
                        return true
                    }
                } else if let httpResponse = response as? HTTPURLResponse {
                    let errorMsg = String(data: data, encoding: .utf8) ?? ""
                    print("⚠️ MT5: \(path) returned \(httpResponse.statusCode): \(errorMsg)")
                }
            } catch {
                print("⚠️ MT5: Connection check failed for \(path): \(error.localizedDescription)")
                continue
            }
        }
        return false
    }
    
    // MARK: - Market Data (God Mode Charts)
    
    func getCandles(symbol: String, timeframe: String, count: Int = 1000) async throws -> [Kline] {
        // Clean symbol (remove slashes, e.g., EUR/USD -> EURUSD)
        let cleanSymbol = symbol.replacingOccurrences(of: "/", with: "")
        
        // Map timeframe to MT5 format (e.g., 1m -> M1)
        let mt5Timeframe: String
        switch timeframe.lowercased() {
        case "1m": mt5Timeframe = "M1"
        case "5m": mt5Timeframe = "M5"
        case "15m": mt5Timeframe = "M15"
        case "30m": mt5Timeframe = "M30"
        case "1h": mt5Timeframe = "H1"
        case "4h": mt5Timeframe = "H4"
        case "1d": mt5Timeframe = "D1"
        default: mt5Timeframe = timeframe.uppercased()
        }
        
        // Try paths: /v1/history/prices (matches bridge), /api/mt5/candles, /candles
        let paths = ["/v1/history/prices", "/api/mt5/candles", "/candles"]
        
        for path in paths {
            let urlString = "\(baseURL)\(path)?symbol=\(cleanSymbol)&time_frame=\(mt5Timeframe)&count=\(count)"
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
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
            } catch {
                continue
            }
        }
        
        throw TradingError.apiError("Failed to fetch candles from MT5")
    }
    
    // MARK: - Trading (God Mode Execution)
    
    func executeTrade(signal: Signal) async throws -> MT5TradeResult {
        // Clean symbol (remove slashes, e.g., EUR/USD -> EURUSD)
        let cleanSymbol = signal.symbol.replacingOccurrences(of: "/", with: "")
        
        // Try paths: /v1/order (matches bridge), /api/mt5/trade, /trade
        let paths = ["/v1/order", "/api/mt5/trade", "/trade"]
        var lastError: Error?
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            // MT5 precise options for God Mode - Matching nodejs bridge SendOrderRequest
            let body: [String: Any] = [
                "action": signal.executionMode?.rawValue.lowercased() ?? "market",
                "symbol": cleanSymbol,
                "order_type": signal.orderType?.rawValue.lowercased() ?? (signal.type == .buy ? "buy" : "sell"),
                "volume": signal.positionSize ?? signal.volume,
                "price": signal.price,
                "sl": signal.stopLoss ?? 0,
                "tp": signal.takeProfit ?? 0,
                "magic": signal.magicNumber ?? 888888,
                "comment": signal.comment ?? "GOD_MODE_SCALPER",
                "deviation": signal.deviation ?? 10,
                "type_filling": signal.filler?.rawValue.lowercased() ?? "ioc"
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        let tradeResult = try JSONDecoder().decode(MT5TradeResult.self, from: data)
                        if tradeResult.retcode != 10009 && tradeResult.retcode != 10008 {
                            throw TradingError.apiError("MT5 Execution Failed: Code \(tradeResult.retcode)")
                        }
                        return tradeResult
                    } else if httpResponse.statusCode == 404 {
                        continue
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                        lastError = TradingError.apiError("Status \(httpResponse.statusCode): \(errorMsg)")
                    }
                }
            } catch {
                lastError = error
            }
        }
        
        throw lastError ?? TradingError.apiError("MT5 Execution Failed")
    }
    
    // MARK: - Order History & Positions
    
    func getOpenPositions() async throws -> [MT5Position] {
        // Try paths: /v1/order/list, /api/mt5/positions, /positions
        let paths = ["/v1/order/list", "/api/mt5/positions", "/positions"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return try JSONDecoder().decode([MT5Position].self, from: data)
                }
            } catch {
                continue
            }
        }
        
        throw TradingError.apiError("Failed to fetch positions")
    }
    
    func getAccountInfo() async throws -> MT5AccountInfo {
        let paths = ["/v1/account", "/api/mt5/account", "/account"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return try JSONDecoder().decode(MT5AccountInfo.self, from: data)
                }
            } catch {
                continue
            }
        }
        
        throw TradingError.apiError("Failed to fetch account info")
    }
    
    func closePosition(ticket: Int) async throws -> Bool {
        let paths = ["/v1/order/close", "/api/mt5/close", "/close"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["ticket": ticket])
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(MT5TradeResult.self, from: data)
                    return result.retcode == 10009
                }
            } catch {
                continue
            }
        }
        
        return false
    }
}

// MARK: - Internal MT5 Helper Models
struct MT5StatusResponse: Codable {
    let connected: Bool
    let status: String?
    let message: String?
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
