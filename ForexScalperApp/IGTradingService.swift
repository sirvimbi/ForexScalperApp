// IGTradingService.swift
import Foundation

actor IGTradingService {
    static let shared = IGTradingService()
    private let baseURL = "http://localhost:3000/api" // Your Node.js backend
    private var sessionId: String?
    private var cst: String?
    private var xSecurityToken: String?
    
    private init() {}
    
    // MARK: - Authentication
    
    func authenticate(identifier: String, password: String, apiKey: String) async throws -> IGAuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/ig") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-ig-api-key")
        
        let body: [String: Any] = [
            "identifier": identifier,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard httpResponse.statusCode == 200 else {
                throw TradingError.apiError("Server returned status \(httpResponse.statusCode)")
            }
        }
        
        let authResponse = try decode(IGAuthResponse.self, from: data)
        
        // Store session information
        if let sessionId = authResponse.data?.sessionId {
            self.sessionId = sessionId
        }
        if let cst = authResponse.data?.cst {
            self.cst = cst
        }
        if let token = authResponse.data?.xSecurityToken {
            self.xSecurityToken = token
        }
        
        return authResponse
    }
    
    // MARK: - Account Info
    
    func getAccountInfo() async throws -> IGAccountInfo {
        guard let url = URL(string: "\(baseURL)/account") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let apiResponse = try decode(IGAPIResponse<IGAccountInfo>.self, from: data)
        
        guard apiResponse.success, let accountData = apiResponse.data else {
            throw TradingError.apiError(apiResponse.error ?? "Unknown error")
        }
        
        return accountData
    }
    
    // MARK: - Trading
    
    func executeTrade(signal: Signal) async throws -> IGTradeResult {
        guard let url = URL(string: "\(baseURL)/trades/execute") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        } else {
            throw TradingError.notAuthenticated
        }
        
        let positionSize = signal.positionSize ?? 1000
        let body: [String: Any] = [
            "signalId": signal.id.uuidString,
            "symbol": signal.symbol,
            "direction": signal.type == .buy ? "BUY" : "SELL",
            "size": positionSize,
            "stopLoss": signal.stopLoss ?? 0,
            "takeProfit": signal.takeProfit ?? 0,
            "confidence": signal.confidence
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw TradingError.notAuthenticated
            } else if httpResponse.statusCode != 200 {
                throw TradingError.apiError("Server returned status \(httpResponse.statusCode)")
            }
        }
        
        let apiResponse = try decode(IGAPIResponse<IGTradeResult>.self, from: data)
        
        guard apiResponse.success, let tradeResult = apiResponse.data else {
            throw TradingError.apiError(apiResponse.error ?? "Unknown error")
        }
        
        return tradeResult
    }
    
    func getOpenPositions() async throws -> [IGPosition] {
        guard let url = URL(string: "\(baseURL)/trades/positions") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        } else {
            throw TradingError.notAuthenticated
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try decode(IGAPIResponse<[IGPosition]>.self, from: data)
        
        guard response.success, let positions = response.data else {
            throw TradingError.apiError(response.error ?? "Unknown error")
        }
        
        return positions
    }
    
    func closePosition(dealId: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/trades/positions/\(dealId)") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        } else {
            throw TradingError.notAuthenticated
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try decode(IGAPIResponse<Bool>.self, from: data)
        
        return response.success
    }
    
    // MARK: - Session Management
    
    func isAuthenticated() -> Bool {
        return sessionId != nil && !sessionId!.isEmpty
    }
    
    func getSessionId() -> String? {
        return sessionId
    }
    
    func clearSession() {
        sessionId = nil
        cst = nil
        xSecurityToken = nil
    }
    
    // MARK: - Helper Methods
    
    private nonisolated func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Extension for Config
extension UserDefaults {
    var igAPIKey: String {
        get { string(forKey: "igAPIKey") ?? "23ca12562ccdbef0e9ab24d55c4f423b604bddd9" }
        set { set(newValue, forKey: "igAPIKey") }
    }
}
