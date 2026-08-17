# V22 protection execution

- Swift owns configurable protection settings.
- `SettingsRuntimeBridge.saveAll()` synchronizes TP1/TP2/TP3 percentages/distances and trailing activation to MT5 terminal Global Variables.
- EA V22 owns broker-side partial closes, TP1-triggered breakeven, and forward-only trailing.
- Fixed broker TP supplied by the entry signal is removed immediately after the position transaction so it cannot close the entire position before staged TP levels.
- Protection state is persisted per ticket in MT5 Global Variables so TP stages are not repeated after EA restart.
- The existing V22 trailing curve remains unchanged; only its activation is user configurable.
