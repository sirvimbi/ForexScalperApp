import Foundation
import Combine

@MainActor
class SignalTester: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    @Published var testResults: [String] = []
    
    func testSignalGeneration(coordinator: RefactoredAppCoordinator, symbol: String) {
        Task {
            await testSymbol(coordinator: coordinator, symbol: symbol)
        }
    }
    
    private func testSymbol(coordinator: RefactoredAppCoordinator, symbol: String) async {
        await addResult("🔍 Testing signal generation for \(symbol)")
        
        // Get the market data from coordinator
        // Note: You'll need to expose this or create a way to access it
        // For now, let's create a simple test with mock data
        
        await testWithMockData(symbol: symbol)
    }
    
    private func testWithMockData(symbol: String) async {
        // Create mock bullish data
        await addResult("\n📈 Testing BULLISH scenario:")
        let bullishFeatures: [String: Double] = [
            "returns": 0.005,
            "high_low_pct": 0.008,
            "close_open_pct": 0.003,
            "sma_10": 1.2345,
            "sma_20": 1.2330,
            "sma_50": 1.2300,
            "ema_12": 1.2340,
            "ema_26": 1.2320,
            "rsi": 65.0,
            "macd": 0.002,
            "macd_signal": 0.001,
            "macd_hist": 0.001,
            "bb_width": 0.02,
            "bb_position": 0.8,
            "atr_pct": 0.005,
            "volume_ratio": 1.5
        ]
        
        let mlModel = MLModelHandler()
        let prediction = await mlModel.predictSignal(features: bullishFeatures)
        
        if let (signal, confidence) = prediction {
            await addResult("✅ ML Prediction: \(signal) with confidence: \(String(format: "%.2f", confidence * 100))%")
        } else {
            await addResult("❌ No prediction from ML model")
        }
        
        // Test rule-based fallback
        await addResult("\n📊 Testing rule-based signals:")
        
        // Test RSI oversold condition
        let oversoldFeatures = bullishFeatures.merging(["rsi": 30.0]) { $1 }
        let rulePrediction = await mlModel.predictSignal(features: oversoldFeatures)
        if let (signal, confidence) = rulePrediction {
            await addResult("✅ RSI Oversold: \(signal) with confidence: \(String(format: "%.2f", confidence * 100))%")
        }
        
        // Test RSI overbought condition
        let overboughtFeatures = bullishFeatures.merging(["rsi": 70.0]) { $1 }
        let rulePrediction2 = await mlModel.predictSignal(features: overboughtFeatures)
        if let (signal, confidence) = rulePrediction2 {
            await addResult("✅ RSI Overbought: \(signal) with confidence: \(String(format: "%.2f", confidence * 100))%")
        }
    }
    
    private func addResult(_ message: String) async {
        await MainActor.run {
            testResults.append(message)
            print(message)
        }
    }
}

