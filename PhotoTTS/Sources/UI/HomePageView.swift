import SwiftUI
import os.log

/// 首页子页面播放用
private struct PlayFromHomeItem: Identifiable, Hashable {
    let id: String
    let queueRecordIds: [String]
}

enum HomePagePlayPlanHelper {
    static func shouldUsePlanQueue(
        sortMode: HomeSessionSortMode,
        playPlanEnabled: Bool,
        isTodoRecord: Bool
    ) -> Bool {
        sortMode == .list && playPlanEnabled && isTodoRecord
    }

    static func activePlanDate(
        in items: [SessionRecordMetadata],
        statsMap: [String: PlayStatInfo],
        isTodayProcessed: Bool,
        todayProcessedTodoDate: Date? = nil,
        now: Date = Date()
    ) -> Date? {
        let calendar = Calendar.current

        if isTodayProcessed, let todayProcessedTodoDate {
            return calendar.startOfDay(for: todayProcessedTodoDate)
        }

        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else {
            return nil
        }
        let thirtyDaysAgoStart = calendar.startOfDay(for: thirtyDaysAgo)

        return items
            .filter { metadata in
                guard statsMap[metadata.id] == nil else { return false }
                let itemDate = calendar.startOfDay(for: metadata.namePrefixDate)
                return itemDate >= thirtyDaysAgoStart
            }
            .map { calendar.startOfDay(for: $0.namePrefixDate) }
            .min()
    }

    static func applySort(
        to items: [SessionRecordMetadata],
        statsMap: [String: PlayStatInfo],
        sortMode: HomeSessionSortMode,
        playPlanEnabled: Bool,
        isTodayProcessed: Bool,
        todayProcessedTodoDate: Date? = nil,
        now: Date = Date()
    ) -> ([SessionRecordMetadata], Set<String>) {
        guard playPlanEnabled else {
            return (items, [])
        }

        let calendar = Calendar.current
        guard let planDate = activePlanDate(
            in: items,
            statsMap: statsMap,
            isTodayProcessed: isTodayProcessed,
            todayProcessedTodoDate: todayProcessedTodoDate,
            now: now
        ) else {
            return (items, [])
        }

        let visibleItems = items.filter { metadata in
            let itemDate = calendar.startOfDay(for: metadata.namePrefixDate)
            return itemDate <= planDate
        }

        guard !isTodayProcessed else {
            return (visibleItems, [])
        }

        let todoItems = visibleItems.filter { item in
            guard statsMap[item.id] == nil else { return false }
            let itemDate = calendar.startOfDay(for: item.namePrefixDate)
            return itemDate == planDate
        }

        let todoIdSet = Set(todoItems.map(\.id))
        guard sortMode == .list else {
            return (visibleItems, todoIdSet)
        }

        let otherItems = visibleItems.filter { !todoIdSet.contains($0.id) }
        return (todoItems + otherItems, todoIdSet)
    }
}

// MARK: - 首页
struct HomePageView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var bgMakeManager = BackgroundMakeManager.shared

    @State private var sessionToPlayFromHome: PlayFromHomeItem? = nil
    @State private var pagedMetadataList: [SessionRecordMetadata] = []
    @State private var totalCount: Int = 0
    @State private var loadedPageCount: Int = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var searchText: String = ""
    @State private var playStatsMap: [String: PlayStatInfo] = [:]
    @State private var selectedSeries: String? = nil  // nil 表示不限
    @State private var selectedReadStatus: SessionReadStatusFilter? = nil  // nil 表示不限
    @State private var seriesOptions: [String] = []   // 所有系列选项
    @State private var todoRecordIds: Set<String> = []

    // MARK: - 播放计划每日限制

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

    /// 标记某个日期为今日已处理
    private func markTodoDateAsProcessed(_ date: Date) {
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Constants.UserDefaultsKeys.playPlanTodayProcessedTodoDate)
        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: Constants.UserDefaultsKeys.playPlanTodayProcessedForDate)
    }

    /// 检查当前待办日期的所有记录是否都已播放，如果是则标记为今日已处理
    private func checkAndMarkTodoDateIfNeeded() {
        // 获取当前的待办日期（从 todoRecordIds 中取第一个记录的日期）
        guard let firstTodoId = todoRecordIds.first,
              let metadata = pagedMetadataList.first(where: { $0.id == firstTodoId }) else {
            return
        }

        let todoDate = Calendar.current.startOfDay(for: metadata.namePrefixDate)

        // 获取所有该日期的记录
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(
            excludeUnnamed: true,
            caller: "HomePageView.检查待办完成"
        )
        let todoDateRecords = allMetadata.filter {
            Calendar.current.isDate($0.namePrefixDate, inSameDayAs: todoDate)
        }

        // 检查是否所有记录都已播放
        let statsMap = SessionRecordManager.shared.loadPlayStats(sessionIds: todoDateRecords.map(\.id))
        let allPlayed = todoDateRecords.allSatisfy { statsMap[$0.id] != nil }

        if allPlayed {
            markTodoDateAsProcessed(todoDate)
            // 重新加载页面以更新待办状态
            refreshFirstBatch()
        }
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    /// iPhone 2 列, iPad 4 列
    private var columns: [GridItem] {
        let count = UIDevice.current.userInterfaceIdiom == .pad ? Constants.HomeCard.iPadColumns : Constants.HomeCard.iPhoneColumns
        return Array(repeating: GridItem(.flexible(), spacing: scaled(Constants.HomeCard.gridSpacing)), count: count)
    }

    private var hasMoreItems: Bool {
        pagedMetadataList.count < totalCount
    }

    var body: some View {
        CustomZStack(alignment: .top) {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("加载中...")
                        .scaleEffect(scaled(1.0))
                    Spacer()
                } else if totalCount == 0
                    && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && selectedSeries == nil
                    && selectedReadStatus == nil {
                    Spacer()
                    VStack(spacing: scaled(20)) {
                        Image(systemName: "book.closed")
                            .font(Constants.Fonts.emptyStateIcon)
                            .foregroundColor(.gray)
                        Text("暂无会话记录")
                            .font(Constants.Fonts.navTitle)
                            .foregroundColor(.secondary)
                        Text("在管理页制作绘本后即可播放")
                            .font(Constants.Fonts.recordMeta)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                // 搜索栏（默认被顶导遮盖，下拉出现）
                                searchBar
                                    .padding(.horizontal, scaled(Constants.HomeCard.gridHorizontalPadding))
                                    .padding(.top, scaled(8))
                                    .padding(.bottom, scaled(4))
                                    .id(Constants.UI.searchBarRowId)

                                // 搜索栏与卡片之间的锚点（滚动隐藏搜索栏时定位于此，保留顶部间距）
                                Color.clear
                                    .frame(height: scaled(6))
                                    .id("cardTopAnchor")

                                if pagedMetadataList.isEmpty {
                                    // 搜索无结果
                                    VStack(spacing: scaled(12)) {
                                        Image(systemName: "magnifyingglass")
                                            .font(Constants.Fonts.searchEmptyIcon)
                                            .foregroundColor(.gray)
                                        Text(Constants.UI.searchNoResult)
                                            .font(Constants.Fonts.searchNoResult)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, scaled(40))
                                } else {
                                    // 卡片网格
                                    LazyVGrid(columns: columns, spacing: scaled(Constants.HomeCard.gridSpacing)) {
                                        ForEach(pagedMetadataList) { metadata in
                                            SessionRecordCard(
                                                metadata: metadata,
                                                makeProgress: makeProgress(for: metadata),
                                                playStats: playStatsMap[metadata.id],
                                                isTodo: todoRecordIds.contains(metadata.id),
                                                onTap: { loadAndPlay(metadata.id) }
                                            )
                                            .onAppear {
                                                loadNextBatchIfNeeded(currentItem: metadata)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, scaled(Constants.HomeCard.gridHorizontalPadding))
                                    .padding(.top, scaled(8))

                                    if isLoadingMore {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: scaled(Constants.Pagination.controlHeight))
                                            .padding(.top, scaled(8))
                                    }
                                }
                            }
                            .frame(minHeight: UIScreen.main.bounds.height, alignment: .top)
                            .background(Color(.systemBackground))
                        }
                        .onAppear {
                            scrollToHideSearchBar(proxy: scrollProxy)
                        }
                    }
                }
            }
            .padding(.top, scaled(45))

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
        .onAppear {
            if !applyStartupPreloadIfAvailable() {
                refreshFirstBatch()
                loadSeriesOptions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.sessionsDidImport)) { _ in
            refreshFirstBatch()
            loadSeriesOptions()
        }
        .onChange(of: appState.tab0ReselectTrigger) {
            guard loadedPageCount > 1 else { return }
            refreshFirstBatch()
        }
        .onChange(of: searchText) {
            // 清空时自动刷新回原列表
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                refreshFirstBatch()
            }
        }
        .onChange(of: selectedSeries) {
            refreshFirstBatch()
        }
        .onChange(of: selectedReadStatus) {
            refreshFirstBatch()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.playHistoryDidUpdate)) { _ in
            checkAndMarkTodoDateIfNeeded()
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        SessionSearchBar(
            searchText: $searchText,
            selectedSeries: $selectedSeries,
            selectedReadStatus: $selectedReadStatus,
            seriesOptions: seriesOptions,
            onSearchSubmit: {
                refreshFirstBatch()
            }
        )
    }

    // MARK: - Helpers

    private func makeProgress(for metadata: SessionRecordMetadata) -> Float? {
        // 多任务并发下按 sessionId 精准定位任务进度
        guard metadata.isMaking,
              let task = bgMakeManager.task(for: metadata.id),
              !task.isCompleted else { return nil }
        return task.progress
    }

    private func loadAndPlay(_ id: String) {
        guard !appState.isPlayViewActive else {
            os.Logger.audioPlayer.warning("播放互斥: 已有播放中，拒绝首页触发播放 sessionId=\(id)")
            return
        }
        appState.isPlayViewActive = true

        // 检查播放计划开关
        let playPlanEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.playPlanEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.playPlanEnabled)

        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(
            sortMode: .list,
            excludeUnnamed: true,
            caller: "HomePageView.连播队列"
        )
        let queue: [String]

        if HomePagePlayPlanHelper.shouldUsePlanQueue(
            sortMode: .list,
            playPlanEnabled: playPlanEnabled,
            isTodoRecord: todoRecordIds.contains(id)
        ) {
            // 仅列表模式下，播放计划内记录才构建计划连播队列
            queue = SessionRecordManager.buildPlanQueue(from: id, in: allMetadata, todoRecordIds: todoRecordIds)
        } else {
            // 非列表模式或非计划内记录：仅单条播放
            queue = [id]
        }

        sessionToPlayFromHome = PlayFromHomeItem(id: id, queueRecordIds: queue)
    }

    private func loadSeriesOptions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(
                excludeUnnamed: true,
                caller: "首页系列选项"
            )
            let uncategorized = Constants.GroupDisplay.uncategorizedLabel
            let seriesSet = Set(allMetadata.map { $0.seriesName })
                .filter { $0 != uncategorized }
            let sortedSeries = Array(seriesSet).sorted { $0.localizedCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                self.seriesOptions = sortedSeries
            }
        }
    }

    private func applyStartupPreloadIfAvailable() -> Bool {
        let playPlanEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.playPlanEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.playPlanEnabled)
        guard !playPlanEnabled else {
            _ = appState.consumeHomePageStartupPreloadSnapshot()
            return false
        }

        guard loadedPageCount == 0,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedSeries == nil,
              selectedReadStatus == nil,
              let snapshot = appState.consumeHomePageStartupPreloadSnapshot() else {
            return false
        }

        let (sortedItems, todoIds) = applyPlayPlanSort(to: snapshot.items, statsMap: snapshot.playStatsMap)
        pagedMetadataList = sortedItems
        todoRecordIds = todoIds
        totalCount = snapshot.totalCount
        playStatsMap = snapshot.playStatsMap
        seriesOptions = snapshot.seriesOptions
        loadedPageCount = snapshot.items.isEmpty ? 0 : 1
        isLoading = false
        isLoadingMore = false
        return true
    }

    private func refreshFirstBatch() {
        loadBatch(page: 1, append: false)
    }

    private func loadNextBatchIfNeeded(currentItem: SessionRecordMetadata) {
        guard currentItem.id == pagedMetadataList.last?.id,
              hasMoreItems,
              !isLoading,
              !isLoadingMore else {
            return
        }
        loadBatch(page: loadedPageCount + 1, append: true)
    }

    private func loadBatch(page: Int, append: Bool) {
        if append {
            isLoadingMore = true
        } else {
            isLoading = true
            isLoadingMore = false
        }

        let pageSize = Constants.Pagination.pageSize
        let keyword = searchText
        let series = selectedSeries
        let readStatus = selectedReadStatus
        let requestedSortMode: HomeSessionSortMode = .list
        let isPlanEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.playPlanEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.playPlanEnabled)
        let hasTodayProcessed = isTodayProcessed
        let processedTodoDate = todayProcessedTodoDate
        DispatchQueue.global(qos: .userInitiated).async {
            let result: (items: [SessionRecordMetadata], totalCount: Int)
            let batchTodoIds: Set<String>
            if isPlanEnabled {
                let allItems = SessionRecordManager.shared.getFilteredSessionMetadata(
                    searchKeyword: keyword,
                    seriesFilter: series,
                    readStatusFilter: readStatus,
                    completedOnly: true,
                    excludeUnnamed: true,
                    sortMode: requestedSortMode,
                    caller: "首页卡片"
                )
                let allStatsMap = SessionRecordManager.shared.loadPlayStats(sessionIds: allItems.map(\.id))
                let (visibleItems, allTodoIds) = HomePagePlayPlanHelper.applySort(
                    to: allItems,
                    statsMap: allStatsMap,
                    sortMode: requestedSortMode,
                    playPlanEnabled: isPlanEnabled,
                    isTodayProcessed: hasTodayProcessed,
                    todayProcessedTodoDate: processedTodoDate
                )
                batchTodoIds = allTodoIds
                let startIndex = max(0, (max(1, page) - 1) * pageSize)
                if startIndex < visibleItems.count {
                    let endIndex = min(startIndex + pageSize, visibleItems.count)
                    result = (Array(visibleItems[startIndex..<endIndex]), visibleItems.count)
                } else {
                    result = ([], visibleItems.count)
                }
            } else {
                result = SessionRecordManager.shared.getSessionMetadataPage(
                    page: page,
                    pageSize: pageSize,
                    searchKeyword: keyword,
                    seriesFilter: series,
                    readStatusFilter: readStatus,
                    completedOnly: true,
                    excludeUnnamed: true,
                    sortMode: requestedSortMode,
                    caller: "首页卡片"
                )
                batchTodoIds = []
            }
            let statsMap = SessionRecordManager.shared.loadPlayStats(
                sessionIds: result.items.map(\.id)
            )
            DispatchQueue.main.async {
                defer {
                    if append {
                        self.isLoadingMore = false
                    } else {
                        self.isLoading = false
                    }
                }

                guard self.searchText == keyword,
                      self.selectedSeries == series,
                      self.selectedReadStatus == readStatus else {
                    return
                }

                // 播放计划开启时已基于全量列表完成过滤与排序，避免按当前页重复计算计划日期。
                let sortedItems: [SessionRecordMetadata]
                let todoIds: Set<String>
                if isPlanEnabled {
                    sortedItems = result.items
                    todoIds = batchTodoIds
                } else {
                    (sortedItems, todoIds) = self.applyPlayPlanSort(to: result.items, statsMap: statsMap)
                }

                if append {
                    if sortedItems.isEmpty {
                        self.totalCount = self.pagedMetadataList.count
                        return
                    }
                    self.pagedMetadataList += sortedItems
                    self.todoRecordIds.formUnion(todoIds)
                    self.totalCount = result.totalCount
                    self.playStatsMap.merge(statsMap) { _, new in new }
                    self.loadedPageCount = page
                } else {
                    self.pagedMetadataList = sortedItems
                    self.todoRecordIds = todoIds
                    self.totalCount = result.totalCount
                    self.playStatsMap = statsMap
                    self.loadedPageCount = sortedItems.isEmpty ? 0 : page
                }
            }
        }
    }

    private func scrollToHideSearchBar(proxy: ScrollViewProxy) {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // 卡片不足以触发滚动时，保持搜索框可见
        let minCardsToHideSearch = columns.count * 2
        guard pagedMetadataList.count >= minCardsToHideSearch else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("cardTopAnchor", anchor: .top)
        }
    }

    /// 对记录列表进行"播放计划"排序：最早日期的未播放记录置顶
    /// - Parameters:
    ///   - items: 原始记录列表
    ///   - statsMap: 播放统计字典
    /// - Returns: (排序后的列表, 置顶记录ID集合)
    private func applyPlayPlanSort(to items: [SessionRecordMetadata], statsMap: [String: PlayStatInfo]) -> ([SessionRecordMetadata], Set<String>) {
        let playPlanEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.playPlanEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.playPlanEnabled)
        return HomePagePlayPlanHelper.applySort(
            to: items,
            statsMap: statsMap,
            sortMode: .list,
            playPlanEnabled: playPlanEnabled,
            isTodayProcessed: isTodayProcessed,
            todayProcessedTodoDate: todayProcessedTodoDate
        )
    }
}

// MARK: - 绘本卡片
private struct SessionRecordCard: View {
    let metadata: SessionRecordMetadata
    var makeProgress: Float? = nil
    var playStats: PlayStatInfo? = nil
    var isTodo: Bool = false
    var onTap: () -> Void

    @State private var avatarImage: UIImage? = nil
    @State private var loadingId: String? = nil

    private var isMaking: Bool { metadata.isMaking }

    /// 去掉日期前缀 "YY.MM.DD " 后的名称
    private var displayName: String {
        let name = metadata.name
        let prefixLen = Constants.sessionNameDatePrefixFormat.count // "yy.MM.dd " = 9
        guard name.count > prefixLen else { return name }
        let prefix = String(name.prefix(prefixLen))
        // 检查是否符合 "XX.XX.XX " 格式
        if prefix.count == prefixLen,
           prefix[prefix.index(prefix.startIndex, offsetBy: 2)] == ".",
           prefix[prefix.index(prefix.startIndex, offsetBy: 5)] == ".",
           prefix.last == " " {
            return String(name.dropFirst(prefixLen))
        }
        return name
    }

    /// 播放统计格式化：MM.dd(N)
    private static let playStatsDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM.dd"
        return f
    }()

    private var playStatsText: String {
        if isTodo {
            // 待办卡片：只显示日期
            return Self.playStatsDateFormatter.string(from: metadata.namePrefixDate)
        } else if let stats = playStats {
            // 有播放记录：展示 "MM.dd/N"
            return "\(Self.playStatsDateFormatter.string(from: metadata.namePrefixDate))/\(stats.playCount)"
        } else {
            // 无播放记录：只展示 "MM.dd"
            return Self.playStatsDateFormatter.string(from: metadata.namePrefixDate)
        }
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 封面区域
            Color.clear
                .aspectRatio(Constants.HomeCard.coverAspectRatio, contentMode: .fit)
                .overlay {
                    ZStack {
                        // 封面图
                        if let avatar = avatarImage {
                            Image(uiImage: avatar)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(Color.blue.opacity(0.08))
                                .overlay {
                                    Image(systemName: "book.closed.fill")
                                        .font(Constants.Fonts.homeCardPlaceholderIcon)
                                        .foregroundColor(.blue.opacity(0.25))
                                }
                        }

                        // 制作中蒙层
                        if isMaking {
                            Rectangle()
                                .fill(Color.black.opacity(Constants.HomeCard.makingOverlayOpacity))
                            if let progress = makeProgress {
                                Text("制作中 \(Int(progress * 100))%")
                                    .font(Constants.Fonts.homeCardProgress)
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                            } else {
                                Text("制作中")
                                    .font(Constants.Fonts.homeCardProgress)
                                    .foregroundColor(.white)
                            }
                        }

                        // 播放统计（图片左下角，跟标题左对齐）
                        VStack {
                            Spacer()
                            HStack {
                                Text(playStatsText)
                                    .font(Constants.Fonts.homeCardPlayStats)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, scaled(Constants.HomeCard.titleHorizontalPadding))
                            .padding(.bottom, scaled(4))
                        }
                    }
                }
                .clipped()

            // 名称栏（去掉日期前缀）
            HStack {
                Text(displayName)
                    .font(Constants.Fonts.homeCardTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, scaled(Constants.HomeCard.titleHorizontalPadding))
            .padding(.vertical, scaled(Constants.HomeCard.titleVerticalPadding))
            .background(isTodo ? Constants.HomeCard.todoCardBottomBackgroundColor : Color.clear)
        }
        .background(isTodo ? Constants.HomeCard.todoCardBackgroundColor : Color(.white))
        .clipShape(RoundedRectangle(cornerRadius: scaled(Constants.HomeCard.cornerRadius)))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMaking else { return }
            onTap()
        }
        .onAppear { loadAvatarImage() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.coverImageDidUpdate)) { notification in
            if let updatedId = notification.userInfo?["sessionId"] as? String, updatedId == metadata.id {
                SessionRecordManager.shared.invalidateHomeCardCoverCache(sessionId: updatedId)
                loadAvatarImage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.avatarImageDidUpdate)) { notification in
            if let updatedId = notification.userInfo?["sessionId"] as? String, updatedId == metadata.id {
                SessionRecordManager.shared.invalidateHomeCardCoverCache(sessionId: updatedId)
                loadAvatarImage()
            }
        }
    }

    private func loadAvatarImage() {
        guard metadata.totalImageCount > 0 else { return }
        let sid = metadata.id
        loadingId = sid
        let maxDim = Constants.HomeCard.coverAvatarMaxDimension
        DispatchQueue.global(qos: .utility).async {
            let image = SessionRecordManager.shared.loadHomeCardCover(
                sessionId: sid,
                avatarImageIndex: metadata.avatarImageIndex,
                totalImageCount: metadata.totalImageCount,
                maxDimension: maxDim
            )
            DispatchQueue.main.async {
                if loadingId == sid { avatarImage = image }
            }
        }
    }
}
