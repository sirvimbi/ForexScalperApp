import SwiftUI
import Foundation
import Combine

struct OrderRequest: Encodable {
    let symbol: String
    let action: String
    let volume: Double
    let price: Double
    let sl: Double
    let tp: Double
    let type: String
    let comment: String
    let magic: Int
    let deviation: Int
}

@main
struct MacGoldTraderApp: App {
    var body: some Scene {
        WindowGroup("Gold Trader") {
            ContentView()
                .frame(minWidth: 520, minHeight: 430)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class TraderViewModel: ObservableObject {
    @Published var endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? "http://127.0.0.1:8890/v1/order"
    @Published var symbol = UserDefaults.standard.string(forKey: "symbol") ?? "XAUUSD"
    @Published var volume = UserDefaults.standard.string(forKey: "volume") ?? "0.01"
    @Published var deviation = UserDefaults.standard.string(forKey: "deviation") ?? "15"
    @Published var status = "Ready"
    @Published var lastCommand = ""
    @Published var isSending = false

    func saveSettings() {
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(symbol, forKey: "symbol")
        UserDefaults.standard.set(volume, forKey: "volume")
        UserDefaults.standard.set(deviation, forKey: "deviation")
    }

    func send(action: String) async {
        saveSettings()
        status = "Sending \(action)…"
        isSending = true
        defer { isSending = false }

        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            status = "Invalid endpoint URL"
            return
        }

        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Symbol is required"
            return
        }
        guard let parsedVolume = Double(volume), parsedVolume > 0 else {
            status = "Volume must be greater than 0"
            return
        }
        guard let parsedDeviation = Int(deviation), parsedDeviation >= 0 else {
            status = "Deviation must be 0 or greater"
            return
        }

        let order = OrderRequest(
            symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            action: action,
            volume: parsedVolume,
            price: 0,
            sl: 0,
            tp: 0,
            type: "MARKET",
            comment: "GOLD_NO_STOPS",
            magic: 888888,
            deviation: parsedDeviation
        )

        do {
            let body = try JSONEncoder().encode(order)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            lastCommand = makeCurlCommand(url: url, body: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let responseText = String(data: data, encoding: .utf8) ?? ""
                if (200..<300).contains(httpResponse.statusCode) {
                    status = "\(action) accepted — HTTP \(httpResponse.statusCode)\(responseText.isEmpty ? "" : " — \(responseText)")"
                } else {
                    status = "\(action) failed — HTTP \(httpResponse.statusCode)\(responseText.isEmpty ? "" : " — \(responseText)")"
                }
            } else {
                status = "No HTTP response received"
            }
        } catch {
            status = "\(action) error — \(error.localizedDescription)"
        }
    }

    private func makeCurlCommand(url: URL, body: Data) -> String {
        let json = String(data: body, encoding: .utf8) ?? "{}"
        let escapedJSON = json.replacingOccurrences(of: "'", with: "'\\''")
        return "curl -X POST \"\(url.absoluteString)\" -H \"Content-Type: application/json\" -d '\(escapedJSON)'"
    }
}

struct ContentView: View {
    @StateObject private var model = TraderViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gold Trader")
                        .font(.system(size: 26, weight: .bold))
                    Text("Manual XAUUSD market execution")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(model.isSending ? .orange : .green)
                    .frame(width: 10, height: 10)
            }

            GroupBox("Connection") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Order endpoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:8890/v1/order", text: $model.endpoint)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(4)
            }

            GroupBox("Order") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        field("Symbol", text: $model.symbol)
                        field("Volume", text: $model.volume)
                            .frame(width: 120)
                        field("Deviation", text: $model.deviation)
                            .frame(width: 120)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await model.send(action: "BUY") }
                        } label: {
                            Label("BUY", systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut("b", modifiers: [.command])
                        .disabled(model.isSending)

                        Button {
                            Task { await model.send(action: "SELL") }
                        } label: {
                            Label("SELL", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .keyboardShortcut("s", modifiers: [.command])
                        .disabled(model.isSending)
                    }
                }
                .padding(4)
            }

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.status)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    if !model.lastCommand.isEmpty {
                        Divider()
                        Text("Equivalent curl")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.lastCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Text("MARKET • no SL/TP • magic 888888")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset defaults") {
                    model.endpoint = "http://127.0.0.1:8890/v1/order"
                    model.symbol = "XAUUSD"
                    model.volume = "0.01"
                    model.deviation = "15"
                    model.saveSettings()
                    model.status = "Defaults restored"
                }
                .buttonStyle(.link)
            }
        }
        .padding(22)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
