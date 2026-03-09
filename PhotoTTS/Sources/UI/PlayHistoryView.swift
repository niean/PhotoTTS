import SwiftUI
import UIKit

// MARK: - 播放历史页（卡片式时间线）
struct PlayHistoryView: View {
    let entries: [PlayHistoryEntry]
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
    
    private func historyCard(entry: PlayHistoryEntry, showConnector: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧时间轴：圆点 + 向下连接线
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
            
            // 卡片内容
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.playCount > 1 ? "\(entry.name) (\(entry.playCount))" : entry.name)
                    .font(.system(size: isPad ? 17 : 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(dateFormatter.string(from: entry.lastPlayedAt)) \(timeFormatter.string(from: entry.lastPlayedAt))")
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
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: isPad ? 56 : 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂无播放历史")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text("播放绘本后会在这里记录")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 顶导（带导航栏的播放历史页）
struct PlayHistoryViewWithBar: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PlayHistoryEntry] = []
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            PlayHistoryView(entries: entries)
                .padding(.top, 45)
            
            TopAndLeftSideNavigationBar(title: "播放历史", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isPad ? 18 : 16, weight: .medium))
                        .frame(width: isPad ? 24 : 20, height: isPad ? 24 : 20)
                        .foregroundStyle(.primary)
                }
            }, trailing: {
                EmptyView()
            })
        }
        .onAppear { loadEntries() }
    }
    
    private func loadEntries() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = PlayHistoryManager.shared.loadEntries()
            DispatchQueue.main.async {
                entries = loaded
            }
        }
    }
}

// MARK: - ShareSheet 用于导出
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
