import SwiftUI
import os.log

/// 首页子页面播放用
private struct PlayFromHomeItem: Identifiable, Hashable {
    let id: String
}

// MARK: - 首页
struct HomePageView: View {
    @ObservedObject var appState: AppState
    @State private var sessionToPlayFromHome: PlayFromHomeItem? = nil
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            VStack() {
                // 制作入口
                HStack(spacing: 0) {
                    Button(action: {
                        appState.openCameraOnNextRecordAppear = true
                        appState.selectedTab = 1
                    }) {
                        entryItem(icon: "camera.fill", title: "拍照制作")
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button(action: {
                        appState.openPhotoPickerOnNextRecordAppear = true
                        appState.selectedTab = 1
                    }) {
                        entryItem(icon: "photo.on.rectangle.angled", title: "选图制作")
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, isPad ? 32 : 24)

                // 会话记录
                SessionRecordListView(
                    onLoadSession: { record in
                        guard !appState.isPlayViewActive else {
                            os.Logger.audioPlayer.warning("播放互斥: 已有播放中，拒绝首页触发播放 sessionId=\(record.id)")
                            return
                        }
                        appState.isPlayViewActive = true
                        sessionToPlayFromHome = PlayFromHomeItem(id: record.id)
                    },
                    mode: .embedded
                )
            }
            .padding(.top, 45) // 为顶导留出空间
            
            // 顶导
            TopAndLeftSideNavigationBar(title: "首页")
        }
        .fullScreenCover(item: $sessionToPlayFromHome) { item in
            PlayView(recordId: item.id, onDismiss: {
                sessionToPlayFromHome = nil
                appState.isPlayViewActive = false
            })
        }
        .navigationBarHidden(true)
    }
    
    private func entryItem(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: isPad ? 48 : 32))
                .foregroundColor(.blue)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}
