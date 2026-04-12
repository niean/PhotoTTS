import SwiftUI

// MARK: - 播放设置页面
struct PlaybackSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var playPlanEnabled: Bool = {
        let key = Constants.UserDefaultsKeys.playPlanEnabled
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }()

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    /// 检查今天是否已经处理过某个待办日期
    private var isTodayProcessed: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let storedForDate = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.playPlanTodayProcessedForDate)
        guard storedForDate > 0 else { return false }
        let storedForDateValue = Date(timeIntervalSince1970: storedForDate)
        return Calendar.current.isDate(storedForDateValue, inSameDayAs: today)
    }

    /// 今日状态文本
    private var todayStatusText: String {
        isTodayProcessed ? "计划已完成" : "计划未完成"
    }

    /// 今日状态颜色
    private var todayStatusColor: Color {
        isTodayProcessed ? .secondary : .green
    }

    var body: some View {
        CustomZStack(alignment: .top) {
            List {
                Section {
                    HStack {
                        Text("播放计划")
                            .font(Constants.Fonts.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Toggle("", isOn: $playPlanEnabled)
                            .labelsHidden()
                            .onChange(of: playPlanEnabled) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKeys.playPlanEnabled)
                            }
                    }

                    if playPlanEnabled {
                        HStack {
                            Text("今日状态")
                                .font(Constants.Fonts.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(todayStatusText)
                                .font(Constants.Fonts.body)
                                .foregroundStyle(todayStatusColor)
                        }

                        Button(action: {
                            showResetConfirm = true
                        }) {
                            HStack {
                                Spacer()
                                Text("重置今日标记")
                                    .font(Constants.Fonts.body)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("播放计划")
                } footer: {
                    if !playPlanEnabled {
                        Text("关闭后，首页将不再展示播放计划。")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .padding(.top, scaled(45))

            TopAndLeftSideNavigationBar(
                title: "播放设置",
                onSwipeBack: { dismiss() },
                leading: {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(Constants.Fonts.navAction)
                            .frame(width: scaled(20), height: scaled(20))
                            .foregroundStyle(.primary)
                    }
                }
            )
        }
        .navigationBarHidden(true)
        .alert("重置今日标记", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                resetTodayMarker()
            }
        } message: {
            Text("确定要重置今日标记吗？")
        }
    }

    /// 重置今日标记
    private func resetTodayMarker() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.playPlanTodayProcessedTodoDate)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.playPlanTodayProcessedForDate)
    }
}

#Preview {
    PlaybackSettingsView()
}
