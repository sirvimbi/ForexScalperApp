import Foundation
import SwiftUI
import Combine

struct DailyNewsConfiguration: Sendable, Equatable {
    var highImpactWeight: Double = 3.0
    var mediumImpactWeight: Double = 1.5
    var lowImpactWeight: Double = 0.5
    var macroKeywordFallbackMultiplier: Double = 0.15
    var directionalScoreClamp: Double = 4.0
    var pairBiasThreshold: Double = 1.0
    var watchCurrencyCount: Int = 6
    var eventLookbackHours: Double = 1.0
    var refreshIntervalMinutes: Double = 15.0
    private static func double(_ key: String, _ fallback: Double) -> Double { UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.double(forKey: key) }
    private static func int(_ key: String, _ fallback: Int) -> Int { UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.integer(forKey: key) }
    static func load() -> DailyNewsConfiguration {
        var c = DailyNewsConfiguration()
        c.highImpactWeight = double("dailyNews.highImpactWeight", c.highImpactWeight); c.mediumImpactWeight = double("dailyNews.mediumImpactWeight", c.mediumImpactWeight); c.lowImpactWeight = double("dailyNews.lowImpactWeight", c.lowImpactWeight); c.macroKeywordFallbackMultiplier = max(0, double("dailyNews.macroKeywordFallbackMultiplier", c.macroKeywordFallbackMultiplier)); c.directionalScoreClamp = max(0.1, double("dailyNews.directionalScoreClamp", c.directionalScoreClamp)); c.pairBiasThreshold = max(0.1, double("dailyNews.pairBiasThreshold", c.pairBiasThreshold)); c.watchCurrencyCount = min(12, max(2, int("dailyNews.watchCurrencyCount", c.watchCurrencyCount))); c.eventLookbackHours = max(0, double("dailyNews.eventLookbackHours", c.eventLookbackHours)); c.refreshIntervalMinutes = max(5, double("dailyNews.refreshIntervalMinutes", c.refreshIntervalMinutes)); return c
    }
    func save() {
        UserDefaults.standard.set(highImpactWeight, forKey: "dailyNews.highImpactWeight"); UserDefaults.standard.set(mediumImpactWeight, forKey: "dailyNews.mediumImpactWeight"); UserDefaults.standard.set(lowImpactWeight, forKey: "dailyNews.lowImpactWeight"); UserDefaults.standard.set(macroKeywordFallbackMultiplier, forKey: "dailyNews.macroKeywordFallbackMultiplier"); UserDefaults.standard.set(directionalScoreClamp, forKey: "dailyNews.directionalScoreClamp"); UserDefaults.standard.set(pairBiasThreshold, forKey: "dailyNews.pairBiasThreshold"); UserDefaults.standard.set(watchCurrencyCount, forKey: "dailyNews.watchCurrencyCount"); UserDefaults.standard.set(eventLookbackHours, forKey: "dailyNews.eventLookbackHours"); UserDefaults.standard.set(refreshIntervalMinutes, forKey: "dailyNews.refreshIntervalMinutes")
    }
}

@MainActor
final class DailyNewsSettingsController: ObservableObject {
    @Published var values: DailyNewsConfiguration = DailyNewsConfiguration.load()
    func reload() { values = DailyNewsConfiguration.load() }
    func save() { values.watchCurrencyCount = min(12, max(2, values.watchCurrencyCount)); values.save(); godLog("📰 DAILY NEWS SETTINGS | saved", level: .success) }
}
