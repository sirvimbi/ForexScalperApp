// MT5Service.swift - MT5 execution service
import Foundation

actor MT5Service {
    static let shared = MT5Service()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: config)
    }()

    private nonisolated let decoder = JSONDecoder()
    private var customBaseURL: String?
    private var customAuthToken: String?
    private var lastWorkingPath: String?
    private var symbolTradeMode: [String: Int] = [:]
    private var symbolVolumeLimits: [String: (min: Double, max: Double, step: Double)] = [:]
    private var _isConnected = false
    private var lastRequestTime: Date?
    private let minimumInterval: TimeInterval = 0.1

    var isConnected: Bool { _isConnected }

    private var authBuffer: String {
        if let custom = customAuthToken {
            return custom.hasPrefix("Bearer ") ? custom : "Bearer \(custom)"
        }
        let saved = SecureCredentialStore.shared.read("mt5AuthToken") ?? ""
        return saved.hasPrefix("Bearer ") ? saved : "Bearer \(saved)"
    }

    private var baseURL: String {
        let raw = customBaseURL ?? UserDefaults.standard.string(forKey: "mt5BridgeURL") ?? "http://127.0.0.1:8890"
        var value = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        if value.contains(":8891") { value = value.replacingOccurrences(of: ":8891", with: ":8890") }
        return value
    }

    private init() {}

    func setBaseURL(_ url: String) {
        customBaseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        godLog("🌐 MT5: Base URL set to \(customBaseURL!)", level: .diagnostic)
    }

    func setAuthToken(_ token: String) {
        customAuthToken = token
        godLog("🔐 MT5: Auth token updated", level: .diagnostic)
    }

    private func waitForRateLimit() async {
        let now = Date()
        if let last = lastRequestTime {
            let wait = minimumInterval - now.timeIntervalSince(last)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        }
        lastRequestTime = Date()
    }

    private func request(_ url: URL, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 15) async throws -> (Data, HTTPURLResponse) {
        await waitForRateLimit()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(authBuffer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TradingError.apiError("Invalid response from MT5 Bridge")
        }
        return (data, http)
    }

    func disconnect() {
        _isConnected = false
        lastWorkingPath = nil
        godLog("🔌 MT5Service: connection state cleared", level: .diagnostic)
    }

    func initialize(login: Int, password: String, server: String) async throws {
        for path in ["/api/mt5/initialize", "/v1/initialize", "/initialize"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (_, response) = try await request(url, method: "POST", body: ["login": login, "password": password, "server": server], timeout: 10)
                if response.statusCode == 200 {
                    _isConnected = true
                    godLog("✅ MT5: Initialization successful", level: .success)
                    return
                }
                if response.statusCode != 404 { godLog("⚠️ MT5: Initialize \(path) returned \(response.statusCode)", level: .warning) }
            } catch { godLog("⚠️ MT5: Initialize \(path) failed: \(error.localizedDescription)", level: .warning) }
        }
        _ = try await checkConnection()
    }

    func checkConnection() async throws -> Bool {
        var lastError: Error?
        for path in ["/v1/status", "/status"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (data, response) = try await request(url, timeout: 5)
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw TradingError.apiError("Authentication failed - check API token")
                }
                guard response.statusCode == 200 else { continue }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let connected = json["connected"] as? Bool {
                    _isConnected = connected
                    return connected
                }
                _isConnected = true
                return true
            } catch {
                lastError = error
                godLog("⚠️ MT5: Connection check failed at \(path): \(error.localizedDescription)", level: .warning)
            }
        }
        _isConnected = false
        throw lastError ?? TradingError.apiError("MT5 connection failed - Bridge may be offline")
    }

    func getCandles(symbol: String, timeframe: String, count: Int = 1000) async throws -> [Kline] {
        let clean = symbol.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tf: String
        switch timeframe.lowercased() {
        case "1m", "m1": tf = "M1"
        case "5m", "m5": tf = "M5"
        case "15m", "m15": tf = "M15"
        case "30m", "m30": tf = "M30"
        case "1h", "h1": tf = "H1"
        case "4h", "h4": tf = "H4"
        case "1d", "d1": tf = "D1"
        case "1w", "w1": tf = "W1"
        default: tf = timeframe.uppercased()
        }
        let safeCount = max(1, min(count, 5000))
        var paths = ["/v1/history/prices", "/api/mt5/candles", "/candles"]
        if let working = lastWorkingPath, let i = paths.firstIndex(of: working) { paths.remove(at: i); paths.insert(working, at: 0) }
        for path in paths {
            guard var components = URLComponents(string: baseURL + path) else { continue }
            components.queryItems = [URLQueryItem(name: "symbol", value: clean), URLQueryItem(name: "time_frame", value: tf), URLQueryItem(name: "count", value: String(safeCount))]
            guard let url = components.url else { continue }
            do {
                let (data, response) = try await request(url, timeout: 30)
                if response.statusCode == 404 || response.statusCode == 503 { continue }
                guard response.statusCode == 200, let root = try? JSONSerialization.jsonObject(with: data) else { continue }
                let raw: [[String: Any]]
                if let object = root as? [String: Any] {
                    raw = (object["data"] as? [[String: Any]]) ?? (object["candles"] as? [[String: Any]]) ?? (object["rates"] as? [[String: Any]]) ?? (object["items"] as? [[String: Any]]) ?? []
                } else { raw = (root as? [[String: Any]]) ?? [] }
                let candles = raw.compactMap { dict -> Kline? in
                    guard let time = Self.number(dict["time"] ?? dict["timestamp"] ?? dict["time_stamp"]), let open = Self.number(dict["open"] ?? dict["o"]), let high = Self.number(dict["high"] ?? dict["h"]), let low = Self.number(dict["low"] ?? dict["l"]), let close = Self.number(dict["close"] ?? dict["c"]) else { return nil }
                    let seconds = time > 10_000_000_000 ? time / 1000 : time
                    return Kline(open: open, high: high, low: low, close: close, volume: Self.number(dict["volume"] ?? dict["tick_volume"] ?? dict["real_volume"] ?? dict["v"]) ?? 0, closeTime: Int(seconds), spread: Self.number(dict["spread"]), isClosed: true)
                }
                if !candles.isEmpty { lastWorkingPath = path; return candles.sorted { $0.closeTime < $1.closeTime } }
            } catch { godLog("⚠️ MT5: Candle fetch failed at \(path): \(error.localizedDescription)", level: .warning) }
        }
        return []
    }

    func getAccountInfo() async throws -> MT5AccountInfo {
        for path in ["/v1/account", "/api/mt5/account", "/account"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (data, response) = try await request(url, timeout: 10)
                if response.statusCode == 404 { continue }
                if response.statusCode == 401 || response.statusCode == 403 { throw TradingError.apiError("Authentication failed - check API token") }
                guard response.statusCode == 200 else { continue }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let accountData = json["data"] as? [String: Any] {
                    let nested = try JSONSerialization.data(withJSONObject: accountData)
                    let account = try decoder.decode(MT5AccountInfo.self, from: nested)
                    _isConnected = true
                    return account
                }
                let account = try decoder.decode(MT5AccountInfo.self, from: data)
                _isConnected = true
                godLog("💰 MT5 Account: Balance \(account.balance), Equity \(account.equity)", level: .info)
                return account
            } catch let error as TradingError { throw error }
            catch { godLog("⚠️ MT5: Account fetch error at \(path): \(error.localizedDescription)", level: .warning) }
        }
        _isConnected = false
        throw TradingError.apiError("Failed to fetch MT5 account information - Bridge may be offline or not authenticated")
    }

    func getPositionsAndOrders() async throws -> (active: [MT5Position], pending: [MT5Position]) {
        for path in ["/v1/order/list", "/api/mt5/positions", "/positions"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (data, response) = try await request(url, timeout: 10)
                guard response.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let parse: ([[String: Any]]) -> [MT5Position] = { rows in rows.compactMap { d in
                    guard let ticket = Self.int64(d["ticket"]), let symbol = Self.string(d["symbol"]), let type = Self.string(d["type"]), let volume = Self.number(d["volume"]), let open = Self.number(d["price_open"] ?? d["open_price"] ?? d["price"]) else { return nil }
                    return MT5Position(ticket: ticket, symbol: symbol, type: type, volume: volume, priceOpen: open, sl: Self.number(d["sl"]) ?? 0, tp: Self.number(d["tp"]) ?? 0, priceCurrent: Self.number(d["price_current"]) ?? open, profit: Self.number(d["profit"]) ?? 0, magic: Self.int64(d["magic"]), comment: Self.string(d["comment"]), openTime: Self.int64(d["open_time"]))
                }}
                return (parse((json["opened"] as? [[String: Any]]) ?? []), parse((json["pending"] as? [[String: Any]]) ?? []))
            } catch { godLog("⚠️ MT5: Positions fetch failed at \(path): \(error.localizedDescription)", level: .warning) }
        }
        return ([], [])
    }

    func executeTrade(signal: Signal) async throws -> MT5TradeResult {
        var symbol = signal.symbol.replacingOccurrences(of: "/", with: "")
        let suffix = await MainActor.run { ScalpingConfig.shared.brokerSuffix }
        if !suffix.isEmpty && !symbol.hasSuffix(suffix) { symbol += suffix }

        guard await isSymbolTradable(symbol) else { throw TradingError.apiError("Symbol \(symbol) is not tradable on MT5") }
        let limits = await getVolumeLimits(for: symbol)
        let requested = signal.positionSize ?? signal.volume
        let clamped = max(limits.min, min(requested, limits.max))
        let stepped = max(limits.min, (clamped / limits.step).rounded() * limits.step)
        let orderType: String = signal.type == .buy ? "buy" : signal.type == .sell ? "sell" : ""
        guard !orderType.isEmpty else { throw TradingError.apiError("Invalid signal type: none") }

        guard let url = URL(string: baseURL + "/v1/order") else { throw TradingError.apiError("Invalid MT5 order URL") }

        // The V10.5 EA exposes /v1/order as a MARKET ENTRY endpoint only.
        // `executionMode` is an app-side execution preference, not the bridge action.
        // Sending values such as "instant" makes the EA reject an otherwise valid signal
        // with "Unsupported order action". Always send the bridge action as "market".
        let executionPreference = signal.executionMode?.rawValue.lowercased() ?? "market"
        var body: [String: Any] = [
            "action": "market",
            "symbol": symbol,
            "order_type": signal.orderType?.rawValue.lowercased() ?? orderType,
            "volume": stepped,
            "price": signal.price,
            "sl": signal.stopLoss ?? 0,
            "tp": signal.takeProfit ?? 0,
            "magic": signal.magicNumber ?? 888888,
            "comment": signal.comment ?? "GOD_MODE_SCALPER",
            "deviation": signal.deviation ?? 20,
            "type_filling": signal.filler?.rawValue.lowercased() ?? "ioc"
        ]
        if signal.stopLoss == nil { body.removeValue(forKey: "sl") }
        if signal.takeProfit == nil { body.removeValue(forKey: "tp") }

        godLog("🚀 MT5 EXECUTION | \(symbol) | side=\(orderType.uppercased()) | action=market | preference=\(executionPreference) | volume=\(String(format: "%.4f", stepped)) | price=\(String(format: "%.5f", signal.price)) | SL=\(signal.stopLoss.map { String(format: "%.5f", $0) } ?? "none") | TP=\(signal.takeProfit.map { String(format: "%.5f", $0) } ?? "none")", level: .info)

        do {
            let (data, response) = try await request(url, method: "POST", body: body, timeout: 15)
            let raw = String(data: data, encoding: .utf8) ?? ""
            guard response.statusCode == 200 else {
                throw TradingError.apiError("MT5 order HTTP \(response.statusCode): \(raw.prefix(500))")
            }
            guard !data.isEmpty else { throw TradingError.apiError("Empty response from MT5 Bridge") }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let success = json["success"] as? Bool, success == false {
                throw TradingError.apiError("MT5 Bridge Error: \(json["error"] as? String ?? "Execution failed")")
            }
            let result = try decoder.decode(MT5TradeResult.self, from: data)
            guard result.retcode == 10008 || result.retcode == 10009 else {
                throw TradingError.apiError("MT5 Error (\(result.retcode)): \(result.comment ?? "Execution failed")")
            }
            godLog("✅ MT5: Trade executed successfully (Code: \(result.retcode))", level: .success)
            return result
        } catch let error as TradingError { throw error }
        catch { throw TradingError.apiError("Failed to parse MT5 trade response: \(error.localizedDescription)") }
    }

    func closePosition(ticket: Int64, volume: Double? = nil) async throws -> Bool {
        for path in ["/v1/order/close", "/api/mt5/close", "/close"] {
            guard let url = URL(string: baseURL + path) else { continue }
            var body: [String: Any] = ["ticket": ticket]
            if let volume { body["volume"] = volume }
            do {
                let (data, response) = try await request(url, method: "POST", body: body, timeout: 15)
                if response.statusCode == 200 {
                    let result = try decoder.decode(MT5TradeResult.self, from: data)
                    return result.retcode == 10009 || result.retcode == 10010
                }
            } catch { godLog("⚠️ MT5: Close failed at \(path): \(error.localizedDescription)", level: .warning) }
        }
        return false
    }

    func modifyPosition(ticket: Int64, sl: Double, tp: Double) async throws -> Bool {
        for path in ["/v1/order/modify", "/api/mt5/modify", "/modify"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (data, response) = try await request(url, method: "POST", body: ["ticket": ticket, "sl": sl, "tp": tp], timeout: 15)
                if response.statusCode == 200 {
                    let result = try decoder.decode(MT5TradeResult.self, from: data)
                    return result.retcode == 10009 || result.retcode == 10010
                }
            } catch { godLog("⚠️ MT5: Modify failed at \(path): \(error.localizedDescription)", level: .warning) }
        }
        return false
    }

    func getTradeHistory(days: Int = 30) async throws -> [MT5HistoryPosition] {
        let safeDays = max(1, min(days, 3650))
        let to = Int64(Date().timeIntervalSince1970)
        let from = to - Int64(safeDays) * 86400
        for path in ["/v1/history/orders", "/api/mt5/history", "/history"] {
            guard var components = URLComponents(string: baseURL + path) else { continue }
            components.queryItems = [URLQueryItem(name: "mode", value: "positions"), URLQueryItem(name: "from", value: String(from)), URLQueryItem(name: "to", value: String(to)), URLQueryItem(name: "days", value: String(safeDays))]
            guard let url = components.url else { continue }
            do {
                let (data, response) = try await request(url, timeout: 20)
                guard response.statusCode == 200, let root = try? JSONSerialization.jsonObject(with: data) else { continue }
                let raw: [[String: Any]]
                if let object = root as? [String: Any] { raw = (object["data"] as? [[String: Any]]) ?? (object["trades"] as? [[String: Any]]) ?? (object["history"] as? [[String: Any]]) ?? (object["positions"] as? [[String: Any]]) ?? [] } else { raw = (root as? [[String: Any]]) ?? [] }
                let history = raw.compactMap { d -> MT5HistoryPosition? in
                    guard let symbol = Self.string(d["symbol"]), let ticket = Self.int64(d["ticket"] ?? d["deal"] ?? d["order"]), let volume = Self.number(d["volume"]) else { return nil }
                    let open = Self.number(d["open_price"] ?? d["price_open"] ?? d["price"]) ?? 0
                    let close = Self.number(d["close_price"] ?? d["price_close"] ?? d["price"]) ?? open
                    let openTime = Self.int64(d["open_time"] ?? d["time_open"] ?? d["time"]) ?? 0
                    let closeTime = Self.int64(d["close_time"] ?? d["time_close"] ?? d["time"]) ?? openTime
                    return MT5HistoryPosition(symbol: symbol, ticket: ticket, type: Self.string(d["type"]) ?? "unknown", volume: volume, open_price: open, close_price: close, open_time: openTime, close_time: closeTime, profit: Self.number(d["profit"]) ?? 0, commission: Self.number(d["commission"]) ?? 0, swap: Self.number(d["swap"]) ?? 0, comment: Self.string(d["comment"]), magic: Self.int64(d["magic"]))
                }
                if !history.isEmpty { return history.sorted { $0.close_time > $1.close_time } }
            } catch { godLog("⚠️ MT5: History fetch failed at \(path): \(error.localizedDescription)", level: .warning) }
        }
        return []
    }

    func isSymbolTradable(_ symbol: String) async -> Bool {
        let clean = symbol.replacingOccurrences(of: "/", with: "")
        if let mode = symbolTradeMode[clean] { return mode == 1 || mode == 2 || mode == 4 }
        do {
            let info = try await getSymbolInfo(clean)
            symbolTradeMode[clean] = info.trade_mode
            symbolVolumeLimits[clean] = (info.volume_min ?? 0.01, info.volume_max ?? 100, info.volume_step ?? 0.01)
            return info.trade_mode == 1 || info.trade_mode == 2 || info.trade_mode == 4
        } catch {
            godLog("⚠️ MT5: Symbol info unavailable for \(clean); refusing to assume tradability", level: .warning)
            return false
        }
    }

    func getVolumeLimits(for symbol: String) async -> (min: Double, max: Double, step: Double) {
        let clean = symbol.replacingOccurrences(of: "/", with: "")
        if let limits = symbolVolumeLimits[clean] { return limits }
        _ = await isSymbolTradable(clean)
        return symbolVolumeLimits[clean] ?? (0.01, 100, 0.01)
    }

    func getSymbolInfo(_ symbol: String) async throws -> MT5SymbolInfo {
        guard var components = URLComponents(string: baseURL + "/v1/symbol/info") else { throw TradingError.apiError("Invalid URL") }
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol.replacingOccurrences(of: "/", with: ""))]
        guard let url = components.url else { throw TradingError.apiError("Invalid URL") }
        let (data, response) = try await request(url, timeout: 10)
        guard response.statusCode == 200 else { throw TradingError.apiError("Symbol info unavailable: \(response.statusCode)") }
        return try decoder.decode(MT5SymbolInfo.self, from: data)
    }

    func getCurrentSpread(symbol: String) async throws -> Double { Double((try await getSymbolInfo(symbol)).spread) }

    func getATR(symbol: String, period: Int = 14) async throws -> Double {
        let candles = try await getCandles(symbol: symbol, timeframe: "5m", count: period * 2)
        guard candles.count >= period else { throw TradingError.apiError("Insufficient MT5 candle data for ATR") }
        let closes = candles.map(\.close), highs = candles.map(\.high), lows = candles.map(\.low)
        var trs: [Double] = []
        for i in 1..<candles.count { trs.append(max(highs[i] - lows[i], abs(highs[i] - closes[i - 1]), abs(lows[i] - closes[i - 1]))) }
        return trs.reduce(0, +) / Double(trs.count)
    }

    func setTrackedSymbols(_ symbols: [String]) async throws -> Bool {
        for path in ["/v1/track/prices", "/api/mt5/track"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do { let (_, response) = try await request(url, method: "POST", body: ["symbols": symbols], timeout: 10); if response.statusCode == 200 { return true } }
            catch { godLog("⚠️ MT5: Track symbols failed at \(path): \(error.localizedDescription)", level: .warning) }
        }
        return false
    }

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