// BinanceModels.swift - THREAD-SAFE STREAM MODELS
import Foundation

struct BinanceStreamResponse: Codable, Sendable {
    let stream: String
    let data: BinanceKlineData

    enum CodingKeys: String, CodingKey {
        case stream, data
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stream = try container.decode(String.self, forKey: .stream)
        self.data = try container.decode(BinanceKlineData.self, forKey: .data)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stream, forKey: .stream)
        try container.encode(data, forKey: .data)
    }
}

struct BinanceKlineData: Codable, Sendable {
    let e: String // Event type
    let E: Int64  // Event time
    let s: String // Symbol
    let k: BinanceKlineDetail

    enum CodingKeys: String, CodingKey {
        case e, E, s, k
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.e = try container.decode(String.self, forKey: .e)
        self.E = try container.decode(Int64.self, forKey: .E)
        self.s = try container.decode(String.self, forKey: .s)
        self.k = try container.decode(BinanceKlineDetail.self, forKey: .k)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(e, forKey: .e)
        try container.encode(E, forKey: .E)
        try container.encode(s, forKey: .s)
        try container.encode(k, forKey: .k)
    }
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

    enum CodingKeys: String, CodingKey {
        case t, T, s, i, f, L, o, c, h, l, v, n, x, q, V, Q, B
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.t = try container.decode(Int64.self, forKey: .t)
        self.T = try container.decode(Int.self, forKey: .T)
        self.s = try container.decode(String.self, forKey: .s)
        self.i = try container.decode(String.self, forKey: .i)
        self.f = try container.decode(Int64.self, forKey: .f)
        self.L = try container.decode(Int64.self, forKey: .L)
        self.o = try container.decode(String.self, forKey: .o)
        self.c = try container.decode(String.self, forKey: .c)
        self.h = try container.decode(String.self, forKey: .h)
        self.l = try container.decode(String.self, forKey: .l)
        self.v = try container.decode(String.self, forKey: .v)
        self.n = try container.decode(Int.self, forKey: .n)
        self.x = try container.decode(Bool.self, forKey: .x)
        self.q = try container.decode(String.self, forKey: .q)
        self.V = try container.decode(String.self, forKey: .V)
        self.Q = try container.decode(String.self, forKey: .Q)
        self.B = try container.decode(String.self, forKey: .B)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(t, forKey: .t)
        try container.encode(T, forKey: .T)
        try container.encode(s, forKey: .s)
        try container.encode(i, forKey: .i)
        try container.encode(f, forKey: .f)
        try container.encode(L, forKey: .L)
        try container.encode(o, forKey: .o)
        try container.encode(c, forKey: .c)
        try container.encode(h, forKey: .h)
        try container.encode(l, forKey: .l)
        try container.encode(v, forKey: .v)
        try container.encode(n, forKey: .n)
        try container.encode(x, forKey: .x)
        try container.encode(q, forKey: .q)
        try container.encode(V, forKey: .V)
        try container.encode(Q, forKey: .Q)
        try container.encode(B, forKey: .B)
    }
}
