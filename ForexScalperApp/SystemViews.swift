import SwiftUI
import UniformTypeIdentifiers

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                sectionHeader("GOD MODE INSIGHTS", icon: "brain.head.profile", color: .accentCyan)
                Spacer()
                Button(action: { viewModel.allInsights.removeAll() }) {
                    Text("CLEAR ALL").font(.system(size: 10, weight: .bold)).foregroundColor(.accentRed)
                }.buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.bgSecondary)
            #endif
            
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.allInsights.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 40))
                                .foregroundColor(.textMuted)
                            Text("No performance or news warnings yet.")
                                .foregroundColor(.textMuted)
                                .font(.subheadline)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(viewModel.allInsights) { insight in
                            let color: Color = {
                                switch insight.type {
                                case .newsBroadcast: return .accentGold
                                case .signalHistory: return .accentGreen
                                default: return .accentCyan
                                }
                            }()
                            GlassCard(borderColor: color.opacity(0.3)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        TagBadge(text: insight.type.rawValue, color: color)
                                        Text(insight.title)
                                            .font(.system(size: 14, weight: .black, design: .monospaced))
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        Text(formatLogTime(insight.timestamp))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.textMuted)
                                    }
                                    
                                    Text(insight.message)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(3)
                                    
                                    if !insight.affectedPairs.isEmpty {
                                        HStack(spacing: 6) {
                                            Text("AFFECTED:")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.textMuted)
                                            
                                            ForEach(insight.affectedPairs, id: \.self) { pair in
                                                Text(pair)
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.textPrimary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.white.opacity(0.05))
                                                    .cornerRadius(3)
                                            }
                                            
                                            Spacer()
                                            
                                            if insight.sentiment != .none {
                                                HStack(spacing: 4) {
                                                    Image(systemName: insight.sentiment == .buy ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                                                    Text(insight.sentiment == .buy ? "BULLISH" : "BEARISH")
                                                }
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundColor(insight.sentiment == .buy ? .accentGreen : .accentRed)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(14)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color.bgPrimary)
    }
    
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .tracking(1)
        }
    }
    
    private func formatLogTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct SystemLogsView: View {
    @ObservedObject var consoleLogger = ConsoleLogger.shared
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isExportingLogs = false
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("SYSTEM LOGS & DIAGNOSTICS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentCyan)
                    .tracking(2)
                Spacer()
                
                Button(action: {
                    ConsoleLogger.shared.clearLogs()
                }) {
                    Label("CLEAR", systemImage: "trash.fill")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentRed)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.accentRed.opacity(0.1))
                .cornerRadius(4)
                
                Button(action: {
                    exportLogs()
                }) {
                    Label("EXPORT (.TXT)", systemImage: "square.and.arrow.down.fill")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.bgPrimary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.accentCyan)
                .cornerRadius(4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider().background(Color.borderSubtle)
            #endif
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(consoleLogger.logs.reversed()) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(formatLogTime(entry.timestamp))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.textMuted)
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(entry.level.icon)
                                    .font(.system(size: 11))
                                
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.level.color)
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 14)
                }
                .onChange(of: consoleLogger.logs.count) { old, newValue in
                    if let first = ConsoleLogger.shared.logs.last {
                        withAnimation {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Color.bgSecondary.opacity(0.5))
        
        #if !os(macOS)
        .fileExporter(
            isPresented: $isExportingLogs,
            document: LogDocument(text: ConsoleLogger.shared.exportLogs()),
            contentType: .plainText,
            defaultFilename: "GodMode_Logs_\(Int(Date().timeIntervalSince1970)).txt"
        ) { result in
            if case .success(let url) = result {
                print("✅ Logs exported to: \(url.path)")
            }
        }
        #endif
    }
    
    private func exportLogs() {
        let logsText = ConsoleLogger.shared.exportLogs()
        let filename = "GodMode_Logs_\(Int(Date().timeIntervalSince1970)).txt"
        
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = filename
        savePanel.message = "Choose where to save your System Logs"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try logsText.write(to: url, atomically: true, encoding: .utf8)
                godLog("📂 Logs Exported: \(url.path)", level: .success)
                viewModel.showNotification(title: "Export Successful", message: "Logs saved successfully.")
            } catch {
                godLog("❌ Export Failed: \(error.localizedDescription)", level: .error)
                viewModel.showNotification(title: "Export Failed", message: error.localizedDescription)
            }
        }
        #else
        isExportingLogs = true
        #endif
    }
    
    private func formatLogTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
