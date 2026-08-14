import SwiftUI

#if !os(macOS)
struct MT5DisconnectButton: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        Button { Task { await viewModel.disconnectFromMT5() } } label: {
            Label("DISCONNECT MT5", systemImage: "power").font(.caption.bold()).foregroundColor(.red)
        }.disabled(!viewModel.mt5Connected)
    }
}
#endif
