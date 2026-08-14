import SwiftUI

struct NotificationBanner: View {
    let isAuthorized: Bool
    @Binding var isDismissed: Bool

    var body: some View {
        if !isAuthorized && !isDismissed {
            HStack {
                Image(systemName: "bell.badge.fill").foregroundColor(.white)
                Text("Notifications Disabled")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("ENABLE") {
                    NotificationManager.shared.requestAuthorization()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
            .padding(12)
            .background(Color.accentRed)
            .cornerRadius(8)
            .padding(.horizontal, 20)
        }
    }
}

struct NoSignalsView: View {
    let connectionStatus: String
    let signalsCount: Int
    let signals: [Signal]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundColor(.accentCyan.opacity(0.3))
            Text("SCANNING FOR INSTITUTIONAL FLOW")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
            Text(connectionStatus.lowercased().contains("connected")
                 ? "Active WebSocket stream on Port 8890. Waiting for high-probability confluence."
                 : "Waiting for MT5 bridge connection...")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if signalsCount > 0 {
                Text("\(signalsCount) historical/expired signals hidden.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
            Spacer()
        }
        .frame(minHeight: 400)
    }
}