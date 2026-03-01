import Foundation
import SwiftUI
import Combine

class TradingModelBridge: ObservableObject {
    @Published var predictionResult: String = "Ready"
    @Published var predictionColor: Color = .gray
    
    func makePrediction(featureValues: [String]) -> Bool {
        // Convert strings to doubles, handle empty strings
        let features = featureValues.map { Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        
        guard features.count == 16 else {
            predictionResult = "Invalid Input"
            predictionColor = .red
            return false
        }
        
        // Here you would call your ML model
        // For now, return a simulated result based on some logic
        let rsi = features[8] // RSI is at index 8
        let macd = features[9] // MACD is at index 9
        let volumeRatio = features[15] // Volume ratio is at index 15
        
        if rsi > 60 && macd > 0 && volumeRatio > 1.2 {
            predictionResult = "BUY"
            predictionColor = .green
        } else if rsi < 40 && macd < 0 && volumeRatio > 1.2 {
            predictionResult = "SELL"
            predictionColor = .red
        } else {
            predictionResult = "HOLD"
            predictionColor = .orange
        }
        
        return true
    }
}
