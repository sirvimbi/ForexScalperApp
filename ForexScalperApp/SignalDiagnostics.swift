import Foundation

/// Observes the signal engine's existing logs and turns the raw pillar/gate events
/// into one structured calculation record per symbol.
///
/// This remains observational only. ScalpingSignalEngine remains the sole authority
/// for scoring, risk validation and trade decisions.
enum SignalDiagnostics {
    private struct PendingEvaluation {
        var direction: String = "NONE"
        var rawConfidence: Double = 0
        var historicalAdjustment: Double = 0
        var finalConfidence: Double = 0
        var threshold: Double = 0
        var riskRewardPassed: Bool = false
        var riskRewardKnown = false
        var decision: String = "PENDING"
        var passed: [(name: String, contribution: Double)] = []
        var failed: [(name: String, reason: String)] = []
        var lastUpdate = Date()
    }

    private static let lock = NSLock()
    private static var installed = false
    private static var pending: [String: PendingEvaluation] = [:]

    static func install() {
        lock.lock()
        guard !installed else {
            lock.unlock()
            return
        }
        installed = true
        lock.unlock()

        NotificationCenter.default.addObserver(
            forName: .newLogEntry,
            object: nil,
            queue: nil
        ) { notification in
            guard let entry = notification.object as? LogEntry else { return }
            consume(entry.message)
        }

        godLog("🧭 Signal diagnostics installed — structured calculation tracing enabled", level: .diagnostic)
        SignalAuditSettings.shared.logSettings()
    }

    private static func consume(_ message: String) {
        // Never consume our own synthesized audit messages.
        guard !message.contains("🧾 SIGNAL CALC"),
              !message.contains("🧮 SIGNAL CALC"),
              !message.contains("⚙️ SIGNAL AUDIT SETTINGS") else { return }

        if let parsed = parsePillar(message) {
            recordPillar(parsed.symbol, passed: parsed.passed, name: parsed.name, contribution: parsed.contribution, reason: parsed.reason)
            return
        }

        if let parsed = parseScore(message) {
            lock.lock()
            var evaluation = pending[parsed.symbol] ?? PendingEvaluation()
            evaluation.direction = parsed.direction
            evaluation.rawConfidence = parsed.confidence
            evaluation.finalConfidence = parsed.confidence
            evaluation.threshold = parsed.threshold
            evaluation.lastUpdate = Date()
            pending[parsed.symbol] = evaluation
            lock.unlock()
            return
        }

        if let parsed = parseAdjustment(message) {
            lock.lock()
            var evaluation = pending[parsed.symbol] ?? PendingEvaluation()
            evaluation.historicalAdjustment = parsed.adjustment
            evaluation.finalConfidence = parsed.finalConfidence
            evaluation.lastUpdate = Date()
            pending[parsed.symbol] = evaluation
            lock.unlock()
            return
        }

        if let parsed = parseRR(message) {
            lock.lock()
            var evaluation = pending[parsed.symbol] ?? PendingEvaluation()
            evaluation.riskRewardKnown = true
            evaluation.riskRewardPassed = parsed.passed
            evaluation.lastUpdate = Date()
            pending[parsed.symbol] = evaluation
            lock.unlock()

            if !parsed.passed {
                finalize(parsed.symbol, decision: "NO TRADE — R:R FAIL")
            }
            return
        }

        if let parsed = parseDecision(message) {
            lock.lock()
            var evaluation = pending[parsed.symbol] ?? PendingEvaluation()
            evaluation.decision = parsed.decision
            if let finalConfidence = parsed.finalConfidence {
                evaluation.finalConfidence = finalConfidence
            }
            evaluation.lastUpdate = Date()
            pending[parsed.symbol] = evaluation
            lock.unlock()

            if parsed.isTerminal {
                finalize(parsed.symbol, decision: parsed.decision)
            }
            return
        }

        if let parsed = parseAccepted(message) {
            lock.lock()
            var evaluation = pending[parsed.symbol] ?? PendingEvaluation()
            evaluation.direction = parsed.direction
            evaluation.finalConfidence = parsed.confidence
            evaluation.decision = "TRADE ACCEPTED"
            evaluation.lastUpdate = Date()
            pending[parsed.symbol] = evaluation
            lock.unlock()
            finalize(parsed.symbol, decision: "TRADE ACCEPTED")
        }
    }

    private static func recordPillar(_ symbol: String, passed: Bool, name: String, contribution: Double, reason: String) {
        lock.lock()
        var evaluation = pending[symbol] ?? PendingEvaluation()
        if passed {
            evaluation.passed.removeAll { $0.name == name }
            evaluation.passed.append((name: name, contribution: contribution))
        } else {
            evaluation.failed.removeAll { $0.name == name }
            evaluation.failed.append((name: name, reason: reason))
        }
        evaluation.lastUpdate = Date()
        pending[symbol] = evaluation
        lock.unlock()
    }

    private static func finalize(_ symbol: String, decision: String) {
        lock.lock()
        guard var evaluation = pending.removeValue(forKey: symbol) else {
            lock.unlock()
            return
        }
        evaluation.decision = decision
        lock.unlock()

        SignalEvaluationAudit(
            symbol: symbol,
            direction: evaluation.direction,
            rawConfidence: evaluation.rawConfidence,
            historicalAdjustment: evaluation.historicalAdjustment,
            finalConfidence: evaluation.finalConfidence,
            threshold: evaluation.threshold,
            riskRewardPassed: evaluation.riskRewardKnown ? evaluation.riskRewardPassed : false,
            decision: decision,
            passedPillars: evaluation.passed,
            failedPillars: evaluation.failed
        ).emit()
    }

    private static func parsePillar(_ message: String) -> (symbol: String, passed: Bool, name: String, contribution: Double, reason: String)? {
        guard let range = message.range(of: "🔎 SIGNAL PILLAR | ") else { return nil }
        let tail = String(message[range.upperBound...])
        let parts = tail.components(separatedBy: " | ")
        guard parts.count >= 5 else { return nil }
        let symbol = parts[0]
        let passed = parts[1].contains("PASS")
        let name = parts[2]
        let contribution = extractSignedDouble(parts[parts.count - 2]) ?? 0
        let reason = parts.dropFirst(3).dropLast(2).joined(separator: " | ")
        return (symbol, passed, name, contribution, reason)
    }

    private static func parseScore(_ message: String) -> (symbol: String, direction: String, confidence: Double, threshold: Double)? {
        guard message.contains("🎯 SIGNAL SCORE | ") else { return nil }
        guard let symbol = capture(message, pattern: "🎯 SIGNAL SCORE \\| ([A-Z0-9]+) \\| direction=") else { return nil }
        guard let direction = capture(message, pattern: "direction=([^ |]+)") else { return nil }
        guard let confidence = captureDouble(message, key: "baseConfidence=") else { return nil }
        return (symbol, direction, confidence, 0)
    }

    private static func parseAdjustment(_ message: String) -> (symbol: String, adjustment: Double, finalConfidence: Double)? {
        guard message.contains("🧠 SIGNAL ADJUSTMENT | ") else { return nil }
        guard let symbol = capture(message, pattern: "🧠 SIGNAL ADJUSTMENT \\| ([A-Z0-9]+) \\|") else { return nil }
        guard let values = twoPercentValues(in: message) else { return nil }
        return (symbol, values.second - values.first, values.second)
    }

    private static func parseRR(_ message: String) -> (symbol: String, passed: Bool)? {
        guard message.contains("⚖️ SIGNAL GATE | ") else { return nil }
        guard let symbol = capture(message, pattern: "⚖️ SIGNAL GATE \\| ([A-Z0-9]+) \\|") else { return nil }
        return (symbol, message.contains("R:R=PASS"))
    }

    private static func parseDecision(_ message: String) -> (symbol: String, decision: String, finalConfidence: Double?, isTerminal: Bool)? {
        guard message.contains("🛑 SIGNAL DECISION | ") else { return nil }
        guard let symbol = capture(message, pattern: "🛑 SIGNAL DECISION \\| ([A-Z0-9]+) \\|") else { return nil }
        let confidence = captureDouble(message, key: "confidence=")
        return (symbol, message.contains("REJECTED") ? "NO TRADE — THRESHOLD/TYPE FAIL" : "NO TRADE", confidence, true)
    }

    private static func parseAccepted(_ message: String) -> (symbol: String, direction: String, confidence: Double)? {
        guard message.contains("🚀 HYBRID SIGNAL: ") else { return nil }
        guard let symbol = capture(message, pattern: "🚀 HYBRID SIGNAL: ([A-Z0-9]+) \\|") else { return nil }
        guard let confidence = captureDouble(message, key: "Confidence: ") else { return nil }
        return (symbol, "TRADE", confidence)
    }

    private static func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func captureDouble(_ text: String, key: String) -> Double? {
        guard let value = capture(text, pattern: NSRegularExpression.escapedPattern(for: key) + "(-?[0-9]+(?:\\.[0-9]+)?)") else { return nil }
        return Double(value)
    }

    private static func extractSignedDouble(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "+", with: "")
        return Double(cleaned.split(separator: " ").first ?? "")
    }

    private static func twoPercentValues(in text: String) -> (first: Double, second: Double)? {
        let pattern = "from ([0-9]+(?:\\.[0-9]+)?)% to ([0-9]+(?:\\.[0-9]+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text),
              let first = Double(text[r1]),
              let second = Double(text[r2]) else { return nil }
        return (first, second)
    }
}
