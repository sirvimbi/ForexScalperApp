// IGTradingService.swift
import Foundation

class IGTradingService {
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
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug: Print raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Raw auth response: \(responseString)")
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 HTTP Status: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    throw TradingError.apiError("Server returned status \(httpResponse.statusCode)")
                }
            }
            
            let authResponse = try JSONDecoder().decode(IGAuthResponse.self, from: data)
            
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
            
        } catch let decodingError as DecodingError {
            print("❌ Decoding error: \(decodingError)")
            throw TradingError.decodingError
        } catch {
            print("❌ Network error: \(error)")
            throw error
        }
    }
    
    // MARK: - Account Info
    
    func getAccountInfo() async throws -> AccountInfo {
        guard let url = URL(string: "\(baseURL)/account") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add session ID if available
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Debug: Print raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 Raw account response: \(responseString)")
        }
        
        // Check if response is HTML (starts with <)
        if let firstChar = String(data: data.prefix(1), encoding: .utf8), firstChar == "<" {
            throw TradingError.apiError("Backend returned HTML instead of JSON. Make sure your Node.js server is running at \(baseURL)")
        }
        
        let apiResponse = try JSONDecoder().decode(IGAPIResponse<AccountInfo>.self, from: data)
        
        guard apiResponse.success else {
            throw TradingError.apiError(apiResponse.error ?? "Unknown error")
        }
        
        return apiResponse.data!
    }
    
    // MARK: - Trading
    
    func executeTrade(signal: Signal) async throws -> TradeResult {
        guard let url = URL(string: "\(baseURL)/trades/execute") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add session ID if available (required for authenticated requests)
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        } else {
            print("⚠️ No session ID available - authentication required for IG trading")
            throw TradingError.notAuthenticated
        }
        
        // Use a default size if positionSize is nil (this happens before acceptance)
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
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug print
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 IG execute trade response: \(responseString)")
            }
            
            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw TradingError.notAuthenticated
                } else if httpResponse.statusCode != 200 {
                    throw TradingError.apiError("Server returned status \(httpResponse.statusCode)")
                }
            }
            
            let apiResponse = try JSONDecoder().decode(IGAPIResponse<TradeResult>.self, from: data)
            
            guard apiResponse.success else {
                throw TradingError.apiError(apiResponse.error ?? "Unknown error")
            }
            
            print("✅ IG trade executed successfully. Deal Reference: \(apiResponse.data?.dealReference ?? "N/A")")
            return apiResponse.data!
        } catch {
            print("❌ IG execute trade error: \(error)")
            throw error
        }
    }
    
    func getOpenPositions() async throws -> [Position] {
        guard let url = URL(string: "\(baseURL)/trades/positions") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add session ID if available
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        } else {
            throw TradingError.notAuthenticated
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(IGAPIResponse<[Position]>.self, from: data)
        
        guard response.success else {
            throw TradingError.apiError(response.error ?? "Unknown error")
        }
        
        return response.data!
    }
    
    func closePosition(dealId: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/trades/positions/\(dealId)") else {
            throw TradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        // Add session ID if available
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        } else {
            throw TradingError.notAuthenticated
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(IGAPIResponse<Bool>.self, from: data)
        
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
}

// MARK: - Models

struct IGAuthResponse: Codable {
    let success: Bool
    let data: IGAuthData?
    let error: String?
}

struct IGAuthData: Codable {
    let cst: String
    let xSecurityToken: String
    let accountId: String
    let lightstreamerEndpoint: String?
    let sessionId: String?  // Added for session management
}

struct IGAPIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
}

struct AccountInfo: Codable {
    let accountId: String
    let accountName: String
    let balance: Double
    let deposit: Double
    let profitLoss: Double
    let available: Double
    let currency: String
}

struct TradeResult: Codable {
    let dealReference: String
    let dealId: String?
    let symbol: String
    let direction: String
    let size: Double
    let status: String?  // Added status field
    let timestamp: String? // Added timestamp
}

struct Position: Codable {
    let dealId: String
    let epic: String
    let marketName: String
    let direction: String
    let size: Double
    let level: Double
    let limitLevel: Double?
    let stopLevel: Double?
    let createdDate: String
    let currency: String
    let profitLoss: Double?
}

enum TradingError: Error, LocalizedError {
    case invalidURL
    case apiError(String)
    case decodingError
    case serverNotRunning
    case notAuthenticated
    case insufficientFunds
    case marketClosed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .apiError(let message):
            return "API Error: \(message)"
        case .decodingError:
            return "Failed to decode response"
        case .serverNotRunning:
            return "Backend server is not running at http://localhost:3000"
        case .notAuthenticated:
            return "Not authenticated. Please connect to IG first."
        case .insufficientFunds:
            return "Insufficient funds in account"
        case .marketClosed:
            return "Market is closed for this instrument"
        }
    }
}

// MARK: - Extension for Config (if not already defined)
// This is a placeholder - you should store API key securely
extension UserDefaults {
    var igAPIKey: String {
        get { string(forKey: "igAPIKey") ?? "23ca12562ccdbef0e9ab24d55c4f423b604bddd9" }
        set { set(newValue, forKey: "igAPIKey") }
    }
}
