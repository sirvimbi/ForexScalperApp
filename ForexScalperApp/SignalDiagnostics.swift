import Foundation

/// Makes the signal engine's existing evaluation output explicit and easy to follow in real time.
/// The engine remains the authority for the decision; this component only observes and explains logs.
enum SignalDiagnostics {
    static func install() {
        NotificationCenter.default.addObserver(
            forName: .newLogEntry,
            object: nil,
            queue: nil
        ) { notification in
            guard let entry = notification.object as? LogEntry else { return }
            let message = entry.message
            guard !message.contains("🧭 SIGNAL TRACE") else { return }

            if message.contains("📊 EVAL:") {
                emitTrace(from: message, kind: "EVALUATION")
            } else if message.contains("🚀 HYBRID SIGNAL:") || message.contains("⚡️ FAST SIGNAL:") {
                emitTrace(from: message, kind: "ACCEPTED")
            } else if message.contains("skipped:") && message.contains("ScalpingSignalEngine.swift") {
                emitTrace(from: message, kind: "REJECTED")
            }
        }

        godLog("🧭 Signal diagnostics installed — live confidence/pillar decisions enabled", level: .diagnostic)
    }

    private static func emitTrace(from message: String, kind: String) {
        if let range = message.range(of: "📊 EVAL:") {
            let evaluation = String(message[range.lowerBound...])
            godLog("🧭 SIGNAL TRACE [EVALUATION] \(evaluation)", level: .diagnostic)
        } else {
            godLog("🧭 SIGNAL TRACE [\(kind)] \(message)", level: kind == "REJECTED" ? .warning : .success)
        }
    }
}
