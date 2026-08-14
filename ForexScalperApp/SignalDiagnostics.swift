import Foundation

/// Observes the signal engine's existing logs and keeps the in-app trace readable.
/// The signal engine remains the sole authority for scoring and trade decisions.
enum SignalDiagnostics {
    private static let lock = NSLock()
    private static var installed = false

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
            let message = entry.message

            // The engine now emits the complete pillar-by-pillar trace itself.
            // Do not echo EVAL/PILLAR messages: that was creating a second copy of
            // the same analysis in the console.
            guard !message.contains("🧭 SIGNAL TRACE"),
                  !message.contains("🔎 SIGNAL PILLAR"),
                  !message.contains("📊 EVAL:") else { return }

            if message.contains("🚀 HYBRID SIGNAL:") || message.contains("⚡️ FAST SIGNAL:") {
                godLog("🧭 SIGNAL TRACE [ACCEPTED] \(message)", level: .diagnostic)
            }
        }

        godLog("🧭 Signal diagnostics installed — live confidence/pillar decisions enabled", level: .diagnostic)
    }
}
