# MacGoldTrader

A deliberately small native SwiftUI macOS 26+ app for manual XAUUSD BUY/SELL market orders through the local MT5 bridge.

## What it sends

The app sends an HTTP `POST` to the configured endpoint with this payload shape:

```json
{
  "symbol": "XAUUSD",
  "action": "BUY",
  "volume": 0.01,
  "price": 0,
  "sl": 0,
  "tp": 0,
  "type": "MARKET",
  "comment": "GOLD_NO_STOPS",
  "magic": 888888,
  "deviation": 15
}
```

SELL uses the same payload with `action: "SELL"`.

The app uses `URLSession` for the POST rather than launching a shell. It also displays the equivalent curl command after every order, so the request is easy to inspect and reproduce in Terminal.

## User-configurable fields

- **Order endpoint:** defaults to `http://127.0.0.1:8890/v1/order`
- **Symbol:** defaults to `XAUUSD`
- **Volume:** defaults to `0.01`
- **Deviation:** defaults to `15`

Settings are remembered with `UserDefaults`.

## Build in Xcode

1. Open `MacGoldTrader/Package.swift` in Xcode 26 or later.
2. Select the **MacGoldTrader** executable scheme.
3. Run it on **My Mac**.
4. For distribution, use Xcode's Product > Archive workflow.

No third-party packages are required. The UI and networking use Apple system frameworks only, keeping the app footprint small.

## Important

This is a manual execution client. It does not generate signals, calculate stops, manage positions, or modify orders after submission. The local bridge/MT5 terminal remains responsible for accepting and executing the order.
