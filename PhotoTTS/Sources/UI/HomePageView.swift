import SwiftUI
import os.log

/// 首页子页面播放用
private struct PlayFromHomeItem: Identifiable, Hashable {
    let id: String
    let queueRecordIds: [String]  // 连播队列（含自身）
}

// MARK: - 首页
struct HomePageView: View {
    @ObservedObject var appState: AppState
    @State private var sessionToPlayFromHome: PlayFromHomeItem? = nil
    @State private var isListScrolled = false
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            VStack(spacing: 0) {
                // 制作入口
                HStack(spacing: 0) {
                    Button(action: {
                        appState.openCameraOnNextRecordAppear = true
                        appState.selectedTab = 1
                    }) {
                        entryItem(icon: "camera.fill", title: "拍照制作")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, scaled(24))
                    .padding(.bottom, scaled(12))
                    
                    Button(action: {
                        appState.openPhotoPickerOnNextRecordAppear = true
                        appState.selectedTab = 1
                    }) {
                        entryItem(icon: "photo.on.rectangle.angled", title: "选图制作")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, scaled(24))
                    .padding(.bottom, scaled(12))
                }
                .background(Color(.systemBackground))
                .padding(.bottom, isListScrolled ? 0 : 1)

                // 会话记录
                SessionRecordListView(
                    appState: appState,
                    onLoadSession: { record in
                        guard !appState.isPlayViewActive else {
                            os.Logger.audioPlayer.warning("播放互斥: 已有播放中，拒绝首页触发播放 sessionId=\(record.id)")
                            return
                        }
                        appState.isPlayViewActive = true
                        // 构建同日期连播队列
                        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "HomePageView.连播队列")
                        let queue = SessionRecordManager.buildSameDateQueue(from: record.id, in: allMetadata)
                        sessionToPlayFromHome = PlayFromHomeItem(id: record.id, queueRecordIds: queue)
                    },
                    mode: .embedded,
                    onListScrolled: { isListScrolled = $0 }
                )
            }
            .padding(.top, 45) // 为顶导留出空间
            
            // 顶导
            TopAndLeftSideNavigationBar(title: "首页")
        }
        .fullScreenCover(item: $sessionToPlayFromHome) { item in
            PlayView(recordId: item.id, queueRecordIds: item.queueRecordIds, onDismiss: {
                sessionToPlayFromHome = nil
                appState.isPlayViewActive = false
            })
        }
        .navigationBarHidden(true)
    }
    
    private func entryItem(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(Constants.Fonts.homeIcon)
                .foregroundColor(.blue)
            Text(title)
                .font(Constants.Fonts.subheadline)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}
