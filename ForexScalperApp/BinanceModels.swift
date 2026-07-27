// BinanceModels.swift - THREAD-SAFE STREAM MODELS
import Foundation

struct BinanceStreamResponse: Codable, Sendable {
    let stream: String
    let data: BinanceKlineData
}

struct BinanceKlineData: Codable, Sendable {
    let e: String // Event type
    let E: Int64  // Event time
    let s: String // Symbol
    let k: BinanceKlineDetail
}

struct BinanceKlineDetail: Codable, Sendable {
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
