import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedTrade: TradeRecord?
    @Binding var showTradeSheet: Bool
    @State private var showExporter = false
    @State private var exportDocument = HistoryCSVDocument(text: "")
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack(spacing: 8) {
                Text("TRADE HISTORY")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                Spacer()

                Button {
                    Task { await refreshHistory() }
                } label: {
                    Label("REFRESH", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentCyan)
                .disabled(isRefreshing)

                Button {
                    Task { await exportHistory() }
                } label: {
                    Label("EXPORT", systemImage: "square.and.arrow.up")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.accentCyan.opacity(0.1))
                .foregroundColor(.accentCyan)
                .cornerRadius(4)

                Button {
                    viewModel.clearAllHistory()
                } label: {
                    Text("CLEAR ALL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentRed)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.bgSecondary)
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "Stellas_Trade_History.csv"
            ) { result in
                switch result {
                case .success(let url): godLog("✅ Exported history to \(url.path)", level: .success)
                case .failure(let error): godLog("⚠️ History export cancelled/failed: \(error.localizedDescription)", level: .warning)
                }
            }

            Divider().background(Color.borderSubtle)
            #endif

            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.tradeHistory.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 40))
                                .foregroundColor(.textMuted)
                            Text("No past trades to display.")
                                .foregroundColor(.textMuted)
                                .font(.subheadline)
                            Button("FETCH CURRENT HISTORY") {
                                Task { await refreshHistory() }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentCyan)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(viewModel.tradeHistory.prefix(500)) { trade in
                            Button {
                                selectedTrade = trade
                                showTradeSheet = true
                            } label: {
                                historyRow(trade)
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.tradeHistory.count > 500 {
                            Text("Showing last 500 of \(viewModel.tradeHistory.count) trades.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.textMuted)
                                .padding(.top, 10)
                        }
                    }
                }
                .padding(20)
            }
            .refreshable { await refreshHistory() }
        }
        .background(Color.bgPrimary)
    }

    private func refreshHistory() async {
        await MainActor.run { isRefreshing = true }
        // The coordinator already performs a broker-history sync every 30 seconds.
        // Force a local history refresh immediately so the tab never requires relaunch.
        viewModel.refreshData()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await MainActor.run { isRefreshing = false }
    }

    private func exportHistory() async {
        let csv = await RefactoredTradeHistoryManager.shared.generateCSV()
        #if os(macOS)
        await MainActor.run {
            exportDocument = HistoryCSVDocument(text: csv)
            showExporter = true
        }
        #else
        await MainActor.run {
            exportDocument = HistoryCSVDocument(text: csv)
            showExporter = true
        }
        #endif
    }

    @ViewBuilder
    private func historyRow(_ trade: TradeRecord) -> some View {
        let pnl = trade.pnl ?? 0
        let isWin = pnl >= 0
        let color = isWin ? Color.accentGreen : Color.accentRed
        GlassCard(borderColor: color.opacity(0.2)) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(trade.symbol).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                            TagBadge(text: trade.type.rawValue.uppercased(), color: trade.type == .buy ? .accentGreen : .accentRed)
                        }
                        Text(formatDate(trade.entryTime)).font(.system(size: 10)).foregroundColor(.textMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%@%.2f", pnl >= 0 ? "+" : "", pnl)).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(color)
                        Text(trade.status.rawValue.capitalized).font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                    }
                }
                Divider().background(Color.white.opacity(0.05))
                HStack(spacing: 15) {
                    StatLabel(title: "SIZE", value: String(format: "%.2f", trade.positionSize ?? 0))
                    StatLabel(title: "ENTRY", value: String(format: "%.5f", trade.entryPrice))
                    StatLabel(title: "EXIT", value: String(format: "%.5f", trade.exitPrice ?? 0))
                    Spacer()
                    if let exit = trade.exitTime { StatLabel(title: "DUR", value: formatDuration(exit.timeIntervalSince(trade.entryTime))) }
                }
            }.padding(14)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .medium; return formatter.string(from: date)
    }
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds / 60))m"
    }
}

#if os(macOS)
private struct HistoryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
#else
private struct HistoryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
#endif

struct StatLabel: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .bold)).foregroundColor(.textMuted)
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.textPrimary)
        }
    }
}
