// MT5Service.swift - MetaTrader 5 "God Mode" Integration
import Foundation

actor MT5Service {
    static let shared = MT5Service()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 45.0
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: config)
    }()

    private nonisolated let decoder = JSONDecoder()
    private var customBaseURL: String?
    private var customAuthToken: String?

    private var authBuffer: String {
        if let custom = customAuthToken { return "Bearer \(custom)" }
        let savedToken = UserDefaults.standard.string(forKey: "mt5AuthToken") ?? "al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY"
        return savedToken.hasPrefix("Bearer ") ? savedToken : "Bearer \(savedToken)"
    }

    private var baseURL: String {
        let raw: String
        if let custom = customBaseURL {
            raw = custom
        } else {
            raw = UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
        }
        var cleaned = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        if cleaned.contains(":8891") {
            cleaned = cleaned.replacingOccurrences(of: ":8891", with: ":8890")
        }
        return cleaned
    }

    private var lastWorkingPath: String?
    private var symbolTradeMode: [String: Int] = [:]
    private var symbolVolumeLimits: [String: (min: Double, max: Double, step: Double)] = [:]

    // MARK: - Connection Status
    private var _isConnected = false
    var isConnected: Bool { _isConnected }

    private var lastRequestTime: Date?
    private let minimumInterval: TimeInterval = 0.1

    private func waitForRateLimit() async {
        let now = Date()
        if let last = lastRequestTime {
            let waitTime = minimumInterval - now.timeIntervalSince(last)
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func rateLimitedRequest<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        await waitForRateLimit()
        return try await operation()
    }

    func setBaseURL(_ url: String) {
        self.customBaseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        godLog("🌐 MT5: Base URL set to \(self.customBaseURL!)", level: .diagnostic)
    }

    func setAuthToken(_ token: String) {
        self.customAuthToken = token
        godLog("🔐 MT5: Auth token updated", level: .diagnostic)
    }

    private init() {}

    // MARK: - Connection & Status

    func initialize(login: Int, password: String, server: String) async throws {
        let paths = ["/api/mt5/initialize", "/v1/initialize", "/initialize"]

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "login": login,
                "password": password,
                "server": server
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                godLog("🌐 MT5: Initializing EA at \(path)...", level: .diagnostic)

                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        godLog("✅ MT5: Initialization successful", level: .success)
                        _isConnected = true
                        return
                    } else if httpResponse.statusCode == 404 {
                        godLog("ℹ️ MT5: \(path) not found, trying next...", level: .diagnostic)
                        continue
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                        godLog("⚠️ MT5: \(path) returned \(httpResponse.statusCode): \(errorMsg)", level: .warning)
                    }
                }
            } catch {
                godLog("⚠️ MT5: Failed to initialize at \(path): \(error.localizedDescription)", level: .warning)
            }
        }

        _ = try await checkConnection()
    }

    func checkConnection() async throws -> Bool {
        let paths = ["/v1/status", "/v1/account", "/status"]
        var lastError: Error?

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.setValue(authBuffer, forHTTPHeaderField: "Authorization")

                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if path.contains("status") {
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let connected = json["connected"] as? Bool {
                                _isConnected = connected
                                if connected {
                                    godLog("✅ MT5: Connected via \(url.absoluteString)", level: .success)
                                } else {
                                    godLog("⚠️ MT5: Bridge online but EA not connected to account", level: .warning)
                                }
                                return _isConnected
                            }
                            continue
                        } else {
                            _isConnected = true
                            godLog("✅ MT5: Connected via \(url.absoluteString)", level: .success)
                            return true
                        }
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        godLog("❌ MT5: Authentication failed at \(path)", level: .error)
                        throw TradingError.apiError("Authentication failed - check API token")
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        godLog("⚠️ MT5: \(path) returned \(httpResponse.statusCode): \(errorMsg)", level: .warning)
                    }
                }
            } catch {
                lastError = error
                godLog("⚠️ MT5: Connection check failed for \(path): \(error.localizedDescription)", level: .warning)
                continue
            }
        }

        do {
            let _ = try await getAccountInfo()
            _isConnected = true
            godLog("✅ MT5: Connected (verified via account info)", level: .success)
            return true
        } catch {
            godLog("❌ MT5: Not connected - \(error.localizedDescription)", level: .error)
            _isConnected = false
        }

        throw lastError ?? TradingError.apiError("MT5 connection failed")
    }

    // MARK: - Market Data

    func getCandles(symbol: String, timeframe: String, count: Int = 1000) async throws -> [Kline] {
        return try await rateLimitedRequest {
            let cleanSymbol = symbol
                .replacingOccurrences(of: "/", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let mt5Timeframe: String
            switch timeframe.lowercased() {
            case "1m", "m1": mt5Timeframe = "M1"
            case "5m", "m5": mt5Timeframe = "M5"
            case "15m", "m15": mt5Timeframe = "M15"
            case "30m", "m30": mt5Timeframe = "M30"
            case "1h", "h1": mt5Timeframe = "H1"
            case "4h", "h4": mt5Timeframe = "H4"
            case "1d", "d1": mt5Timeframe = "D1"
            case "1w", "w1": mt5Timeframe = "W1"
            default: mt5Timeframe = timeframe.uppercased()
            }

            let safeCount = max(1, min(count, 5000))
            var paths = ["/v1/history/prices", "/api/mt5/candles", "/candles"]
            if let working = self.lastWorkingPath, let idx = paths.firstIndex(of: working) {
                paths.remove(at: idx)
                paths.insert(working, at: 0)
            }

            for path in paths {
                guard var components = URLComponents(string: "\(self.baseURL)\(path)") else { continue }
                components.queryItems = [
                    URLQueryItem(name: "symbol", value: cleanSymbol),
                    URLQueryItem(name: "time_frame", value: mt5Timeframe),
                    URLQueryItem(name: "count", value: String(safeCount))
                ]
                guard let url = components.url else { continue }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(self.authBuffer, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 30.0

                do {
                    let (data, response) = try await self.session.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else { continue }

                    if httpResponse.statusCode == 404 { continue }
                    if httpResponse.statusCode == 503 {
                        try? await Task.sleep(nanoseconds: 750_000_000)
                        continue
                    }
                    guard httpResponse.statusCode == 200 else {
                        let body = String(data: data, encoding: .utf8) ?? ""
                        godLog("⚠️ MT5: Candle endpoint \(path) returned \(httpResponse.statusCode): \(body.prefix(500))", level: .warning)
                        continue
                    }

                    guard let root = try? JSONSerialization.jsonObject(with: data) else {
                        godLog("⚠️ MT5: Invalid JSON for \(cleanSymbol) \(timeframe)", level: .warning)
                        continue
                    }

                    let rawItems: [[String: Any]]
                    if let object = root as? [String: Any] {
                        rawItems =
                            (object["data"] as? [[String: Any]]) ??
                            (object["candles"] as? [[String: Any]]) ??
                            (object["rates"] as? [[String: Any]]) ??
                            (object["items"] as? [[String: Any]]) ?? []
                    } else if let array = root as? [[String: Any]] {
                        rawItems = array
                    } else {
                        rawItems = []
                    }

                    let candles: [Kline] = rawItems.compactMap { dict in
                        guard
                            let time = Self.number(dict["time"] ?? dict["timestamp"] ?? dict["time_stamp"]),
                            let open = Self.number(dict["open"] ?? dict["o"]),
                            let high = Self.number(dict["high"] ?? dict["h"]),
                            let low = Self.number(dict["low"] ?? dict["l"]),
                            let close = Self.number(dict["close"] ?? dict["c"])
                        else { return nil }

                        let volume = Self.number(dict["volume"] ?? dict["tick_volume"] ?? dict["real_volume"] ?? dict["v"]) ?? 0
                        let spread = Self.number(dict["spread"])
                        let seconds = time > 10_000_000_000 ? time / 1000.0 : time

                        return Kline(
                            open: open,
                            high: high,
                            low: low,
                            close: close,
                            volume: volume,
                            closeTime: Int(seconds),
                            spread: spread,
                            isClosed: true
                        )
                    }

                    if !candles.isEmpty {
                        self.lastWorkingPath = path
                        godLog("📥 Received \(candles.count) MT5 \(mt5Timeframe) candles for \(cleanSymbol)", level: .info)
                        return candles.sorted { $0.closeTime < $1.closeTime }
                    }

                    let body = String(data: data, encoding: .utf8) ?? ""
                    godLog("⚠️ MT5: No candles parsed for \(cleanSymbol) \(timeframe). Response: \(body.prefix(700))", level: .warning)
                } catch {
                    godLog("⚠️ MT5: Candle fetch failed for \(path): \(error.localizedDescription)", level: .warning)
                    continue
                }
            }

            return []
        }
    }

    // MARK: - Account Info

    func getAccountInfo() async throws -> MT5AccountInfo {
        let paths = ["/v1/account", "/api/mt5/account", "/account"]

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10.0

            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if json["balance"] != nil || json["equity"] != nil {
                                let account = try decoder.decode(MT5AccountInfo.self, from: data)
                                godLog("💰 MT5 Account: Balance \(account.balance), Equity \(account.equity)", level: .info)
                                _isConnected = true
                                return account
                            } else if let accountData = json["data"] as? [String: Any] {
                                let accountDataJson = try JSONSerialization.data(withJSONObject: accountData)
                                let account = try decoder.decode(MT5AccountInfo.self, from: accountDataJson)
                                godLog("💰 MT5 Account: Balance \(account.balance), Equity \(account.equity)", level: .info)
                                _isConnected = true
                                return account
                            }
                        }

                        do {
                            let account = try decoder.decode(MT5AccountInfo.self, from: data)
                            godLog("💰 MT5 Account: Balance \(account.balance), Equity \(account.equity)", level: .info)
                            _isConnected = true
                            return account
                        } catch {
                            godLog("⚠️ MT5: Failed to decode account info at \(path): \(error)", level: .warning)
                        }
                    } else if httpResponse.statusCode == 404 {
                        continue
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        godLog("⚠️ MT5: Account fetch failed at \(path): \(httpResponse.statusCode) - \(errorMsg)", level: .warning)
                    }
                }
            } catch {
                godLog("⚠️ MT5: Account fetch error at \(path): \(error.localizedDescription)", level: .warning)
                continue
            }
        }

        godLog("⚠️ MT5: Using default account info (fetch failed)", level: .warning)
        return MT5AccountInfo(
            login: 0,
            balance: 10000,
            equity: 10000,
            margin: 0,
            margin_free: 10000,
            profit: 0,
            currency: "USD",
            server: "Unknown",
            algo_trading_enabled: 1
        )
    }

    // MARK: - Positions & Orders

    func getPositionsAndOrders() async throws -> (active: [MT5Position], pending: [MT5Position]) {
        let paths = ["/v1/order/list", "/api/mt5/positions", "/positions"]

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10.0

            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            // Parse opened positions
                            let openedArray = (json["opened"] as? [[String: Any]]) ?? []
                            let pendingArray = (json["pending"] as? [[String: Any]]) ?? []

                            var openedPositions: [MT5Position] = []
                            var pendingPositions: [MT5Position] = []

                            // Parse opened positions
                            for dict in openedArray {
                                guard let ticket = dict["ticket"] as? Int64,
                                      let symbol = dict["symbol"] as? String,
                                      let type = dict["type"] as? String,
                                      let volume = dict["volume"] as? Double,
                                      let priceOpen = dict["price_open"] as? Double else {
                                    continue
                                }
                                let position = MT5Position(
                                    ticket: ticket,
                                    symbol: symbol,
                                    type: type,
                                    volume: volume,
                                    priceOpen: priceOpen,
                                    sl: dict["sl"] as? Double ?? 0,
                                    tp: dict["tp"] as? Double ?? 0,
                                    priceCurrent: dict["price_current"] as? Double ?? priceOpen,
                                    profit: dict["profit"] as? Double ?? 0,
                                    magic: dict["magic"] as? Int64,
                                    comment: dict["comment"] as? String,
                                    openTime: dict["open_time"] as? Int64
                                )
                                openedPositions.append(position)
                            }

                            // Parse pending positions
                            for dict in pendingArray {
                                guard let ticket = dict["ticket"] as? Int64,
                                      let symbol = dict["symbol"] as? String,
                                      let type = dict["type"] as? String,
                                      let volume = dict["volume"] as? Double,
                                      let priceOpen = dict["price_open"] as? Double else {
                                    continue
                                }
                                let position = MT5Position(
                                    ticket: ticket,
                                    symbol: symbol,
                                    type: type,
                                    volume: volume,
                                    priceOpen: priceOpen,
                                    sl: dict["sl"] as? Double ?? 0,
                                    tp: dict["tp"] as? Double ?? 0,
                                    priceCurrent: dict["price_current"] as? Double ?? priceOpen,
                                    profit: dict["profit"] as? Double ?? 0,
                                    magic: dict["magic"] as? Int64,
                                    comment: dict["comment"] as? String,
                                    openTime: dict["open_time"] as? Int64
                                )
                                pendingPositions.append(position)
                            }

                            return (active: openedPositions, pending: pendingPositions)
                        }
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        godLog("⚠️ MT5: Positions fetch failed at \(path): \(httpResponse.statusCode) - \(errorMsg)", level: .warning)
                    }
                }
            } catch {
                godLog("⚠️ MT5: Positions fetch error at \(path): \(error)", level: .warning)
                continue
            }
        }

        return (active: [], pending: [])
    }

    // MARK: - Trading

    func executeTrade(signal: Signal) async throws -> MT5TradeResult {
        var cleanSymbol = signal.symbol.replacingOccurrences(of: "/", with: "")
        let suffix = await MainActor.run { ScalpingConfig.shared.brokerSuffix }
        if !suffix.isEmpty && !cleanSymbol.hasSuffix(suffix) {
            cleanSymbol += suffix
        }

        let paths = ["/v1/order"]
        var lastError: Error?

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15.0

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
                godLog("🌐 MT5: Executing trade on \(cleanSymbol)...", level: .info)

                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if data.isEmpty {
                            godLog("❌ MT5: Received empty response body on successful status code", level: .error)
                            throw TradingError.apiError("Empty response from MT5 Bridge")
                        }
                        
                        let tradeResult: MT5TradeResult
                        do {
                            tradeResult = try decoder.decode(MT5TradeResult.self, from: data)
                        } catch {
                            let raw = String(data: data, encoding: .utf8) ?? "binary data"
                            godLog("❌ MT5: Failed to decode trade result. Raw: \(raw)", level: .error)
                            throw error
                        }

                        if tradeResult.retcode != 10009 && tradeResult.retcode != 10008 {
                            godLog("❌ MT5: Execution failed: \(tradeResult.comment ?? "No comment")", level: .error)
                            throw TradingError.apiError("MT5 Error: \(tradeResult.comment ?? "Execution failed")")
                        }
                        return tradeResult
                    } else if httpResponse.statusCode == 503 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        if httpResponse.statusCode >= 500 {
                            throw TradingError.apiError("MT5 Server Error: \(errorMsg)")
                        }
                        godLog("⚠️ MT5: Path \(path) returned \(httpResponse.statusCode): \(errorMsg)", level: .warning)
                        continue
                    }
                }
            } catch {
                lastError = error
                godLog("⚠️ MT5: Execution error: \(error.localizedDescription)", level: .warning)
            }
        }

        throw lastError ?? TradingError.apiError("MT5 Execution Failed")
    }

    func closePosition(ticket: Int64, volume: Double? = nil) async throws -> Bool {
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
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        let result = try decoder.decode(MT5TradeResult.self, from: data)
                        return result.retcode == 10009 ||
                            result.retcode == 10010
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        godLog("⚠️ MT5: Close failed at \(path): \(httpResponse.statusCode) - \(errorMsg)", level: .warning)
                    }
                }
            } catch {
                godLog("⚠️ MT5: Close error at \(path): \(error)", level: .warning)
                continue
            }
        }

        return false
    }

    func modifyPosition(ticket: Int64, sl: Double, tp: Double) async throws -> Bool {
        let paths = ["/v1/order/modify", "/api/mt5/modify", "/modify"]

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")

            let body: [String: Any] = ["ticket": ticket, "sl": sl, "tp": tp]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        let result = try decoder.decode(MT5TradeResult.self, from: data)
                        return result.retcode == 10009 ||
                            result.retcode == 10010
                    } else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? ""
                        godLog("⚠️ MT5: Modify failed at \(path): \(httpResponse.statusCode) - \(errorMsg)", level: .warning)
                    }
                }
            } catch {
                godLog("⚠️ MT5: Modify error at \(path): \(error)", level: .warning)
                continue
            }
        }

        return false
    }

    // MARK: - History

    func getTradeHistory(days: Int = 30) async throws -> [MT5HistoryPosition] {
        let safeDays = max(1, min(days, 3650))
        let toEpoch = Int64(Date().timeIntervalSince1970)
        let fromEpoch = toEpoch - Int64(safeDays) * 24 * 60 * 60
        let paths = ["/v1/history/orders", "/api/mt5/history", "/history"]

        for path in paths {
            guard var components = URLComponents(string: "\(baseURL)\(path)") else { continue }
            components.queryItems = [
                URLQueryItem(name: "mode", value: "positions"),
                URLQueryItem(name: "from", value: String(fromEpoch)),
                URLQueryItem(name: "to", value: String(toEpoch)),
                URLQueryItem(name: "days", value: String(safeDays))
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20.0

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }

                guard httpResponse.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    godLog("⚠️ MT5: History endpoint \(path) returned \(httpResponse.statusCode): \(body.prefix(700))", level: .warning)
                    continue
                }

                guard let root = try? JSONSerialization.jsonObject(with: data) else {
                    godLog("⚠️ MT5: History response is not valid JSON", level: .warning)
                    continue
                }

                let rawItems: [[String: Any]]
                if let object = root as? [String: Any] {
                    rawItems =
                        (object["data"] as? [[String: Any]]) ??
                        (object["trades"] as? [[String: Any]]) ??
                        (object["history"] as? [[String: Any]]) ??
                        (object["positions"] as? [[String: Any]]) ?? []
                } else if let array = root as? [[String: Any]] {
                    rawItems = array
                } else {
                    rawItems = []
                }

                var history: [MT5HistoryPosition] = []
                history.reserveCapacity(rawItems.count)

                for dict in rawItems {
                    guard let symbol = Self.string(dict["symbol"]),
                          let ticket = Self.int64(dict["ticket"] ?? dict["deal"] ?? dict["order"]),
                          let volume = Self.number(dict["volume"]) else { continue }

                    let type = Self.string(dict["type"]) ?? "unknown"
                    let openPrice = Self.number(dict["open_price"] ?? dict["price_open"] ?? dict["price"]) ?? 0
                    let closePrice = Self.number(dict["close_price"] ?? dict["price_close"] ?? dict["price"]) ?? openPrice
                    let openTime = Self.int64(dict["open_time"] ?? dict["time_open"] ?? dict["time"]) ?? 0
                    let closeTime = Self.int64(dict["close_time"] ?? dict["time_close"] ?? dict["time"]) ?? openTime

                    history.append(
                        MT5HistoryPosition(
                            symbol: symbol,
                            ticket: ticket,
                            type: type,
                            volume: volume,
                            open_price: openPrice,
                            close_price: closePrice,
                            open_time: openTime,
                            close_time: closeTime,
                            profit: Self.number(dict["profit"]) ?? 0,
                            commission: Self.number(dict["commission"]) ?? 0,
                            swap: Self.number(dict["swap"]) ?? 0,
                            comment: Self.string(dict["comment"]),
                            magic: Self.int64(dict["magic"])
                        )
                    )
                }

                if !history.isEmpty {
                    godLog("📊 MT5: Loaded \(history.count) history entries", level: .info)
                    return history.sorted { $0.close_time > $1.close_time }
                }

                godLog("ℹ️ MT5: History endpoint returned 0 trades for the requested period at \(path)", level: .info)
            } catch {
                godLog("⚠️ MT5: History fetch error at \(path): \(error.localizedDescription)", level: .warning)
            }
        }

        return []
    }

    // MARK: - Symbol Info

    func isSymbolTradable(_ symbol: String) async -> Bool {
        let cleanSymbol = symbol.replacingOccurrences(of: "/", with: "")
        if let mode = symbolTradeMode[cleanSymbol] {
            return mode == 4 || mode == 1 || mode == 2
        }

        do {
            let info = try await getSymbolInfo(cleanSymbol)
            symbolTradeMode[cleanSymbol] = info.trade_mode
            symbolVolumeLimits[cleanSymbol] = (
                min: info.volume_min ?? 0.01,
                max: info.volume_max ?? 100.0,
                step: info.volume_step ?? 0.01
            )
            let mode = info.trade_mode
            return mode == 4 || mode == 1 || mode == 2
        } catch {
            return true
        }
    }

    func getVolumeLimits(for symbol: String) async -> (min: Double, max: Double, step: Double) {
        let cleanSymbol = symbol.replacingOccurrences(of: "/", with: "")
        if let limits = symbolVolumeLimits[cleanSymbol] {
            return limits
        }
        _ = await isSymbolTradable(symbol)
        return symbolVolumeLimits[cleanSymbol] ?? (0.01, 100.0, 0.01)
    }

    func getSymbolInfo(_ symbol: String) async throws -> MT5SymbolInfo {
        guard var components = URLComponents(string: "\(baseURL)/v1/symbol/info") else { throw TradingError.apiError("Invalid URL") }
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        guard let url = components.url else { throw TradingError.apiError("Invalid URL") }

        var request = URLRequest(url: url)
        request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return try decoder.decode(MT5SymbolInfo.self, from: data)
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? ""
                throw TradingError.apiError("Symbol info unavailable: \(httpResponse.statusCode) - \(errorMsg)")
            }
        }
        throw TradingError.apiError("Symbol info unavailable")
    }

    func getCurrentSpread(symbol: String) async throws -> Double {
        let info = try await getSymbolInfo(symbol)
        return Double(info.spread)
    }

    func getATR(symbol: String, period: Int = 14) async throws -> Double {
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

    func setTrackedSymbols(_ symbols: [String]) async throws -> Bool {
        let paths = ["/v1/track/prices", "/api/mt5/track"]

        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10.0

            let body = ["symbols": symbols]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        return true
                    } else {
                        godLog("⚠️ MT5: Track symbols failed at \(path): \(httpResponse.statusCode)", level: .warning)
                    }
                }
            } catch {
                godLog("⚠️ MT5: Track symbols error at \(path): \(error)", level: .warning)
                continue
            }
        }
        return false
    }
    // MARK: - JSON number helpers

    private nonisolated static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? UInt64 { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private nonisolated static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? UInt64 { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String, let parsed = Int64(value) { return parsed }
        if let value = number(value) { return Int64(value) }
        return nil
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

}