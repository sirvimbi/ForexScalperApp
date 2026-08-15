from pathlib import Path

root = Path(__file__).resolve().parents[2]
engine = root / "ForexScalperApp" / "ScalpingSignalEngine.swift"
text = engine.read_text(encoding="utf-8")

needle = '''        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candlesByTimeframe["1m"]!)'''
insert = '''        var finalSignal = await generateSignal(symbol: symbol, indicators: indicators, candles1m: candlesByTimeframe["1m"]!)

        // V23 signal-accuracy layer: regime, divergence and micro-reversal confirmation.
        // This remains on the engine's isolation domain; it does not cross an actor boundary.
        let accuracy = SignalAccuracyEngine.assess(
            symbol: symbol,
            direction: finalSignal.type,
            candles: candlesByTimeframe["1m"]!
        )
        godLog("🧠 ACCURACY CHECK | \\(symbol) | approved=\\(accuracy.approved) | regime=\\(accuracy.regime) | H=\\(String(format: \"%.2f\", accuracy.hurst)) | chop=\\(String(format: \"%.1f\", accuracy.choppiness)) | \\(accuracy.reasons.joined(separator: \"; \"))", level: accuracy.approved ? .info : .warning)
        finalSignal = finalSignal.withSelfLearningInsight(accuracy.insight)
        guard accuracy.approved else {
            godLog("🛑 ACCURACY GATE | \\(symbol) | signal held/rejected pending better price action", level: .warning)
            return nil
        }'''

if needle not in text:
    raise SystemExit("ScalpingSignalEngine integration anchor not found; source layout changed and was not modified.")
if "SignalAccuracyEngine.assess(" in text:
    raise SystemExit("Signal accuracy integration already present; refusing duplicate insertion.")

text = text.replace(needle, insert, 1)
engine.write_text(text, encoding="utf-8")
print("Integrated SignalAccuracyEngine into evaluateScalpingSignal")
