import SwiftUI

struct ContentView: View {
    @StateObject private var modelBridge = TradingModelBridge()
    
    @State private var returns: String = ""
    @State private var highLowPct: String = ""
    @State private var closeOpenPct: String = ""
    @State private var sma10: String = ""
    @State private var sma20: String = ""
    @State private var sma50: String = ""
    @State private var ema12: String = ""
    @State private var ema26: String = ""
    @State private var rsi: String = ""
    @State private var macd: String = ""
    @State private var macdSignal: String = ""
    @State private var macdHist: String = ""
    @State private var bbWidth: String = ""
    @State private var bbPosition: String = ""
    @State private var atrPct: String = ""
    @State private var volumeRatio: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Trading Signal")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(modelBridge.predictionResult)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(modelBridge.predictionColor)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    Group {
                        Text("Market Features")
                            .font(.title2)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            InputField(label: "Returns (%)", text: $returns)
                            InputField(label: "High/Low %", text: $highLowPct)
                            InputField(label: "Close/Open %", text: $closeOpenPct)
                            InputField(label: "SMA 10", text: $sma10)
                            InputField(label: "SMA 20", text: $sma20)
                            InputField(label: "SMA 50", text: $sma50)
                            InputField(label: "EMA 12", text: $ema12)
                            InputField(label: "EMA 26", text: $ema26)
                        }
                        
                        Text("Technical Indicators")
                            .font(.title2)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            InputField(label: "RSI", text: $rsi)
                            InputField(label: "MACD", text: $macd)
                            InputField(label: "MACD Signal", text: $macdSignal)
                            InputField(label: "MACD Hist", text: $macdHist)
                            InputField(label: "BB Width", text: $bbWidth)
                            InputField(label: "BB Position", text: $bbPosition)
                            InputField(label: "ATR %", text: $atrPct)
                            InputField(label: "Volume Ratio", text: $volumeRatio)
                        }
                    }

                    NavigationLink {
                        RunnerContinuationSettingsView()
                    } label: {
                        Label("Runner Continuation Settings", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Runner Continuation and Anti-Exhaustion Settings")
                    
                    Button(action: makePrediction) {
                        Text("Get Trading Signal")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Trading Signal")
        }
    }
    
    func makePrediction() {
        let featureValues = [
            returns, highLowPct, closeOpenPct, sma10, sma20, sma50,
            ema12, ema26, rsi, macd, macdSignal, macdHist,
            bbWidth, bbPosition, atrPct, volumeRatio
        ]
        _ = modelBridge.makePrediction(featureValues: featureValues)
    }
    
    func fillBullishData() {
        returns = "0.5"
        highLowPct = "0.8"
        closeOpenPct = "0.3"
        sma10 = "1.2345"
        sma20 = "1.2330"
        sma50 = "1.2300"
        ema12 = "1.2340"
        ema26 = "1.2320"
        rsi = "65"
        macd = "0.002"
        macdSignal = "0.001"
        macdHist = "0.001"
        bbWidth = "0.02"
        bbPosition = "0.8"
        atrPct = "0.005"
        volumeRatio = "1.5"
    }
    
    func fillBearishData() {
        returns = "-0.4"
        highLowPct = "1.2"
        closeOpenPct = "-0.2"
        sma10 = "1.2300"
        sma20 = "1.2320"
        sma50 = "1.2350"
        ema12 = "1.2310"
        ema26 = "1.2330"
        rsi = "35"
        macd = "-0.001"
        macdSignal = "-0.0005"
        macdHist = "-0.0005"
        bbWidth = "0.03"
        bbPosition = "0.2"
        atrPct = "0.008"
        volumeRatio = "0.7"
    }
}

struct InputField: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Enter value", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.body)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}
