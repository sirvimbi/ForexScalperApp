# Settings / Runtime Audit

This change set makes settings runtime behavior explicit:

- `ScalpingConfig.shared` remains the live source consumed by the signal/risk engine.
- `SettingsRuntimeBridge` persists legacy/missing settings (`useManualLot`, news pause windows, max hold/trade limits) whenever the shared configuration changes.
- Dashboard account/equity/history refresh is independent of the selected tab.
- The History tab has an explicit broker/local refresh path and native CSV export.
- The Performance tab is now a realized-performance intelligence dashboard.
- The signal card no longer nests actionable Buttons inside an outer Button, so Deny cannot open the execution sheet.
- Signal and macOS execution overlay text uses explicit white foreground styling where the dark UI requires it.
- The in-app log buffer rotates every 30 minutes. Xcode's own Debug Console remains owned by Xcode and cannot be erased programmatically by the app.
