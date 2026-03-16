import SwiftUI

// MARK: - 消息 Tab 页（布局参考「我的」，调试日志为分组按钮）
struct MessageTabView: View {
    private let iconSize: CGFloat = 64
    private let topPadding: CGFloat = 20
    private let horizontalPadding: CGFloat = 16
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "message.fill")
                            .font(.system(size: iconSize * 0.6)) // 动态计算，保留视图私有
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("消息")
                                .font(Constants.Fonts.headline)
                                .foregroundStyle(.primary)
                            Text("分析和调试")
                                .font(Constants.Fonts.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: topPadding, leading: horizontalPadding, bottom: topPadding, trailing: horizontalPadding))
                    .listRowBackground(Color(.systemGroupedBackground))
                }
                
                Section {
                    NavigationLink {
                        PlayHistoryViewWithBar()
                    } label: {
                        Label("播放历史", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        MakeHistoryViewWithBar()
                    } label: {
                        Label("制作历史", systemImage: "bookmark.circle")
                    }
                }

                Section {
                    NavigationLink {
                        RealTimeMonitorView()
                    } label: {
                        Label("实时监控", systemImage: "gauge.medium")
                    }
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("调试日志", systemImage: "ladybug")
                    }
                    NavigationLink {
                        ChangeLogsView()
                    } label: {
                        Label("更新记录", systemImage: "doc.text")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
