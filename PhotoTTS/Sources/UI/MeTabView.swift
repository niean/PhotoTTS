import SwiftUI

// MARK: - 我的 Tab 页
struct MeTabView: View {
    private enum TodayPlanSummary {
        case pending(bookCount: Int, duration: TimeInterval)
        case completed(bookCount: Int, duration: TimeInterval)
        case empty

        var buttonText: String? {
            switch self {
            case let .pending(bookCount, duration),
                 let .completed(bookCount, duration):
                guard bookCount > 0 else { return nil }
                return "今日计划\(bookCount)本 \(Self.formatDuration(duration))"
            case .empty:
                return nil
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

    @ObservedObject var appState: AppState
    @State private var showNameEditor = false
    @State private var editingName = ""
    @State private var displayName = SettingsManager.shared.identityName
    @State private var todayPlanSummary: TodayPlanSummary = .empty
    
    private let avatarSize: CGFloat = 64
    private let topPadding: CGFloat = 20
    private let horizontalPadding: CGFloat = 16

    private var playPlanEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.playPlanEnabled) as? Bool
            ?? Constants.UserDefaultsKeys.playPlanEnabledDefault
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

                // Section 1
                Section {
                    NavigationLink {
                        ReadingReportViewWithBar()
                    } label: {
                        Label("阅读报告", systemImage: "chart.bar.fill")
                    }
                    NavigationLink {
                        PlayHistoryViewWithBar()
                    } label: {
                        Label("播放历史", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        PlaybackSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Label("播放设置", systemImage: "play.circle.fill")
                            Spacer(minLength: 8)
                            if playPlanEnabled, let buttonText = todayPlanSummary.buttonText {
                                Text(buttonText)
                                    .font(Constants.Fonts.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }

                // Section 2
                Section {
                    NavigationLink {
                        RecordAnalysisViewWithBar()
                    } label: {
                        Label("记录分析", systemImage: "chart.pie.fill")
                    }
                    NavigationLink {
                        EndPictManagementView()
                    } label: {
                        Label("要点图片", systemImage: "photo.on.rectangle.angled")
                    }
                    NavigationLink {
                        MakeHistoryViewWithBar()
                    } label: {
                        Label("制作历史", systemImage: "bookmark.circle")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("制作设置", systemImage: "gearshape.fill")
                    }
                }

                // 调试工具
                Section {
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("调试日志", systemImage: "ladybug")
                    }
                    NavigationLink {
                        RealTimeMonitorView()
                    } label: {
                        Label("实时监控", systemImage: "gauge.medium")
                    }
                    NavigationLink {
                        ChangeLogsView()
                    } label: {
                        Label("更新记录", systemImage: "doc.text")
                    }
                    NavigationLink {
                        IntroPagePushView(appState: appState)
                    } label: {
                        Label("关于", systemImage: "info.circle.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                refreshTodayPlanSummary()
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.playHistoryDidUpdate)) { _ in
                refreshTodayPlanSummary()
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.sessionsDidImport)) { _ in
                refreshTodayPlanSummary()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                refreshTodayPlanSummary()
            }
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

    private func refreshTodayPlanSummary() {
        guard playPlanEnabled else {
            todayPlanSummary = .empty
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "MeTabView.今日计划")
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
