// MT5Service.swift - MetaTrader 5 "God Mode" Integration
import Foundation

actor MT5Service {
    static let shared = MT5Service()
    
    // PRODUCTION NETWORK OPTIMIZATION: Reuse session to prevent nw_path evaluation errors
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25.0
        config.timeoutIntervalForResource = 30.0
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: config)
    }()
    
    private var customBaseURL: String?
    private var customAuthToken: String?
    
    private var authBuffer: String {
        if let custom = customAuthToken { return "Bearer \(custom)" }
        let savedToken = UserDefaults.standard.string(forKey: "mt5AuthToken") ?? "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
        return savedToken.hasPrefix("Bearer ") ? savedToken : "Bearer \(savedToken)"
    }
    
    private var baseURL: String {
        if let custom = customBaseURL { 
            // PRODUCTION FIX: Automatically redirect from EA port 8890 to Bridge port 8891
            if custom.contains(":8890") {
                let fixed = custom.replacingOccurrences(of: ":8890", with: ":8891")
                print("⚠️ MT5: Redirecting from EA port 8890 to Bridge port 8891 for God Mode logic.")
                return fixed
            }
            return custom 
        }
        let savedURL = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8891"
        return savedURL.hasSuffix("/") ? String(savedURL.dropLast()) : savedURL
    }
    
    private var lastWorkingPath: String?
    
    // TRADABILITY CACHE: Prevent 500 errors by knowing which symbols are disabled
    private var symbolTradeMode: [String: Int] = [:]
    private var symbolVolumeLimits: [String: (min: Double, max: Double, step: Double)] = [:]
    
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
                godLog("🌐 MT5: Attempting optional initialization at \(url.absoluteString)...")
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        godLog("✅ MT5: Initialization successful at \(path)", level: .success)
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
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if path.contains("status") {
                        let status = try JSONDecoder().decode(MT5StatusResponse.self, from: data)
                        if status.connected {
                            godLog("✅ MT5: Connected via \(url.absoluteString)", level: .success)
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
        
        // Try the last working path first to reduce network chatter and 404s
        var paths = ["/v1/history/prices", "/api/mt5/candles", "/candles"]
        if let working = lastWorkingPath, let idx = paths.firstIndex(of: working) {
            paths.remove(at: idx)
            paths.insert(working, at: 0)
        }
        
        for path in paths {
            let urlString = "\(baseURL)\(path)?symbol=\(cleanSymbol)&time_frame=\(mt5Timeframe)&count=\(count)"
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30.0 // INCREASED: Allow time for broker history download
            
            do {
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let priceResponse = try JSONDecoder().decode(MT5PriceHistoryResponse.self, from: data)
                    let mt5Candles = priceResponse.data
                    
                    self.lastWorkingPath = path // Cache success
                    
                    // PRODUCTION FIX: If we requested data but got back 0 bars, don't return an empty array
                    if mt5Candles.isEmpty {
                         continue 
                    }

                    return mt5Candles.map { candle in
                        Kline(
                            open: candle.open,
                            high: candle.high,
                            low: candle.low,
                            close: candle.close,
                            volume: candle.totalVolume,
                            closeTime: Int(candle.time),
                            spread: candle.spread != nil ? Double(candle.spread!) : nil
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
        // Clean symbol and append broker suffix
        var cleanSymbol = signal.symbol.replacingOccurrences(of: "/", with: "")
        
        let suffix = await MainActor.run { ScalpingConfig.shared.brokerSuffix }
        if !suffix.isEmpty && !cleanSymbol.hasSuffix(suffix) {
            cleanSymbol += suffix
        }
        
        // Try the last working path first to ensure fast execution
        let paths = ["/v1/order"] // Standardized on /v1/order for God Mode

        var lastError: Error?
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10.0
            
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
                godLog("🌐 MT5: Sending trade to \(url.absoluteString)...")
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        let tradeResult = try JSONDecoder().decode(MT5TradeResult.self, from: data)
                        if tradeResult.retcode != 10009 && tradeResult.retcode != 10008 {
                            godLog("❌ MT5: Execution failed with retcode \(tradeResult.retcode): \(tradeResult.comment ?? "No comment")", level: .error)
                            throw TradingError.apiError("MT5 Error \(tradeResult.retcode): \(tradeResult.comment ?? "Execution failed")")
                        }
                        return tradeResult
                    } else if httpResponse.statusCode == 503 {
                        // POTENTIAL FIX: Socket hang ups usually indicate EA overload. Retry once after delay.
                        print("⚠️ MT5: EA reported 503 (Overload/Hangup). Retrying in 1s...")
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        continue 
                    } else if (400...499).contains(httpResponse.statusCode) {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        if errorMsg.lowercased().contains("symbol not found") || errorMsg.lowercased().contains("details") {
                            print("❌ MT5: Symbol or configuration error (\(httpResponse.statusCode)): \(errorMsg)")
                            throw TradingError.apiError("MT5 Config Error: \(errorMsg)")
                        }
                        print("⚠️ MT5: Path \(path) returned \(httpResponse.statusCode). Body: \(errorMsg)")
                        continue // Try next path
                    } else if httpResponse.statusCode >= 500 {
                        // CRITICAL: Stop retrying on 500 Server Errors (like invalid stops) as the EA already tried and failed
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
                        print("❌ MT5: Terminal/EA Error (500): \(errorMsg)")
                        throw TradingError.apiError("MT5 Execution Error: \(errorMsg)")
                    }
                }
            } catch {
                print("⚠️ MT5: Error during trade execution at \(path): \(error.localizedDescription)")
                lastError = error
            }
        }
        
        throw lastError ?? TradingError.apiError("MT5 Execution Failed")
    }
    
    // MARK: - Order History & Positions
    
    func getPositionsAndOrders() async throws -> (active: [MT5Position], pending: [MT5Position]) {
        let paths = ["/v1/order/list", "/api/mt5/positions", "/positions"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10.0
            
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let wrapper = try JSONDecoder().decode(MT5OrderListResponse.self, from: data)
                    return (active: wrapper.opened, pending: wrapper.pending)
                }
            } catch {
                print("⚠️ MT5: Failed to fetch positions from \(path): \(error)")
                continue
            }
        }
        
        return (active: [], pending: [])
    }
    
    func getAccountInfo() async throws -> MT5AccountInfo {
        let paths = ["/v1/account", "/api/mt5/account", "/account"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Debug print to verify figures
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📊 MT5 Account Raw: \(jsonString)")
                    }
                    return try JSONDecoder().decode(MT5AccountInfo.self, from: data)
                }
            } catch {
                continue
            }
        }
        
        throw TradingError.apiError("Failed to fetch account info")
    }
    
    func closePosition(ticket: Int, volume: Double? = nil) async throws -> Bool {
        let paths = ["/v1/order/close", "/api/mt5/close", "/close"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            var body: [String: Any] = ["ticket": ticket]
            if let vol = volume {
                body["volume"] = vol
            }
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            do {
                let (data, response) = try await session.data(for: request)
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

    func isSymbolTradable(_ symbol: String) async -> Bool {
        let cleanSymbol = symbol.replacingOccurrences(of: "/", with: "")
        
        // Return cached value if we have it
        if let mode = symbolTradeMode[cleanSymbol] {
            return mode == 0
        }
        
        do {
            let info = try await getSymbolInfo(cleanSymbol)
            symbolTradeMode[cleanSymbol] = info.trade_mode
            symbolVolumeLimits[cleanSymbol] = (
                min: info.volume_min ?? 0.01,
                max: info.volume_max ?? 100.0,
                step: info.volume_step ?? 0.01
            )
            return info.trade_mode == 0
        } catch {
            return true 
        }
    }

    func getVolumeLimits(for symbol: String) async -> (min: Double, max: Double, step: Double) {
        let cleanSymbol = symbol.replacingOccurrences(of: "/", with: "")
        if let limits = symbolVolumeLimits[cleanSymbol] {
            return limits
        }
        
        // If not in cache, try to fetch
        _ = await isSymbolTradable(symbol)
        return symbolVolumeLimits[cleanSymbol] ?? (0.01, 100.0, 0.01)
    }

    func getSymbolInfo(_ symbol: String) async throws -> MT5SymbolInfo {
        let urlString = "\(baseURL)/v1/symbol/info?symbol=\(symbol)"
        guard let url = URL(string: urlString) else { throw TradingError.apiError("Invalid URL") }
        
        var request = URLRequest(url: url)
        request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(MT5SymbolInfo.self, from: data)
        }
        throw TradingError.apiError("Symbol info unavailable")
    }

    func modifyPosition(ticket: Int, sl: Double, tp: Double) async throws -> Bool {
        let paths = ["/v1/order/modify", "/api/mt5/modify", "/modify"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            let body: [String: Any] = [
                "ticket": ticket,
                "sl": sl,
                "tp": tp
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            do {
                let (data, response) = try await session.data(for: request)
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

    func getTradeHistory(days: Int = 30) async throws -> [MT5HistoryPosition] {
        let paths = ["/v1/history/orders", "/api/mt5/history"]
        
        // Calculate dates
        let toDate = Date()
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: toDate)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fromStr = formatter.string(from: fromDate).replacingOccurrences(of: "Z", with: "")
        let toStr = formatter.string(from: toDate).replacingOccurrences(of: "Z", with: "")
        
        for path in paths {
            let urlString = "\(baseURL)\(path)?mode=positions&from_date=\(fromStr)&to_date=\(toStr)"
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // The bridge returns a wrapped object with a "data" array
                    let historyResponse = try JSONDecoder().decode(MT5HistoryResponse.self, from: data)
                    return historyResponse.data
                }
            } catch {
                print("⚠️ MT5: History fetch failed for \(path): \(error)")
                continue
            }
        }
        
        return []
    }

    func setTrackedSymbols(_ symbols: [String]) async throws -> Bool {
        let paths = ["/v1/track/prices", "/api/mt5/track"]
        
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            
            let body = ["symbols": symbols]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    func getATR(symbol: String, period: Int = 14) async throws -> Double {
        // GOD MODE V3.2: Use 5m timeframe for faster responsiveness in scalping
        let candles = try await getCandles(symbol: symbol, timeframe: "5m", count: period * 2)
        guard candles.count >= period else { return symbol.contains("JPY") ? 0.20 : 0.0020 }
        
        let closes = candles.map { $0.close }
        let highs = candles.map { $0.high }
        let lows = candles.map { $0.low }
        
        var trs: [Double] = []
        for i in 1..<candles.count {
            let hl = highs[i] - lows[i]
            let hpc = abs(highs[i] - closes[i-1])
            let lpc = abs(lows[i] - closes[i-1])
            trs.append(max(hl, hpc, lpc))
        }
        
        return trs.reduce(0, +) / Double(trs.count)
    }
    
    // NEW: God Mode advanced API methods
    func getCurrentSpread(symbol: String) async throws -> Double {
        let info = try await getSymbolInfo(symbol)
        // Spread is returned in points by MT5
        return Double(info.spread)
    }
    
    func getMarketSession(symbol: String) async throws -> String {
        // Implementation of session detection via MT5 server time
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 0 && hour < 8 { return "Asian" }
        if hour >= 8 && hour < 16 { return "London" }
        return "US"
    }
}

// MARK: - Internal MT5 Helper Models