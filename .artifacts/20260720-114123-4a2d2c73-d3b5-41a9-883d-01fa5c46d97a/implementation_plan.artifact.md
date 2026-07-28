# Fix Signal Execution and Correlation Sync

The goal is to resolve issues where signals are generated but blocked by the `CorrelationFilter` or `RiskManagers` due to out-of-sync states or overly restrictive rules.

## User Review Required

- **Correlation Threshold**: Increased from 0.70 to 0.80 for more aggressive trading.
- **High Confidence Bypass**: Signals with confidence >= 95% will bypass the correlation group block.

## Proposed Changes

### [CorrelationFilter.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper App/ForexScalperApp/CorrelationFilter.swift)

- Update `correlationThreshold` to `0.80`.
- Update `canOpenTrade` to accept `confidence` and implement the "Elite Bypass".
- Add `syncActiveSymbols` to force-sync state.

```swift
    func canOpenTrade(symbol: String, confidence: Double = 0) async -> Bool {
        // ...
        for activeSymbol in activeSymbols {
            if areInSameGroup(symbol, activeSymbol) {
                if confidence >= 95.0 {
                    godLog("💎 High Confidence Bypass: Allowing correlated \(symbol) (\(confidence)%)", level: .info)
                    continue
                }
                // ...
            }
        }
        // ...
    }

    func syncActiveSymbols(_ symbols: Set<String>) async {
        activeSymbols = symbols
        godLog("📊 Correlation: Force-synced \(activeSymbols.count) active symbols", level: .info)
    }
```

---

### [ScalpingRiskManager.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper App/ForexScalperApp/ScalpingRiskManager.swift)

- Add duplicate symbol check in `canOpenTrade`.
- Add `syncActiveTrades` method.

---

### [RefactoredRiskManager.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper App/ForexScalperApp/RefactoredRiskManager.swift)

- Add duplicate symbol check in `canOpenTrade`.
- Add `syncActiveTrades` method.

---

### [ScalpingTradeMonitor.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper App/ForexScalperApp/ScalpingTradeMonitor.swift)

- Update `closeTrade` to unregister from `CorrelationFilter` and `ScalpingRiskManager` immediately.

---

### [TradeMonitor.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper App/ForexScalperApp/TradeMonitor.swift)

- Update `closeTrade` to unregister from `CorrelationFilter` and `RefactoredRiskManager` immediately.

---

### [RefactoredAppCoordinator.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper App/ForexScalperApp/RefactoredAppCoordinator.swift)

- Update `executeSmartOrder` to pass `signal.confidence` to `canOpenTrade`.
- Update `syncMT5Trades` to call `syncActiveSymbols` and `syncActiveTrades` with the actual active trades.

## Verification Plan

### Automated Tests
- None, verification will be via logs and monitoring live behavior.

### Manual Verification
- Generate two correlated signals (e.g. AUDUSD and AUDJPY) with high confidence and verify both are sent to MT5.
- Close a trade and verify the next signal for that symbol is NOT blocked immediately after.
- Check logs for "Force-synced" messages to confirm poller is working.
