import SwiftUI

// MARK: - 我的 Tab 页
struct MeTabView: View {
    @ObservedObject var appState: AppState
    @State private var showNameEditor = false
    @State private var editingName = ""
    @State private var displayName = SettingsManager.shared.identityName
    
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
                                .font(.system(size: avatarSize)) // 视图私有：头像占位图标，动态适配 avatarSize
                                .foregroundColor(Color(.systemGray4))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(displayName)
                                    .font(Constants.Fonts.headline)
                                    .foregroundStyle(.primary)
                                Image(systemName: "pencil")
                                    .font(.system(size: 12)) // 视图私有：编辑铅笔图标，固定 12pt 适配文字
                                    .foregroundStyle(.secondary)
                            }
                            .onTapGesture {
                                editingName = displayName
                                showNameEditor = true
                            }
                            Text("拍照阅读，让绘本更精彩")
                                .font(Constants.Fonts.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: topPadding, leading: horizontalPadding, bottom: topPadding, trailing: horizontalPadding))
                    .listRowBackground(Color(.systemGroupedBackground))
                }

                // 历史记录
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

                // 调试工具
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

                // 设置
                Section {
                    NavigationLink {
                        EndPictManagementView()
                    } label: {
                        Label("要点图片", systemImage: "photo.on.rectangle.angled")
                    }

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
            .alert("修改名称", isPresented: $showNameEditor) {
                TextField("输入名称", text: $editingName)
                Button("取消", role: .cancel) {}
                Button("确定") {
                    let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                    SettingsManager.shared.identityName = trimmed
                    displayName = SettingsManager.shared.identityName
                }
            } message: {
                Text("最多 \(AppConstants.Identity.nameMaxLength) 个字符，留空则恢复为设备名称")
            }
        }
    }
}

// MARK: - 介绍页
private struct IntroPagePushView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
    var body: some View {
        CustomZStack(alignment: .top) {
            AppIntroView(appState: appState, onDismiss: { dismiss() })
            
            TopAndLeftSideNavigationBar(title: "关于", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.navAction)
                        .frame(width: scaled(20), height: scaled(20))
                        .foregroundStyle(.primary)
                }
            })
        }
        .navigationBarHidden(true)
    }
}
