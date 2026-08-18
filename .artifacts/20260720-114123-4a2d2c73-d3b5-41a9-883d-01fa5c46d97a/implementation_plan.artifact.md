# Fix Commodity and Index Trade Execution

Investigating why signals for XAUUSD, USOIL, and indices like NAS100/US30 are not executing revealed that the primary cause is the hardcoded pip-size logic and strict MT5 retcode validation, which doesn't account for the unique tick sizes and return behaviors of non-Forex symbols.

## User Review Required

- **Broker Suffix Alignment**: I am ensuring that the `brokerSuffix` (e.g., "m") is applied only to the final MT5 order symbol, while internal logic uses normalized names.
- **Risk/Reward Thresholds**: Commodities and Indices often have much larger price numbers than Forex (e.g., US30 at 40,000 vs EURUSD at 1.08). I am normalizing these to Ensure R:R checks pass for all asset classes.

## Proposed Changes

### [MT5 Core]

#### [MT5Service.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper%20App/ForexScalperApp/MT5Service.swift)

- **Smarter Symbol Resolution**: Update `executeTrade` to handle symbol names more robustly, ensuring indices like "NAS100" are correctly suffixed and formatted for the bridge.
- **Relaxed Retcode Validation**: Accept a broader range of "success" retcodes (e.g., `10025` for "Placed" or `10009` for "Done") as different asset classes and brokers return different codes for index orders.
- **Precision Logging**: Add point/digit logging to verify price alignment with MT5's expectations.

---

### [Risk & Execution]

#### [ScalpingRiskManager.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper%20App/ForexScalperApp/ScalpingRiskManager.swift)

- **Dynamic Pip Calculation**: Replace hardcoded `0.01/0.0001` pip sizes with dynamic `point` values from MT5 symbol info. This ensures Gold (0.1/0.01) and Indices (1.0) distances are calculated correctly.
- **Normalized Volume Limits**: Use MT5-reported `volume_step` to ensure orders like 0.1 for Gold don't fail due to rounding errors.

#### [RRLock.swift](file:///Users/kilu/Documents/Projects/AppCoordinator/Scalper%20App/ForexScalperApp/RRLock.swift)

- **Asset-Class Awareness**: Normalize the "Price move too small" check. Currently, a 1-point move on US30 is considered "huge" by Forex standards but might be rejected if the logic assumes 5-digit precision.

## Verification Plan

### Automated Tests
- I will run the `xcodebuild` command to ensure the project compiles with the new logic.

### Manual Verification
- **Log Review**: I will monitor the logcat to confirm that `executeTrade` is called with the correctly suffixed symbol (e.g., `XAUUSDm` instead of `XAUUSD`).
- **Retcode Check**: I will verify that `retcode` 10009/10008 are no longer the *only* allowed success codes if the broker returns 10025.
