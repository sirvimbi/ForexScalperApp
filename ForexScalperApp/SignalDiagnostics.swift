import Foundation

enum SignalDiagnostics {
    private struct PendingEvaluation {
        var direction = "NONE"
        var rawConfidence = 0.0
        var historicalAdjustment = 0.0
        var finalConfidence = 0.0
        var threshold = 0.0
        var riskRewardPassed = false
        var riskRewardKnown = false
        var decision = "PENDING"
        var passed: [(name: String, contribution: Double)] = []
        var failed: [(name: String, reason: String)] = []
    }

    private static let lock = NSLock()
    private static var installed = false
    private static var pending: [String: PendingEvaluation] = [:]

    static func install() {
        lock.lock()
        guard !installed else { lock.unlock(); return }
        installed = true
        lock.unlock()

        NotificationCenter.default.addObserver(forName: .newLogEntry, object: nil, queue: nil) { notification in
            guard let entry = notification.object as? LogEntry else { return }
            consume(entry.message)
        }

        godLog("🧭 Signal diagnostics installed — structured calculation tracing enabled", level: .info)
        SignalAuditSettings.shared.logSettings()
    }

    private static func consume(_ message: String) {
        guard !message.contains("🧾 SIGNAL CALC"),
              !message.contains("🧮 SIGNAL CALC"),
              !message.contains("⚙️ SIGNAL AUDIT SETTINGS") else { return }

        if let p = parsePillar(message) {
            recordPillar(p.symbol, passed: p.passed, name: p.name, contribution: p.contribution, reason: p.reason)
            return
        }

        if let p = parseScore(message) {
            lock.lock()
            var e = pending[p.symbol] ?? PendingEvaluation()
            e.direction = p.direction
            e.rawConfidence = p.confidence
            e.finalConfidence = p.confidence
            pending[p.symbol] = e
            lock.unlock()
            return
        }

        if let p = parseEval(message) {
            lock.lock()
            var e = pending[p.symbol] ?? PendingEvaluation()
            e.direction = p.direction
            e.rawConfidence = p.confidence
            e.finalConfidence = p.confidence
            e.threshold = p.threshold
            pending[p.symbol] = e
            lock.unlock()
            return
        }

        if let p = parseAdjustment(message) {
            lock.lock()
            var e = pending[p.symbol] ?? PendingEvaluation()
            e.historicalAdjustment = p.adjustment
            e.finalConfidence = p.finalConfidence
            pending[p.symbol] = e
            lock.unlock()
            return
        }

        if let p = parseRR(message) {
            lock.lock()
            var e = pending[p.symbol] ?? PendingEvaluation()
            e.riskRewardKnown = true
            e.riskRewardPassed = p.passed
            pending[p.symbol] = e
            lock.unlock()
            if !p.passed { finalize(p.symbol, decision: "NO TRADE — R:R FAIL") }
            return
        }

        if let p = parseDecision(message) {
            lock.lock()
            var e = pending[p.symbol] ?? PendingEvaluation()
            e.decision = p.decision
            if let c = p.finalConfidence { e.finalConfidence = c }
            pending[p.symbol] = e
            lock.unlock()
            finalize(p.symbol, decision: p.decision)
            return
        }

        if let p = parseAccepted(message) {
            lock.lock()
            var e = pending[p.symbol] ?? PendingEvaluation()
            e.direction = p.direction
            e.finalConfidence = p.confidence
            pending[p.symbol] = e
            lock.unlock()
            finalize(p.symbol, decision: "TRADE ACCEPTED")
        }
    }

    private static func recordPillar(_ symbol: String, passed: Bool, name: String, contribution: Double, reason: String) {
        lock.lock()
        var e = pending[symbol] ?? PendingEvaluation()
        if passed {
            e.passed.removeAll { $0.name == name }
            e.passed.append((name, contribution))
        } else {
            e.failed.removeAll { $0.name == name }
            e.failed.append((name, reason))
        }
        pending[symbol] = e
        lock.unlock()
    }

    private static func finalize(_ symbol: String, decision: String) {
        lock.lock()
        guard var e = pending.removeValue(forKey: symbol) else { lock.unlock(); return }
        e.decision = decision
        lock.unlock()

        SignalEvaluationAudit(
            symbol: symbol,
            direction: e.direction,
            rawConfidence: e.rawConfidence,
            historicalAdjustment: e.historicalAdjustment,
            finalConfidence: e.finalConfidence,
            threshold: e.threshold,
            riskRewardPassed: e.riskRewardKnown ? e.riskRewardPassed : false,
            decision: decision,
            passedPillars: e.passed,
            failedPillars: e.failed
        ).emit()
    }

    private static func parsePillar(_ message: String) -> (symbol: String, passed: Bool, name: String, contribution: Double, reason: String)? {
        guard let r = message.range(of: "🔎 SIGNAL PILLAR | ") else { return nil }
        let parts = String(message[r.upperBound...]).components(separatedBy: " | ")
        guard parts.count >= 5 else { return nil }
        let contribution = extractDouble(parts[parts.count - 2]) ?? 0
        return (parts[0], parts[1].contains("PASS"), parts[2], contribution, parts.dropFirst(3).dropLast(2).joined(separator: " | "))
    }

    private static func parseScore(_ message: String) -> (symbol: String, direction: String, confidence: Double)? {
        guard message.contains("🎯 SIGNAL SCORE | ") else { return nil }
        guard let symbol = capture(message, "🎯 SIGNAL SCORE \\| ([A-Z0-9]+) \\| direction=") else { return nil }
        guard let direction = capture(message, "direction=([^ |]+)"), let confidence = captureDouble(message, key: "baseConfidence=") else { return nil }
        return (symbol, direction, confidence)
    }

    private static func parseEval(_ message: String) -> (symbol: String, direction: String, confidence: Double, threshold: Double)? {
        guard message.contains("📊 EVAL: ") else { return nil }
        guard let symbol = capture(message, "📊 EVAL: ([A-Z0-9]+) \\|? ?([^ ]+) \\|") else { return nil }
        guard let confidence = captureDouble(message, key: "Conf: "), let threshold = captureDouble(message, key: "Need ") else { return nil }
        let direction = capture(message, "📊 EVAL: [A-Z0-9]+ ([^ ]+) \\|") ?? "NONE"
        return (symbol, direction, confidence, threshold)
    }

    private static func parseAdjustment(_ message: String) -> (symbol: String, adjustment: Double, finalConfidence: Double)? {
        guard message.contains("🧠 SIGNAL ADJUSTMENT | "),
              let symbol = capture(message, "🧠 SIGNAL ADJUSTMENT \\| ([A-Z0-9]+) \\|"),
              let values = twoPercentValues(in: message) else { return nil }
        return (symbol, values.second - values.first, values.second)
    }

    private static func parseRR(_ message: String) -> (symbol: String, passed: Bool)? {
        guard message.contains("⚖️ SIGNAL GATE | "), let symbol = capture(message, "⚖️ SIGNAL GATE \\| ([A-Z0-9]+) \\|") else { return nil }
        return (symbol, message.contains("R:R=PASS"))
    }

    private static func parseDecision(_ message: String) -> (symbol: String, decision: String, finalConfidence: Double?)? {
        guard message.contains("🛑 SIGNAL DECISION | "), let symbol = capture(message, "🛑 SIGNAL DECISION \\| ([A-Z0-9]+) \\|") else { return nil }
        let confidence = captureDouble(message, key: "confidence=")
        return (symbol, message.contains("REJECTED") ? "NO TRADE — GATE FAIL" : "NO TRADE", confidence)
    }

    private static func parseAccepted(_ message: String) -> (symbol: String, direction: String, confidence: Double)? {
        guard message.contains("🚀 HYBRID SIGNAL: "), let symbol = capture(message, "🚀 HYBRID SIGNAL: ([A-Z0-9]+) \\|"), let confidence = captureDouble(message, key: "Confidence: ") else { return nil }
        return (symbol, "TRADE", confidence)
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func captureDouble(_ text: String, key: String) -> Double? {
        capture(text, NSRegularExpression.escapedPattern(for: key) + "(-?[0-9]+(?:\\.[0-9]+)?)").flatMap(Double.init)
    }

    private static func extractDouble(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "+", with: "").split(separator: " ").first ?? "")
    }

    private static func twoPercentValues(in text: String) -> (first: Double, second: Double)? {
        let pattern = "from ([0-9]+(?:\\.[0-9]+)?)% to ([0-9]+(?:\\.[0-9]+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges == 3, let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text), let a = Double(text[r1]), let b = Double(text[r2]) else { return nil }
        return (a, b)
    }
}
