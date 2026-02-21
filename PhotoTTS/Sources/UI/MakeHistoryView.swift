import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - 制作历史页（卡片式时间线）
struct MakeHistoryView: View {
    let entries: [MakeHistoryEntry]
    var isEmpty: Bool { entries.isEmpty }
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    
    var body: some View {
        CustomZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        historyCard(entry: entry, showConnector: index < entries.count - 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            
            if isEmpty {
                emptyState
            }
        }
        .navigationBarHidden(true)
    }
    
    private func historyCard(entry: MakeHistoryEntry, showConnector: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 14, height: 14)
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2.5)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                if showConnector {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 2)
                        .frame(minHeight: 28)
                        .padding(.top, 4)
                }
            }
            .frame(width: 24, alignment: .center)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.system(size: isPad ? 17 : 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(dateFormatter.string(from: entry.savedAt)) \(timeFormatter.string(from: entry.savedAt))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.vertical, 14)
            .padding(.trailing, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .padding(.bottom, 12)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark.circle")
                .font(.system(size: isPad ? 56 : 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂无制作历史")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text("保存绘本后会在这里记录")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 顶导 + 导入/导出（带导航栏的制作历史页）
struct MakeHistoryViewWithBar: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MakeHistoryEntry] = []
    @State private var showImportPicker = false
    @State private var exportItem: MakeHistoryExportableURL?
    @State private var message = ""
    @State private var showMessage = false
    @State private var isImporting = false
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            MakeHistoryView(entries: entries)
                .padding(.top, 45)
            
            TopAndLeftSideNavigationBar(title: "制作历史", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isPad ? 18 : 16, weight: .medium))
                        .frame(width: isPad ? 24 : 20, height: isPad ? 24 : 20)
                        .foregroundStyle(.primary)
                }
            }, trailing: {
                HStack(spacing: 16) {
                    Button(action: { showImportPicker = true }) {
                        Text("导入")
                            .font(.system(size: isPad ? 17 : 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Button(action: {
                        if let url = MakeHistoryManager.shared.exportToTemporaryFile() {
                            exportItem = MakeHistoryExportableURL(url: url)
                        }
                    }) {
                        Text("导出")
                            .font(.system(size: isPad ? 17 : 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            })
        }
        .onAppear { loadEntries() }
        .overlay {
            if isImporting {
                CustomZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("正在导入...").font(.headline).foregroundColor(.white)
                    }
                }
            }
        }
        .alert("提示", isPresented: $showMessage) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message)
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                isImporting = true
                let (success, msg) = MakeHistoryManager.shared.importFromURL(url)
                isImporting = false
                message = msg
                showMessage = true
                if success { loadEntries() }
            case .failure:
                message = "选择文件失败"
                showMessage = true
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheetView(activityItems: [item.url])
                .onDisappear { try? FileManager.default.removeItem(at: item.url) }
        }
    }
    
    private func loadEntries() {
        entries = MakeHistoryManager.shared.loadEntries()
    }
}

private struct MakeHistoryExportableURL: Identifiable {
    let id = UUID()
    let url: URL
}
