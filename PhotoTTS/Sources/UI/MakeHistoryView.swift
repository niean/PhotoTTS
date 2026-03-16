import SwiftUI
import UIKit

// MARK: - 制作历史页（卡片式时间线）
struct MakeHistoryView: View {
    let entries: [MakeHistoryEntry]
    var isEmpty: Bool { entries.isEmpty }
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
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
                    .font(Constants.Fonts.navAction)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(Constants.Fonts.historyDate)
                        .foregroundStyle(.secondary)
                    Text("\(dateFormatter.string(from: entry.savedAt)) \(timeFormatter.string(from: entry.savedAt))")
                        .font(Constants.Fonts.historyDetail)
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
                .font(Constants.Fonts.historyEmptyIcon)
                .foregroundStyle(.tertiary)
            Text("暂无制作历史")
                .font(Constants.Fonts.historyEmptyTitle)
                .foregroundStyle(.secondary)
            Text("保存绘本后会在这里记录")
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 顶导（带导航栏的制作历史页）
struct MakeHistoryViewWithBar: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MakeHistoryEntry] = []
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            MakeHistoryView(entries: entries)
                .padding(.top, 45)
            
            TopAndLeftSideNavigationBar(title: "制作历史", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.navAction)
                        .frame(width: scaled(20), height: scaled(20))
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
            let loaded = MakeHistoryManager.shared.loadEntries()
            DispatchQueue.main.async {
                entries = loaded
            }
        }
    }
}
