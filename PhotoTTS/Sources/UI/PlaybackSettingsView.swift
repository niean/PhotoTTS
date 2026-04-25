import SwiftUI

// MARK: - 播放设置页面
struct PlaybackSettingsView: View {
    private enum TodayPlanSummary {
        case pending(bookCount: Int, duration: TimeInterval)
        case completed(bookCount: Int, duration: TimeInterval)
        case empty

        var statusText: String {
            switch self {
            case let .pending(bookCount, duration):
                return "计划未完成"
                    + (bookCount > 0 ? " · \(bookCount)本 \(Self.formatDuration(duration))" : "")
            case let .completed(bookCount, duration):
                return "计划已完成"
                    + (bookCount > 0 ? " · \(bookCount)本 \(Self.formatDuration(duration))" : "")
            case .empty:
                return "最近30天无待播绘本"
            }
        }

        var statusColor: Color {
            switch self {
            case .pending:
                return .green
            case .completed, .empty:
                return .secondary
            }
        }

        private static func formatDuration(_ duration: TimeInterval) -> String {
            let totalMinutes = max(1, Int((duration + 59) / 60))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60

            if hours > 0 {
                return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时"
            }
            return "\(totalMinutes)分"
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var playPlanEnabled: Bool = {
        let key = Constants.UserDefaultsKeys.playPlanEnabled
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }()
    @State private var todayPlanSummary: TodayPlanSummary = .empty

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

    /// 获取今日已处理的待办日期（如果有）
    private var todayProcessedTodoDate: Date? {
        guard isTodayProcessed else { return nil }
        let storedDate = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.playPlanTodayProcessedTodoDate)
        guard storedDate > 0 else { return nil }
        return Date(timeIntervalSince1970: storedDate)
    }

    /// 今日状态文本
    private var todayStatusText: String {
        todayPlanSummary.statusText
    }

    /// 今日状态颜色
    private var todayStatusColor: Color {
        todayPlanSummary.statusColor
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
                                if newValue {
                                    refreshTodayPlanSummary()
                                }
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
                                .multilineTextAlignment(.trailing)
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
        .onAppear {
            refreshTodayPlanSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.playHistoryDidUpdate)) { _ in
            guard playPlanEnabled else { return }
            refreshTodayPlanSummary()
        }
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
        refreshTodayPlanSummary()
    }

    private func refreshTodayPlanSummary() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "PlaybackSettingsView.今日状态")
            let completedMetadata = allMetadata.filter { $0.makeStatus == nil || $0.makeStatus == .completed }
            let statsMap = SessionRecordManager.shared.loadPlayStats(sessionIds: completedMetadata.map(\.id))
            let planDate = HomePagePlayPlanHelper.activePlanDate(
                in: completedMetadata,
                statsMap: statsMap,
                isTodayProcessed: isTodayProcessed,
                todayProcessedTodoDate: todayProcessedTodoDate
            )

            let calendar = Calendar.current
            let summary: TodayPlanSummary

            if let planDate {
                let sameDayItems = completedMetadata.filter { metadata in
                    calendar.isDate(metadata.namePrefixDate, inSameDayAs: planDate)
                }

                let summaryItems: [SessionRecordMetadata]
                if isTodayProcessed {
                    summaryItems = sameDayItems
                } else {
                    summaryItems = sameDayItems.filter { statsMap[$0.id] == nil }
                }

                let totalDuration = summaryItems.reduce(0) { $0 + $1.audioDuration }
                if isTodayProcessed {
                    summary = .completed(bookCount: summaryItems.count, duration: totalDuration)
                } else {
                    summary = summaryItems.isEmpty
                        ? .empty
                        : .pending(bookCount: summaryItems.count, duration: totalDuration)
                }
            } else {
                summary = .empty
            }

            DispatchQueue.main.async {
                todayPlanSummary = summary
            }
        }
    }
}

#Preview {
    PlaybackSettingsView()
}
