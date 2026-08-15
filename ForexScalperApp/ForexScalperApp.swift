import SwiftUI
import UserNotifications
import Combine

@main
struct ForexScalperApp: App {
    @StateObject private var coordinator: RefactoredAppCoordinator
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var runtimeMaintenance: AppRuntimeMaintenance
    
    init() {
        let coord = RefactoredAppCoordinator()
        let vm = DashboardViewModel(coordinator: coord)
        let maintenance = AppRuntimeMaintenance(coordinator: coord, viewModel: vm)
        self._coordinator = StateObject(wrappedValue: coord)
        self._viewModel = StateObject(wrappedValue: vm)
        self._runtimeMaintenance = StateObject(wrappedValue: maintenance)
        
        // Install runtime diagnostics before services start so startup/network activity is visible.
        NetworkDiagnostics.install()
        SignalDiagnostics.install()
        _ = DailyNewsIntelligence.shared
        
        // Request notification permissions via the manager
        NotificationManager.shared.requestAuthorization()
        
        Task {
            await coord.connectToDataSources()
            await coord.start()
            await MainActor.run {
                vm.refreshData()
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: viewModel, coordinator: coordinator)
        }
        .windowResizability(.contentSize)
        
        #if os(macOS)
        MenuBarExtra("Stellas", systemImage: "chart.xyaxis.line") {
            MenuBarView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
struct MenuBarView: View {
    @ObservedObject var coordinator: RefactoredAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(coordinator.connectionStatus.contains("Connected") ? .green : .orange)
                    .font(.system(size: 8))
                Text(coordinator.status)
                    .font(.headline)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Last Signal:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(coordinator.lastSignal)
                    .font(.body)
                    .bold()
                    .lineLimit(1)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Signals:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if coordinator.signals.isEmpty {
                    Text("No recent signals")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(coordinator.signals.prefix(3)) { signal in
                        HStack {
                            Image(systemName: signal.type == .buy ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundColor(signal.type == .buy ? .green : .red)
                            
                            Text(signal.symbol)
                                .font(.caption)
                                .bold()
                            
                            Spacer()
                            
                            Text(String(format: "%.5f", signal.price))
                                .font(.caption)
                            
                            Text("\(Int(signal.confidence))%")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Open Dashboard") {
                    if let url = URL(string: "forexscalper://dashboard") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 340)
    }
}
#endif