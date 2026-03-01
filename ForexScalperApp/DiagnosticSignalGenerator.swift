// DiagnosticSignalGenerator.swift
import Foundation
import Combine // Add this import

@MainActor
class DiagnosticSignalGenerator: ObservableObject {
    static let shared = DiagnosticSignalGenerator()
    
    @Published var isGeneratingSignals = false
    private var generationTask: Task<Void, Never>?
    private weak var coordinator: RefactoredAppCoordinator?
    
    func setCoordinator(_ coordinator: RefactoredAppCoordinator) {
        self.coordinator = coordinator
    }
    
    func startGeneratingTestSignals() {
        guard !isGeneratingSignals else { return }
        
        isGeneratingSignals = true
        print("🧪 Starting test signal generation every 10 seconds")
        
        generationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.generateTestSignal()
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }
    
    func stopGeneratingTestSignals() {
        isGeneratingSignals = false
        generationTask?.cancel()
        generationTask = nil
        print("🧪 Stopped test signal generation")
    }
    
    private func generateTestSignal() async {
        guard let coordinator = coordinator else { return }
        
        // Generate a random signal
        let symbols = ["EURUSD", "GBPUSD", "BTCUSDT", "ETHUSDT", "XRPUSDT"]
        let randomSymbol = symbols.randomElement() ?? "EURUSD"
        let randomType: SignalType = Bool.random() ? .buy : .sell
        let randomPrice = Double.random(in: 1.0...1.2)
        let randomConfidence = Double.random(in: 75...95)
        
        let signal = Signal(
            type: randomType,
            symbol: randomSymbol,
            price: randomPrice,
            confidence: randomConfidence,
            timestamp: Date(),
            timeframe: "1m",
            expiryTime: Date().addingTimeInterval(180),
            status: .pending,
            source: .binance,
            volume: Double.random(in: 1000...10000)
        )
        
        // Inject directly to coordinator
        await coordinator.injectTestSignal(signal)
        
        print("🧪 TEST SIGNAL GENERATED: \(randomSymbol) \(randomType) @ \(String(format: "%.5f", randomPrice)) (Confidence: \(String(format: "%.1f", randomConfidence))%)")
    }
    
    func generateSingleTestSignal() async {
        await generateTestSignal()
    }
}
