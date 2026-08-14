from pathlib import Path

p = Path('ForexScalperApp/RefactoredAppCoordinator.swift')
s = p.read_text()

anchor = '''        var executionMode: MT5ExecutionMode = .market\n        var deviation: Int = 10\n        var filler: MT5FillingType = .ioc'''
replacement = '''        // Smart entry: do not chase an extended candle. When pullback mode is enabled,\n        // wait briefly for price to return toward the fast EMA/ATR entry zone. This is\n        // intentionally client-side because the current V10.5 EA /v1/order endpoint is\n        // a MARKET-only action; sending pending actions would reproduce the earlier\n        // "Unsupported order action" failure.\n        if await shouldWaitForPullback(symbol: symbol, signal: signal, atr: atrVal) {\n            godLog("📌 SMART ENTRY | \\(symbol) | pullback zone not reached yet | waiting up to 12s", level: .info)\n            godLog("📌 PENDING LIMIT | \\(symbol) | deferred safely: current EA bridge exposes market action only", level: .diagnostic)\n            var reached = false\n            for second in 1...12 {\n                try? await Task.sleep(nanoseconds: 1_000_000_000)\n                if await isPullbackEntryReady(symbol: symbol, signal: signal, atr: atrVal) {\n                    reached = true\n                    godLog("🎯 SMART ENTRY READY | \\(symbol) | pullback reached after \\(second)s", level: .success)\n                    break\n                }\n            }\n            if !reached {\n                godLog("⏱️ SMART ENTRY TIMEOUT | \\(symbol) | using spread/volatility-aware market execution", level: .warning)\n            }\n        }\n\n        var executionMode: MT5ExecutionMode = .market\n        var deviation: Int = 10\n        var filler: MT5FillingType = .ioc'''
if anchor not in s:
    raise SystemExit('smart-entry execution anchor not found')
s = s.replace(anchor, replacement, 1)

method_anchor = '    private func calculateLatestIndicators(symbol: String) async -> IndicatorSet? {'
methods = '''    private func shouldWaitForPullback(symbol: String, signal: Signal, atr: Double) async -> Bool {\n        guard await MainActor.run({ ScalpingConfig.shared.enablePullbackEntry }) else { return false }\n        guard let actor = marketData as? RefactoredMarketDataActor else { return false }\n        let candles = await actor.getCandles(symbol: symbol, timeframe: "1m")\n        guard candles.count >= 25, let current = candles.last?.close else { return false }\n        let ema = Indicators.ema(candles.map { $0.close }, period: 21).last ?? current\n        let distance = abs(current - ema)\n        return distance > max(atr * 0.35, symbol.contains("JPY") ? 0.0035 : 0.00035)\n    }\n\n    private func isPullbackEntryReady(symbol: String, signal: Signal, atr: Double) async -> Bool {\n        guard let actor = marketData as? RefactoredMarketDataActor else { return true }\n        let candles = await actor.getCandles(symbol: symbol, timeframe: "1m")\n        guard candles.count >= 25, let current = candles.last?.close else { return false }\n        let ema = Indicators.ema(candles.map { $0.close }, period: 21).last ?? current\n        let tolerance = max(atr * 0.15, symbol.contains("JPY") ? 0.0015 : 0.00015)\n        let nearEMA = abs(current - ema) <= tolerance\n        let directionAligned = signal.type == .buy ? current >= ema - tolerance : current <= ema + tolerance\n        return nearEMA && directionAligned\n    }\n\n'''
if method_anchor not in s:
    raise SystemExit('smart-entry method anchor not found')
s = s.replace(method_anchor, methods + method_anchor, 1)
p.write_text(s)

for path in [Path('.github/workflows/apply-smart-entry.yml'), Path('.github/patch_smart_entry.py')]:
    if path.exists(): path.unlink()
print('smart entry patch completed')
