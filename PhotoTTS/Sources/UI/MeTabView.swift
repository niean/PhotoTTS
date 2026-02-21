import SwiftUI

// MARK: - 我的 Tab 页
struct MeTabView: View {
    @ObservedObject var appState: AppState
    
    private let avatarSize: CGFloat = 64
    private let topPadding: CGFloat = 20
    private let horizontalPadding: CGFloat = 16
    
    var body: some View {
        NavigationStack {
            List {
                // 顶部
                Section {
                    HStack(spacing: 16) {
                        if let image = IntroAvatarImage.load() {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: avatarSize))
                                .foregroundColor(Color(.systemGray4))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Photo TTS")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("拍照阅读，让绘本更精彩")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: topPadding, leading: horizontalPadding, bottom: topPadding, trailing: horizontalPadding))
                    .listRowBackground(Color(.systemGroupedBackground))
                }
                
                // 记录管理
                Section {
                    NavigationLink {
                        SessionRecordListView(
                            onLoadSession: { _ in },
                            onLoadToMake: { id in
                                appState.sessionIdToLoadIntoMake = id
                                appState.selectedTab = 1
                            },
                            mode: .manage
                        )
                    } label: {
                        Label("记录管理", systemImage: "book.fill")
                    }
                }
                
                // 菜单
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    
                    NavigationLink {
                        IntroPagePushView(appState: appState)
                    } label: {
                        Label("关于", systemImage: "info.circle.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - 介绍页
private struct IntroPagePushView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            AppIntroView(appState: appState, onDismiss: { dismiss() })
            
            TopAndLeftSideNavigationBar(title: "关于", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isPad ? 18 : 16, weight: .medium))
                        .frame(width: isPad ? 24 : 20, height: isPad ? 24 : 20)
                        .foregroundStyle(.primary)
                }
            })
        }
        .navigationBarHidden(true)
    }
}
