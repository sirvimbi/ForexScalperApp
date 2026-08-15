import Foundation

/// Module-level bootstrap keeps daily macro intelligence alive without requiring a view to own it.
@MainActor
private let dailyNewsIntelligenceBootstrap: DailyNewsIntelligence = .shared

@MainActor
func startDailyNewsIntelligence() {
    _ = dailyNewsIntelligenceBootstrap
}
