import Foundation
import CoreML
import Combine

actor MLModelHandler {
    private var model: MLModel?
    private var isModelLoaded = false
    private var featureNames: [String] = []

    #if DEBUG
    /// Allow building/running without a valid TradingModel.mlmodel present.
    /// Set this to `true` to completely skip Core ML loading when the model is broken or missing.
    private let skipModelLoading = ProcessInfo.processInfo.environment["SKIP_COREML"] != nil
    #else
    private let skipModelLoading = false
    #endif
    
    init() {
        if !skipModelLoading {
            Task {
                await loadModel()
            }
        } else {
            print("⚠️ SKIPPING Core ML model loading due to SKIP_COREML env var. Predictions will be disabled.")
        }
    }
    
    private func loadModel() {
        if skipModelLoading {
            self.model = nil
            self.isModelLoaded = false
            return
        }
        
        // Prefer compiled model packaged in the app bundle
        if let compiledURL = Bundle.main.url(forResource: "TradingModel", withExtension: "mlmodelc") {
            do {
                self.model = try MLModel(contentsOf: compiledURL)
                self.isModelLoaded = true
                print("✅ Core ML model loaded successfully from mlmodelc")
            } catch {
                print("❌ Failed to load compiled model TradingModel.mlmodelc from bundle: \(error)")
            }
        }

        // If not loaded yet, try to compile a raw .mlmodel from the bundle
        if self.model == nil, let rawModelURL = Bundle.main.url(forResource: "TradingModel", withExtension: "mlmodel") {
            do {
                let compiledURL = try MLModel.compileModel(at: rawModelURL)
                self.model = try MLModel(contentsOf: compiledURL)
                self.isModelLoaded = true
                print("✅ Core ML model compiled and loaded from mlmodel")
            } catch {
                print("❌ Failed to compile/load TradingModel.mlmodel from bundle: \(error)")
            }
        }

        // If still not loaded, give a concise error
        guard let localModel = self.model else {
            print("❌ Could not load Core ML model. Ensure TradingModel.mlmodelc is included in the app target.")
            return
        }

        // Print model info
        print("📊 Model description: \(localModel.modelDescription)")
        print("📊 Inputs: \(localModel.modelDescription.inputDescriptionsByName)")
        print("📊 Outputs: \(localModel.modelDescription.outputDescriptionsByName)")
    }
    
    func predictSignal(features: [String: Double]) async -> (signal: TradeSignal, confidence: Double)? {
        // Try ML model first if available
        if !skipModelLoading && isModelLoaded, let localModel = self.model {
            if let mlResult = await tryMLPrediction(with: localModel, features: features) {
                // If ML model has high confidence, use it
                if mlResult.confidence > 0.7 {
                    print("📊 Using ML prediction with confidence: \(String(format: "%.2f", mlResult.confidence))")
                    return mlResult
                } else {
                    print("📊 ML confidence too low (\(String(format: "%.2f", mlResult.confidence))), falling back to rules")
                }
            }
        }
        
        // Fallback to rule-based signals
        print("📊 Generating rule-based signal")
        return generateRuleBasedSignal(features: features)
    }
    
    private func tryMLPrediction(with localModel: MLModel, features: [String: Double]) async -> (signal: TradeSignal, confidence: Double)? {
        do {
            // Ensure all 16 features are present with defaults
            let orderedFeatures: [Double] = [
                features["returns"] ?? 0.0,
                features["high_low_pct"] ?? 0.0,
                features["close_open_pct"] ?? 0.0,
                features["sma_10"] ?? 0.0,
                features["sma_20"] ?? 0.0,
                features["sma_50"] ?? 0.0,
                features["ema_12"] ?? 0.0,
                features["ema_26"] ?? 0.0,
                features["rsi"] ?? 50.0,
                features["macd"] ?? 0.0,
                features["macd_signal"] ?? 0.0,
                features["macd_hist"] ?? 0.0,
                features["bb_width"] ?? 0.02,
                features["bb_position"] ?? 0.5,
                features["atr_pct"] ?? 0.005,
                features["volume_ratio"] ?? 1.0
            ]
            
            // Create MLMultiArray
            let multiArray = try MLMultiArray(shape: [1, 16] as [NSNumber], dataType: .double)
            
            // Copy values
            for (index, value) in orderedFeatures.enumerated() {
                multiArray[index] = NSNumber(value: value)
            }
            
            // Create input dictionary - try different input names
            var input: MLDictionaryFeatureProvider
            
            if localModel.modelDescription.inputDescriptionsByName.keys.contains("input") {
                input = try MLDictionaryFeatureProvider(dictionary: ["input": multiArray])
            } else if localModel.modelDescription.inputDescriptionsByName.keys.contains("features") {
                input = try MLDictionaryFeatureProvider(dictionary: ["features": multiArray])
            } else {
                // Try the first input name
                let inputName = localModel.modelDescription.inputDescriptionsByName.keys.first ?? "input"
                input = try MLDictionaryFeatureProvider(dictionary: [inputName: multiArray])
            }
            
            // Make prediction
            let prediction = try await localModel.prediction(from: input)
            
            // Extract probabilities from classProbability dictionary
            if let probabilities = prediction.featureValue(for: "classProbability")?.dictionaryValue as? [Int64: Double] {
                let buyProb = probabilities[1] ?? 0.0  // class 1 = buy
                let sellProb = probabilities[0] ?? 0.0 // class 0 = sell
                let holdProb = probabilities[2] ?? 0.0 // class 2 = hold
                
                // Normalize probabilities to ensure they sum to 1.0
                let totalProb = buyProb + sellProb + holdProb
                let normalizedBuyProb = totalProb > 0 ? buyProb / totalProb : 0
                let normalizedSellProb = totalProb > 0 ? sellProb / totalProb : 0
                let normalizedHoldProb = totalProb > 0 ? holdProb / totalProb : 0
                
                print("📊 ML Raw Probabilities - Buy: \(String(format: "%.2f", buyProb * 100))%, Sell: \(String(format: "%.2f", sellProb * 100))%, Hold: \(String(format: "%.2f", holdProb * 100))%")
                print("📊 ML Normalized Probabilities - Buy: \(String(format: "%.2f", normalizedBuyProb * 100))%, Sell: \(String(format: "%.2f", normalizedSellProb * 100))%, Hold: \(String(format: "%.2f", normalizedHoldProb * 100))%")
                
                // Find the maximum normalized probability
                let maxProb = max(normalizedBuyProb, normalizedSellProb, normalizedHoldProb)
                let confidence = maxProb
                
                if maxProb == normalizedBuyProb && normalizedBuyProb > 0.5 {
                    return (.buy, confidence)
                } else if maxProb == normalizedSellProb && normalizedSellProb > 0.5 {
                    return (.sell, confidence)
                } else if maxProb == normalizedHoldProb && normalizedHoldProb > 0.5 {
                    return (.neutral, confidence)
                }
            }
            
            // Fallback to classLabel
            if let classLabel = prediction.featureValue(for: "classLabel")?.int64Value {
                print("📊 ML Class Label: \(classLabel)")
                switch classLabel {
                case 1: return (.buy, 0.8)
                case 0: return (.sell, 0.8)
                default: return nil
                }
            }
            
            return nil
        } catch {
            print("❌ ML Prediction error: \(error)")
            return nil
        }
    }
    
    private func generateRuleBasedSignal(features: [String: Double]) -> (signal: TradeSignal, confidence: Double)? {
        guard let rsi = features["rsi"],
              let macd = features["macd"],
              let macdHist = features["macd_hist"],
              let sma10 = features["sma_10"],
              let sma20 = features["sma_20"],
              let sma50 = features["sma_50"],
              let ema12 = features["ema_12"],
              let ema26 = features["ema_26"],
              let volumeRatio = features["volume_ratio"],
              let returns = features["returns"],
              let bbPosition = features["bb_position"],
              let _ = features["atr_pct"] else {
            print("⚠️ Insufficient features for rule-based signal")
            return nil
        }
        
        // Print features for debugging
        print("📊 Rule-based features - RSI: \(String(format: "%.1f", rsi)), MACD: \(String(format: "%.5f", macd)), Volume: \(String(format: "%.2f", volumeRatio))")
        
        // ===== BUY SIGNAL CONDITIONS =====
        
        // Condition 1: RSI oversold with MACD bullish
        if rsi < 35 && macd > 0 && macdHist > 0 && volumeRatio > 1.1 {
            let confidence = min(0.75 + (0.15 * (1 - rsi/35)), 0.90)
            print("📊 RULE: RSI oversold + MACD bullish → BUY (confidence: \(String(format: "%.2f", confidence))")
            return (.buy, confidence)
        }
        
        // Condition 2: Golden cross (SMA 10 crosses above SMA 20) with volume
        if sma10 > sma20 && ema12 > ema26 && returns > 0 && volumeRatio > 1.2 {
            let confidence = 0.80
            print("📊 RULE: Golden cross → BUY")
            return (.buy, confidence)
        }
        
        // Condition 3: Pullback in uptrend (price near lower BB with bullish MACD)
        if bbPosition < 0.3 && macd > 0 && rsi > 40 && rsi < 60 && volumeRatio > 1.0 {
            let confidence = 0.75
            print("📊 RULE: Pullback in uptrend → BUY")
            return (.buy, confidence)
        }
        
        // Condition 4: Strong volume breakout with positive returns
        if returns > 0.001 && volumeRatio > 1.5 && macd > 0 && rsi > 50 && rsi < 70 {
            let confidence = 0.85
            print("📊 RULE: Volume breakout → BUY")
            return (.buy, confidence)
        }
        
        // Condition 5: EMA alignment (all EMAs trending up)
        if ema12 > ema26 && ema26 > sma50 && returns > 0 && rsi > 55 && rsi < 75 {
            let confidence = 0.78
            print("📊 RULE: EMA alignment → BUY")
            return (.buy, confidence)
        }
        
        // ===== SELL SIGNAL CONDITIONS =====
        
        // Condition 6: RSI overbought with MACD bearish
        if rsi > 65 && macd < 0 && macdHist < 0 && volumeRatio > 1.1 {
            let confidence = min(0.75 + (0.15 * (rsi/65 - 1)), 0.90)
            print("📊 RULE: RSI overbought + MACD bearish → SELL (confidence: \(String(format: "%.2f", confidence))")
            return (.sell, confidence)
        }
        
        // Condition 7: Death cross (SMA 10 crosses below SMA 20) with volume
        if sma10 < sma20 && ema12 < ema26 && returns < 0 && volumeRatio > 1.2 {
            let confidence = 0.80
            print("📊 RULE: Death cross → SELL")
            return (.sell, confidence)
        }
        
        // Condition 8: Rejection from upper BB with bearish MACD
        if bbPosition > 0.7 && macd < 0 && rsi > 60 && volumeRatio > 1.0 {
            let confidence = 0.75
            print("📊 RULE: BB rejection → SELL")
            return (.sell, confidence)
        }
        
        // Condition 9: Volume dump with negative returns
        if returns < -0.001 && volumeRatio > 1.5 && macd < 0 && rsi < 50 {
            let confidence = 0.82
            print("📊 RULE: Volume dump → SELL")
            return (.sell, confidence)
        }
        
        // Condition 10: EMA alignment (all EMAs trending down)
        if ema12 < ema26 && ema26 < sma50 && returns < 0 && rsi < 45 {
            let confidence = 0.78
            print("📊 RULE: EMA alignment down → SELL")
            return (.sell, confidence)
        }
        
        // ===== WEAKER SIGNALS =====
        
        // Weak buy: Just RSI oversold without confirmation
        if rsi < 30 {
            print("📊 RULE: RSI oversold only → Weak BUY")
            return (.buy, 0.60)
        }
        
        // Weak sell: Just RSI overbought without confirmation
        if rsi > 70 {
            print("📊 RULE: RSI overbought only → Weak SELL")
            return (.sell, 0.60)
        }
        
        // Weak buy: MACD bullish but low volume
        if macd > 0.0005 && macdHist > 0 && volumeRatio > 0.8 {
            print("📊 RULE: MACD bullish only → Weak BUY")
            return (.buy, 0.65)
        }
        
        // Weak sell: MACD bearish but low volume
        if macd < -0.0005 && macdHist < 0 && volumeRatio > 0.8 {
            print("📊 RULE: MACD bearish only → Weak SELL")
            return (.sell, 0.65)
        }
        
        // No clear signal
        print("📊 No rule-based signal generated")
        return nil
    }
    
    func extractFeatures(symbol: String, candles1m: [Kline], candles5m: [Kline], candles1h: [Kline]) async -> [String: Double] {
        let closes1m = candles1m.map { $0.close }
        let volumes1m = candles1m.map { $0.volume }
        let highs1m = candles1m.map { $0.high }
        let lows1m = candles1m.map { $0.low }
        
        guard let lastClose = closes1m.last,
              let lastOpen = candles1m.last?.open,
              let lastHigh = highs1m.last,
              let lastLow = lows1m.last,
              let lastVolume = volumes1m.last else {
            print("⚠️ Not enough data for feature extraction for \(symbol)")
            return [:]
        }
        
        // Calculate real indicators
        let returns = closes1m.count > 1 ? (lastClose - closes1m[closes1m.count - 2]) / lastClose : 0
        
        let highLowPct = (lastHigh - lastLow) / lastClose
        let closeOpenPct = (lastClose - lastOpen) / lastOpen
        
        // Moving averages
        let sma10 = closes1m.suffix(10).reduce(0, +) / Double(min(10, closes1m.count))
        let sma20 = closes1m.suffix(20).reduce(0, +) / Double(min(20, closes1m.count))
        let sma50 = closes1m.suffix(50).reduce(0, +) / Double(min(50, closes1m.count))
        
        // EMA calculations
        let ema12 = Indicators.ema(closes1m, period: 12).last ?? lastClose
        let ema26 = Indicators.ema(closes1m, period: 26).last ?? lastClose
        
        // RSI
        let rsi = Indicators.rsi(closes1m, period: 14).last ?? 50.0
        
        // MACD
        let macdResult = Indicators.macd(closes1m)
        let macd = macdResult.macd.last ?? 0
        let macdSignal = macdResult.signal.last ?? 0
        let macdHist = macdResult.histogram.last ?? 0
        
        // Bollinger Bands
        let bbResult = Indicators.bollingerBands(closes1m)
        let bbWidth = (bbResult.upper.last ?? 0) - (bbResult.lower.last ?? 0)
        let bbPosition = bbWidth > 0 ? (lastClose - (bbResult.lower.last ?? 0)) / bbWidth : 0.5
        
        // ATR
        let atr = Indicators.atr(candles1m, period: 14).last ?? 0
        let atrPct = atr / lastClose
        
        // Volume ratio
        let avgVolume = volumes1m.suffix(20).reduce(0, +) / Double(max(1, min(20, volumes1m.count)))
        let volumeRatio = avgVolume > 0 ? lastVolume / avgVolume : 1.0
        
        // Debug print key features
        print("📊 Features for \(symbol): RSI=\(String(format: "%.1f", rsi)), MACD=\(String(format: "%.5f", macd)), Returns=\(String(format: "%.5f", returns)), Volume=\(String(format: "%.2f", volumeRatio))")
        
        return [
            "returns": returns,
            "high_low_pct": highLowPct,
            "close_open_pct": closeOpenPct,
            "sma_10": sma10,
            "sma_20": sma20,
            "sma_50": sma50,
            "ema_12": ema12,
            "ema_26": ema26,
            "rsi": rsi,
            "macd": macd,
            "macd_signal": macdSignal,
            "macd_hist": macdHist,
            "bb_width": bbWidth,
            "bb_position": bbPosition,
            "atr_pct": atrPct,
            "volume_ratio": volumeRatio
        ]
    }
    
    // Add to MLModelHandler class
    func debugPrintFeatureRequirements() {
        print("\n📊 ML Model Feature Requirements:")
        if let localModel = self.model {
            print("Inputs: \(localModel.modelDescription.inputDescriptionsByName)")
            print("Expected feature count: \(localModel.modelDescription.inputDescriptionsByName.first?.value.multiArrayConstraint?.shape.first?.intValue ?? 16)")
        } else {
            print("⚠️ No model loaded, using rule-based only")
            print("Rule-based features required: returns, high_low_pct, close_open_pct, sma_10, sma_20, sma_50, ema_12, ema_26, rsi, macd, macd_signal, macd_hist, bb_width, bb_position, atr_pct, volume_ratio")
        }
    }
}

enum TradeSignal: Int {
    case sell = -1
    case neutral = 0
    case buy = 1
}
