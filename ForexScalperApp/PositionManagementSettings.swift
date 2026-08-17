import Foundation

/// Runtime-adjustable position-management controls shared by the Swift execution authority
/// and the Settings UI. The MT5 EA remains an execution/validation bridge only.
struct PositionManagementSettings: Sendable, Equatable {
    static let breakevenEnabledKey = "positionManagement.breakevenEnabled"
    static let breakevenTriggerPipsKey = "positionManagement.breakevenTriggerPips"
    static let breakevenOffsetPipsKey = "positionManagement.breakevenOffsetPips"
    static let trailingDistancePipsKey = "positionManagement.trailingDistancePips"
    static let trailingStepPipsKey = "positionManagement.trailingStepPips"

    var breakevenEnabled: Bool
    var breakevenTriggerPips: Double
    var breakevenOffsetPips: Double
    var trailingDistancePips: Double
    var trailingStepPips: Double

    static let defaults = PositionManagementSettings(
        breakevenEnabled: true,
        breakevenTriggerPips: 10,
        breakevenOffsetPips: 0,
        trailingDistancePips: 6,
        trailingStepPips: 0.5
    )

    static func load(from defaults: UserDefaults = .standard) -> PositionManagementSettings {
        let savedTrigger = defaults.object(forKey: breakevenTriggerPipsKey) as? Double
        let savedOffset = defaults.object(forKey: breakevenOffsetPipsKey) as? Double
        let savedDistance = defaults.object(forKey: trailingDistancePipsKey) as? Double
        let savedStep = defaults.object(forKey: trailingStepPipsKey) as? Double
        return PositionManagementSettings(
            breakevenEnabled: defaults.object(forKey: breakevenEnabledKey) as? Bool ?? Self.defaults.breakevenEnabled,
            breakevenTriggerPips: savedTrigger ?? Self.defaults.breakevenTriggerPips,
            breakevenOffsetPips: savedOffset ?? Self.defaults.breakevenOffsetPips,
            trailingDistancePips: savedDistance ?? Self.defaults.trailingDistancePips,
            trailingStepPips: savedStep ?? Self.defaults.trailingStepPips
        ).validated()
    }

    func save(to defaults: UserDefaults = .standard) {
        let value = validated()
        defaults.set(value.breakevenEnabled, forKey: Self.breakevenEnabledKey)
        defaults.set(value.breakevenTriggerPips, forKey: Self.breakevenTriggerPipsKey)
        defaults.set(value.breakevenOffsetPips, forKey: Self.breakevenOffsetPipsKey)
        defaults.set(value.trailingDistancePips, forKey: Self.trailingDistancePipsKey)
        defaults.set(value.trailingStepPips, forKey: Self.trailingStepPipsKey)
    }

    func validated() -> PositionManagementSettings {
        PositionManagementSettings(
            breakevenEnabled: breakevenEnabled,
            breakevenTriggerPips: max(0, breakevenTriggerPips),
            breakevenOffsetPips: max(-10, min(10, breakevenOffsetPips)),
            trailingDistancePips: max(0.1, trailingDistancePips),
            trailingStepPips: max(0.1, trailingStepPips)
        )
    }
}
