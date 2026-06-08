import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os.log

// MARK: - 会话记录列表展示模式
/// 标准：顶导 + 查看、编辑、删除、导入导出（不含播放，当前无调用方显式使用）
/// 嵌入：无顶导，仅播放、查看
/// 管理：顶导 + 查看、编辑、删除（不允许播放）、导入导出
enum SessionRecordListMode {
    case standard
    case embedded
    case manage
}

// MARK: - 管理页分组展示模式
private enum GroupMode: CaseIterable {
    case flat       // 平铺（list.bullet）
    case bySeries   // 按系列（square.grid.2x2）
    case byMonth    // 按月份（calendar）

    var iconName: String {
        switch self {
        case .flat: return "list.bullet"
        case .bySeries: return "square.grid.2x2"
        case .byMonth: return "calendar"
        }
    }

    var next: GroupMode {
        switch self {
        case .flat: return .bySeries
        case .bySeries: return .byMonth
        case .byMonth: return .flat
        }
    }
}

// MARK: - 会话记录列表视图
struct SessionRecordListView: View {
    // 跨Tab协调
    @ObservedObject var appState: AppState
    // 后台制作进度观察
    @ObservedObject private var bgMakeManager = BackgroundMakeManager.shared
    // 分页数据状态
    @State private var pagedMetadataList: [SessionRecordMetadata] = []
    @State private var playStatsMap: [String: PlayStatInfo] = [:]
    @State private var totalCount: Int = 0
    @State private var currentPage: Int = 1
    
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: SessionRecordMetadata?
    @State private var sessionToEditRecord: SessionRecord?  // 编辑时加载的完整记录
    @State private var isLoadingSession = false  // 加载会话记录时的加载状态
    @State private var showSessionDetail = false  // 显示会话详情
    @State private var sessionToView: SessionRecord?  // 要查看的会话记录
    @State private var exportLoadingState: SessionExportLoadingState?  // 导出准备状态
    @State private var showImportPicker = false  // 显示导入文件夹选择器
    @State private var exportItem: SessionExportableURL?  // 导出分享项
    @State private var isImporting = false  // 导入状态
    @State private var showMessage = false  // 显示操作结果提示
    @State private var message = ""  // 操作结果消息
    @State private var needReloadAfterMessage = false  // 提示关闭后是否需要刷新列表
    @State private var showClearConfirmation = false  // 显示清空确认弹窗
    @State private var showDeleteSelectedConfirmation = false  // 显示批量删除确认弹窗
    @State private var searchText: String = ""  // 搜索关键词
    @State private var selectedSeries: String? = nil  // nil 表示不限
    @State private var selectedReadStatus: SessionReadStatusFilter? = nil  // nil 表示不限
    @State private var seriesOptions: [String] = []   // 所有系列选项
    
    // 滚动位置追踪（首页嵌入模式用）
    @State private var scrollAnchorSetup = false
    @State private var scrollAnchorY: CGFloat = 0
    
    // 多选导出状态
    @State private var isSelectionMode: Bool = false
    @State private var selectedIDs: Set<String> = []
    @State private var allRecordIDs: [String] = []  // 所有记录的 ID 列表（用于全选）
    @State private var currentExportHistoryMode: ExportHistoryMode = .trimPlayEvents

    // 设备传输
    @State private var showDeviceTransfer = false
    @State private var deviceTransferIDs: [String] = []
    @State private var currentDeviceTransferMode: TransferMode = .full
    @State private var showPlayOnlyTransfer = false

    // 分组状态（仅管理 Tab 使用）
    @State private var groupMode: GroupMode = .flat
    @State private var expandedGroup: String? = nil
    @State private var allMetadataList: [SessionRecordMetadata] = []
    // 分组计算结果缓存（避免展开/折叠时重新计算导致乱序）
    @State private var cachedGroups: [(key: String, items: [SessionRecordMetadata])] = []

    // 编辑/查看页导航标记（防止返回时 .onAppear 重新加载列表丢失滚动位置）
    @State private var isEditingOrViewing: Bool = false
    
    let onLoadSession: (SessionRecord) -> Void
    var onLoadToMake: ((String) -> Void)? = nil
    /// 展示模式
    var mode: SessionRecordListMode = .standard
    /// 是否作为Tab首页（无返回按钮、无滑动返回手势）
    var isRootTab: Bool = false
    var onListScrolled: ((Bool) -> Void)? = nil

    private var showTopNav: Bool { mode != .embedded }
    private var allowEditDelete: Bool { mode != .embedded }
    /// embedded 模式下搜索框默认隐藏在顶导上方，其他模式默认可见
    private var hideSearchBarByDefault: Bool { mode == .embedded }
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // 检测是否为 iPad
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
    // iPad 竖屏时的最大内容宽度
    private var maxContentWidth: CGFloat {
        .infinity
    }
    
    private var hasMoreItems: Bool {
        pagedMetadataList.count < totalCount
    }
    
    // 是否处于分组模式
    private var isGroupedMode: Bool { groupMode != .flat }

    /// 根据 allMetadataList 和 groupMode 重新计算分组，结果写入 cachedGroups
    private func rebuildGroups() {
        guard groupMode != .flat else {
            cachedGroups = []
            return
        }

        let keyExtractor: (SessionRecordMetadata) -> String = { item in
            switch groupMode {
            case .flat:
                return ""
            case .bySeries:
                return item.seriesName
            case .byMonth:
                return item.monthKey
            }
        }

        var groups: [String: [SessionRecordMetadata]] = [:]
        for item in allMetadataList {
            let key = keyExtractor(item)
            groups[key, default: []].append(item)
        }

        let uncategorized = Constants.GroupDisplay.uncategorizedLabel
        let sorted = groups.map { (key: $0.key, items: $0.value.sorted { $0.namePrefixDate > $1.namePrefixDate }) }
            .sorted { lhs, rhs in
                if lhs.key == uncategorized { return false }
                if rhs.key == uncategorized { return true }
                if groupMode == .bySeries {
                    return lhs.key.localizedCompare(rhs.key) == .orderedAscending
                } else {
                    let lhsDate = lhs.items.first?.namePrefixDate ?? Date.distantPast
                    let rhsDate = rhs.items.first?.namePrefixDate ?? Date.distantPast
                    return lhsDate > rhsDate
                }
            }
        cachedGroups = sorted
    }

    // 手风琴组头
    private func groupHeaderView(key: String, count: Int, latestDate: Date) -> some View {
        let isExpanded = expandedGroup == key
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MM.dd"
            return f
        }()

        return HStack(spacing: scaled(8)) {
                Image(systemName: "chevron.right")
                    .font(Constants.Fonts.groupChevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(key)
                    .font(Constants.Fonts.body)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(count)条")
                    .font(Constants.Fonts.recordMeta)
                    .foregroundColor(.secondary)

                Text("最近\(dateFormatter.string(from: latestDate))")
                    .font(Constants.Fonts.recordMeta)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, scaled(16))
            .frame(height: Constants.GroupDisplay.groupHeaderHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedGroup = isExpanded ? nil : key
                }
            }
    }

    // 搜索栏（微信风格，外层 padding 由 listRowInsets 控制）
    private var searchBar: some View {
        SessionSearchBar(
            searchText: $searchText,
            selectedSeries: $selectedSeries,
            selectedReadStatus: $selectedReadStatus,
            seriesOptions: seriesOptions,
            onSearchSubmit: {
                if isGroupedMode {
                    loadAllMetadata()
                } else {
                    currentPage = 1
                    loadPage()
                }
            }
        )
    }
    
    // 分组模式列表内容
    @ViewBuilder
    private var groupedListContent: some View {
        let groups = cachedGroups
        if groups.isEmpty {
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
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(.systemBackground))
            .listRowSeparator(.hidden)
        } else {
            ForEach(groups, id: \.key) { group in
                Section {
                    groupHeaderView(
                        key: group.key,
                        count: group.items.count,
                        latestDate: group.items.first?.namePrefixDate ?? Date()
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    if expandedGroup == group.key {
                        ForEach(group.items) { metadata in
                            self.makeSessionRecordRow(for: metadata)
                        }
                    }
                }
            }
        }
    }

    // 平铺模式列表内容
    @ViewBuilder
    private var flatListContent: some View {
        if pagedMetadataList.isEmpty {
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
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(.systemBackground))
            .listRowSeparator(.hidden)
        } else {
            ForEach(pagedMetadataList) { metadata in
                self.makeSessionRecordRow(for: metadata)
                    .onAppear {
                        loadNextPageIfNeeded(currentItem: metadata)
                    }
                    .overlay {
                        if metadata.id == pagedMetadataList.first?.id {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        if !scrollAnchorSetup {
                                            scrollAnchorY = geo.frame(in: .named("listOuter")).minY
                                        }
                                    }
                                    .onChange(of: geo.frame(in: .named("listOuter")).minY) { _, newY in
                                        guard scrollAnchorSetup else {
                                            scrollAnchorY = newY
                                            return
                                        }
                                        onListScrolled?(newY < scrollAnchorY - 5)
                                    }
                            }
                        }
                    }
            }

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: scaled(Constants.Pagination.controlHeight))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color(.systemBackground))
                    .listRowSeparator(.hidden)
            }
        }
    }
    
    // 主内容区（loading / empty / list）
    @ViewBuilder
    private var mainContentArea: some View {
        if isLoading {
            Spacer()
            ProgressView("加载中...")
                .scaleEffect(scaled(1.0))
            Spacer()
        } else if !isGroupedMode
            && totalCount == 0
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

                Text("导入记录，或播放完成后保存记录")
                    .font(Constants.Fonts.recordMeta)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            GeometryReader { geo in
                ScrollViewReader { scrollProxy in
                    // 计算内容高度
                    let searchBarHeight: CGFloat = Constants.SearchBar.rowMinHeight
                    let groupHeaderHeight: CGFloat = Constants.GroupDisplay.groupHeaderHeight
                    let rowHeight: CGFloat = scaled(56)

                    let groupCount = cachedGroups.count
                    let expandedItemCount = cachedGroups
                        .first(where: { $0.key == expandedGroup })?.items.count ?? 0
                    let flatItemCount = pagedMetadataList.count

                    let contentHeight = isGroupedMode
                        ? searchBarHeight + CGFloat(groupCount) * groupHeaderHeight + CGFloat(expandedItemCount) * rowHeight
                        : searchBarHeight + CGFloat(flatItemCount) * rowHeight
                    let spacerHeight = max(0, geo.size.height - contentHeight)

                    List {
                        searchBar
                            .frame(minHeight: Constants.SearchBar.rowMinHeight)
                            .listRowInsets(EdgeInsets(
                                top: Constants.SearchBar.topPadding,
                                leading: Constants.SearchBar.outerHorizontalPadding,
                                bottom: Constants.SearchBar.bottomPadding,
                                trailing: Constants.SearchBar.outerHorizontalPadding
                            ))
                            .listRowBackground(Color(.systemBackground))
                            .listRowSeparator(.hidden)
                            .id(Constants.UI.searchBarRowId)

                        if isGroupedMode {
                            groupedListContent
                        } else {
                            flatListContent
                        }

                        if spacerHeight > 0 {
                            Color.clear
                                .frame(height: spacerHeight)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color(.systemBackground))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    // .scrollContentBackground(.hidden)
                    .onAppear {
                        if hideSearchBarByDefault {
                            scrollToHideSearchBar(proxy: scrollProxy)
                        }
                    }
                } // ScrollViewReader
            } // GeometryReader
        }
    }

    var body: some View {
        CustomZStack {
            // 主内容区
            HStack {
                VStack(spacing: 0) {
                    mainContentArea
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.top, showTopNav ? (scaled(45)) : 0)
                .coordinateSpace(name: "listOuter")
            }
            
            if showTopNav {
                if isSelectionMode {
                    // 多选模式下的操作栏
                    TopAndLeftSideNavigationBar(
                        title: "选中 (\(selectedIDs.count))",
                        onSwipeBack: { },
                        leading: {
                            // 左侧按钮：全选/本页/反选
                            HStack(spacing: scaled(16)) {
                                Button(action: {
                                    selectedIDs = Set(allRecordIDs.filter { $0 != Constants.DefaultSession.id })
                                }) {
                                    Text("全选")
                                        .font(Constants.Fonts.listAction)
                                }
                                Button(action: {
                                    selectCurrentPage()
                                }) {
                                    Text("本页")
                                        .font(Constants.Fonts.listAction)
                                }
                                Button(action: {
                                    toggleSelection()
                                }) {
                                    Text("反选")
                                        .font(Constants.Fonts.listAction)
                                }
                            }
                        },
                        trailing: {
                            HStack(spacing: scaled(12)) {
                                // 设备传输按钮（有选中时可用）
                                Button(action: {
                                    if !selectedIDs.isEmpty {
                                        deviceTransferIDs = Array(selectedIDs)
                                        currentDeviceTransferMode = .full
                                        showDeviceTransfer = true
                                    }
                                }) {
                                    Text("传输")
                                        .font(Constants.Fonts.listAction)
                                }
                                .disabled(selectedIDs.isEmpty)

                                // 取消按钮
                                Button(action: {
                                    isSelectionMode = false
                                    selectedIDs.removeAll()
                                }) {
                                    Text("取消")
                                        .font(Constants.Fonts.listAction)
                                }

                                // 更多菜单
                                Menu {
                                    Button(action: {
                                        if !selectedIDs.isEmpty {
                                            currentExportHistoryMode = .trimPlayEvents
                                            exportSelectedSessions()
                                        }
                                    }) {
                                        Label("导出", systemImage: "square.and.arrow.up")
                                    }
                                    .disabled(selectedIDs.isEmpty)

                                    Button(action: {
                                        if !selectedIDs.isEmpty {
                                            currentExportHistoryMode = .keepAllEvents
                                            exportSelectedSessions()
                                        }
                                    }) {
                                        Label("导出(带统计)", systemImage: "chart.bar.doc.horizontal")
                                    }
                                    .disabled(selectedIDs.isEmpty)

                                    Button(action: {
                                        if !selectedIDs.isEmpty {
                                            deviceTransferIDs = Array(selectedIDs)
                                            currentDeviceTransferMode = .fullWithStats
                                            showDeviceTransfer = true
                                        }
                                    }) {
                                        Label("传输(带统计)", systemImage: "chart.bar.xaxis")
                                    }
                                    .disabled(selectedIDs.isEmpty)

                                    Button(action: {
                                        if !selectedIDs.isEmpty {
                                            deviceTransferIDs = Array(selectedIDs)
                                            currentDeviceTransferMode = .playOnly
                                            showPlayOnlyTransfer = true
                                        }
                                    }) {
                                        Label("传输播放记录", systemImage: "speaker.wave.2")
                                    }
                                    .disabled(selectedIDs.isEmpty)

                                    Divider()

                                    Button(role: .destructive, action: {
                                        if !selectedIDs.isEmpty {
                                            showDeleteSelectedConfirmation = true
                                        }
                                    }) {
                                        Label("删除", systemImage: "trash")
                                    }
                                    .disabled(selectedIDs.isEmpty)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(Constants.Fonts.listAddIcon)
                                        .foregroundColor(.blue)
                                        .background(Color.clear)
                                }
                            }
                        }
                    )
                } else {
                    // 正常模式下的导航栏
                    TopAndLeftSideNavigationBar(
                        title: isRootTab ? "管理" : "会话记录",
                        onSwipeBack: isRootTab ? nil : { dismiss() },
                        leading: {
                            if isRootTab {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        groupMode = groupMode.next
                                        expandedGroup = nil
                                    }
                                    if groupMode == .flat {
                                        cachedGroups = []
                                        currentPage = 1
                                        loadPage()
                                    } else {
                                        loadAllMetadata()
                                    }
                                }) {
                                    Image(systemName: groupMode.iconName)
                                        .symbolRenderingMode(.monochrome)
                                        .font(Constants.Fonts.navAction)
                                        .frame(width: scaled(20), height: scaled(20))
                                        .foregroundStyle(.primary)
                                }
                            } else {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "chevron.left")
                                        .font(Constants.Fonts.navAction)
                                        .frame(width: scaled(20), height: scaled(20))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }, trailing: {
                        Menu {
                            // 发起新制作任务（多任务并发，上限 Constants.BackgroundMake.maxConcurrentTasks）
                            Button(action: {
                                appState.openCameraOnNextRecordAppear = true
                                appState.selectedTab = 1
                            }) {
                                Label("拍照制作", systemImage: "camera")
                            }
                            Button(action: {
                                appState.openPhotoPickerOnNextRecordAppear = true
                                appState.selectedTab = 1
                            }) {
                                Label("选图制作", systemImage: "photo.on.rectangle")
                            }
                            Divider()
                            Button(action: { showImportPicker = true }) {
                                Label("导入", systemImage: "square.and.arrow.down")
                            }
                            Button(action: { startExportSelectionMode() }) {
                                Label("导出", systemImage: "square.and.arrow.up")
                            }
                            .disabled(totalCount == 0)
                            Button(action: { startExportSelectionMode(historyMode: .keepAllEvents) }) {
                                Label("导出(带统计)", systemImage: "chart.bar.doc.horizontal")
                            }
                            .disabled(totalCount == 0)
                            Divider()
                            Button(role: .destructive, action: { showClearConfirmation = true }) {
                                Label("清空", systemImage: "trash")
                            }
                            .disabled(totalCount == 0)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(Constants.Fonts.listAddIcon)
                                .foregroundColor(.blue)
                                .background(Color.clear)
                        }
                    })
                }
            }
        }
        .navigationBarHidden(true) // 隐藏系统导航栏
        .onAppear {
            if isEditingOrViewing {
                // 从编辑/查看页返回，@State 已保持，不重新加载，保留滚动位置
                isEditingOrViewing = false
            } else {
                loadPage()
                loadSeriesOptions()
            }
            handlePendingEditRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.sessionsDidImport)) { _ in
            loadPage()
            loadSeriesOptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.sessionMetadataDidUpdate)) { notification in
            if let sessionId = notification.userInfo?["sessionId"] as? String {
                handleSessionMetadataUpdate(sessionId: sessionId)
            } else {
                handleSessionMetadataUpdate(sessionId: nil)
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab == 2 {
                handlePendingEditRequest()
            }
        }
        .onChange(of: appState.tab2ReselectTrigger) {
            guard !isGroupedMode, currentPage != 1 else { return }
            currentPage = 1
            loadPage()
        }
        .onChange(of: searchText) {
            // 清空时自动刷新回原列表
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if isGroupedMode {
                    loadAllMetadata()
                } else {
                    currentPage = 1
                    loadPage()
                }
            }
        }
        .onChange(of: selectedSeries) {
            if isGroupedMode {
                loadAllMetadata()
            } else {
                currentPage = 1
                loadPage()
            }
        }
        .onChange(of: selectedReadStatus) {
            if isGroupedMode {
                loadAllMetadata()
            } else {
                currentPage = 1
                loadPage()
            }
        }
        .alert("删除会话记录", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                sessionToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session.id)
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("确定要删除会话记录「\(session.name)」吗？此操作无法撤销。")
            }
        }
        .navigationDestination(item: $sessionToEditRecord) { record in
            SessionRecordUnifiedView(
                mode: .edit(
                    record,
                    onSave: { newName, newAvatarIndex, newAnimationStyle in
                        updateSession(id: record.id, name: newName, avatarImageIndex: newAvatarIndex, animationStyle: newAnimationStyle) {
                            sessionToEditRecord = nil
                        }
                    },
                    onDismiss: {
                        sessionToEditRecord = nil
                    }
                )
            )
        }
        .navigationDestination(isPresented: $showSessionDetail) {
            if let record = sessionToView {
                SessionRecordUnifiedView(
                    mode: .view(record, onDismiss: {
                        showSessionDetail = false
                        sessionToView = nil
                    })
                )
            }
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importSessions(from: url)
            case .failure:
                message = "选择文件夹失败"
                showMessage = true
            }
        }
        .sheet(item: $exportItem) { item in
            ExportShareSheet(item: item) { _ in
                exportItem = nil
                exportLoadingState = nil
            }
        }
        .navigationDestination(isPresented: $showDeviceTransfer) {
            DeviceTransferView(sessionIDs: deviceTransferIDs, transferMode: currentDeviceTransferMode)
        }
        .navigationDestination(isPresented: $showPlayOnlyTransfer) {
            DeviceTransferView(sessionIDs: deviceTransferIDs, transferMode: .playOnly)
        }
        .onChange(of: showDeviceTransfer) { _, newValue in
            if !newValue && isSelectionMode {
                isSelectionMode = false
                selectedIDs.removeAll()
            }
        }
        .onChange(of: showPlayOnlyTransfer) { _, newValue in
            if !newValue && isSelectionMode {
                isSelectionMode = false
                selectedIDs.removeAll()
            }
        }
        .overlay {
            if let exportLoadingState {
                ExportLoadingView(state: exportLoadingState)
            } else if isImporting {
                CustomZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("正在导入...").font(Constants.Fonts.headline).foregroundColor(.white)
                    }
                }
            }
        }
        .alert("提示", isPresented: $showMessage) {
            Button("确定", role: .cancel) {
                if needReloadAfterMessage {
                    needReloadAfterMessage = false
                    loadPage()
                }
            }
        } message: {
            Text(message)
        }
        .alert("清空所有记录", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAllSessions()
            }
        } message: {
            Text("确定要清空所有会话记录吗？")
        }
        .alert("删除选中记录", isPresented: $showDeleteSelectedConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteSelectedSessions()
            }
        } message: {
            Text("确定要删除选中的 \(selectedIDs.count) 条会话记录吗？此操作无法撤销。")
        }
    }
    
    // 创建会话记录行视图（拆分类型检查）
    private func makeSessionRecordRow(for metadata: SessionRecordMetadata) -> some View {
        let makeProgress: Float? = {
            // 多任务并发下按 sessionId 精准定位任务进度
            guard metadata.isMaking,
                  let task = bgMakeManager.task(for: metadata.id),
                  !task.isCompleted else { return nil }
            return task.progress
        }()

        let isDefault = metadata.isDefault
        let isMaking = metadata.isMaking
        let isIncomplete = metadata.isIncomplete

        let canEnterSelectionMode = !isDefault && !isMaking && allowEditDelete && !isSelectionMode

        // 非 embedded 模式下是否允许左滑操作
        let allowSwipeActions = mode != .embedded && !isSelectionMode && allowEditDelete

        return SessionRecordRow(
            metadata: metadata,
            makeProgress: makeProgress,
            playCount: playStatsMap[metadata.id]?.playCount ?? 0,
            mode: mode,
            onLoad: (mode == .embedded && !isMaking && !isIncomplete && !isSelectionMode) ? { loadSession(metadata.id) } : nil,
            onLoadToMake: (!isDefault && mode == .manage && onLoadToMake != nil && !isSelectionMode) ? { onLoadToMake?(metadata.id) } : nil,
            onView: (!isMaking && !isSelectionMode) ? {
                viewSessionDetail(metadata.id)
            } : nil,
            onEdit: (!isDefault && allowEditDelete && !isMaking && !isSelectionMode) ? { editSessionDetail(metadata.id) } : nil,
            onExport: (!isDefault && allowEditDelete && !isMaking && !isSelectionMode) ? { exportOneSession(id: metadata.id) } : nil,
            onDeviceTransfer: (!isDefault && allowEditDelete && !isMaking && !isSelectionMode) ? {
                deviceTransferIDs = [metadata.id]
                currentDeviceTransferMode = .full
                showDeviceTransfer = true
            } : nil,
            onDelete: (!isDefault && allowEditDelete && !isSelectionMode) ? {
                sessionToDelete = metadata
                showDeleteConfirmation = true
            } : nil,
            isSelectionMode: isSelectionMode,
            isSelected: selectedIDs.contains(metadata.id),
            onToggleSelection: {
                if selectedIDs.contains(metadata.id) {
                    selectedIDs.remove(metadata.id)
                } else {
                    selectedIDs.insert(metadata.id)
                }
            },
            onLongPress: canEnterSelectionMode ? {
                enterSelectionModeAndSelect(id: metadata.id)
            } : nil
        )
        // 非 embedded 模式下添加左滑操作按钮（仅文字，方块相连）
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowSwipeActions {
                if isMaking {
                    // 制作中记录显示删除、前台和查看按钮
                    Button("删除") {
                        sessionToDelete = metadata
                        showDeleteConfirmation = true
                    }
                    .tint(.red)

                    Button("前台") {
                        onLoadToMake?(metadata.id)
                    }
                    .tint(.orange)
                    .disabled(mode != .manage || onLoadToMake == nil)

                    Button("查看") {
                        viewSessionDetail(metadata.id)
                    }
                    .tint(.blue)
                } else if !isDefault {
                    Button("删除") {
                        sessionToDelete = metadata
                        showDeleteConfirmation = true
                    }
                    .tint(.red)

                    Button("制作") {
                        onLoadToMake?(metadata.id)
                    }
                    .tint(.orange)
                    .disabled(mode != .manage || onLoadToMake == nil)
                    
                    Button("编辑") {
                        editSessionDetail(metadata.id)
                    }
                    .tint(.blue)
                }
            }
        }
    }
    
    // 自动滚动到第一条记录，隐藏搜索栏
    private func scrollToHideSearchBar(proxy: ScrollViewProxy) {
        // 搜索框有输入文本时，不隐藏
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let firstId = pagedMetadataList.first?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(firstId, anchor: .top)
            // 自动滚动完成后锁定基准位置
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.scrollAnchorSetup = true
            }
        }
    }
    
    // 按需加载首批数据（showLoading=false 时静默刷新，不销毁列表视图）
    private func loadPage(showLoading: Bool = true) {
        loadBatch(page: 1, append: false, showLoading: showLoading)
    }

    private func loadNextPageIfNeeded(currentItem: SessionRecordMetadata) {
        guard currentItem.id == pagedMetadataList.last?.id,
              hasMoreItems,
              !isLoading,
              !isLoadingMore else {
            return
        }
        loadBatch(page: currentPage + 1, append: true, showLoading: true)
    }

    private func refreshLoadedPages(showLoading: Bool = false) {
        let loadedPageCount = max(1, currentPage)
        loadBatch(page: 1, append: false, showLoading: showLoading, pageSizeOverride: Constants.Pagination.pageSize * loadedPageCount)
    }

    private func handleSessionMetadataUpdate(sessionId: String?) {
        loadSeriesOptions()

        if isGroupedMode {
            guard sessionId == nil || allMetadataList.contains(where: { $0.id == sessionId }) else { return }
            loadAllMetadata()
        } else {
            guard sessionId == nil || pagedMetadataList.contains(where: { $0.id == sessionId }) else { return }
            refreshLoadedPages(showLoading: false)
        }
    }

    private func loadBatch(page: Int, append: Bool, showLoading: Bool = true, pageSizeOverride: Int? = nil) {
        if append {
            isLoadingMore = true
        } else {
            if showLoading {
                isLoading = true
            }
            isLoadingMore = false
        }

        let pageSize = Constants.Pagination.pageSize
        let requestPageSize = pageSizeOverride ?? pageSize
        let keyword = searchText
        let series = selectedSeries
        let readStatus = selectedReadStatus

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SessionRecordManager.shared.getSessionMetadataPage(
                page: page,
                pageSize: requestPageSize,
                searchKeyword: keyword,
                seriesFilter: series,
                readStatusFilter: readStatus,
                caller: "记录列表"
            )
            let statsMap = mode == .manage
                ? SessionRecordManager.shared.loadPlayStats(sessionIds: result.items.map(\.id))
                : [:]
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

                if append {
                    guard !result.items.isEmpty else {
                        self.totalCount = result.totalCount
                        return
                    }
                    let existingIds = Set(self.pagedMetadataList.map(\.id))
                    let newItems = result.items.filter { !existingIds.contains($0.id) }
                    self.pagedMetadataList += newItems
                    self.playStatsMap.merge(statsMap) { _, new in new }
                    self.totalCount = result.totalCount
                    self.currentPage = page
                } else {
                    self.pagedMetadataList = result.items
                    self.playStatsMap = statsMap
                    self.totalCount = result.totalCount
                    self.currentPage = max(1, Int(ceil(Double(result.items.count) / Double(pageSize))))
                }
            }
        }
    }

    /// 分组模式：全量加载 metadata（带搜索过滤）
    private func loadAllMetadata() {
        isLoading = true
        let keyword = searchText
        let seriesFilter = selectedSeries
        let readStatusFilter = selectedReadStatus
        DispatchQueue.global(qos: .userInitiated).async {
            let list = SessionRecordManager.shared.getFilteredSessionMetadata(
                searchKeyword: keyword,
                seriesFilter: seriesFilter,
                readStatusFilter: readStatusFilter,
                caller: "分组列表"
            )
            let statsMap = mode == .manage
                ? SessionRecordManager.shared.loadPlayStats(sessionIds: list.map(\.id))
                : [:]
            DispatchQueue.main.async {
                let visibleIds = list.map(\.id)
                for id in visibleIds {
                    self.playStatsMap.removeValue(forKey: id)
                }
                self.allMetadataList = list
                self.playStatsMap.merge(statsMap) { _, new in new }
                self.totalCount = list.count
                self.rebuildGroups()
                self.isLoading = false
            }
        }
    }

    // MARK: - 系列筛选
    private func loadSeriesOptions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "管理页系列选项")
            let uncategorized = Constants.GroupDisplay.uncategorizedLabel
            let seriesSet = Set(allMetadata.map { $0.seriesName })
                .filter { $0 != uncategorized }
            let sortedSeries = Array(seriesSet).sorted { $0.localizedCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                self.seriesOptions = sortedSeries
            }
        }
    }

    /// 处理制作完成后跳转到编辑页的请求
    private func handlePendingEditRequest() {
        guard mode != .embedded else { return }
        guard let recordId = appState.recordIdToEditInManageTab else { return }
        // 立即消费标志位
        appState.recordIdToEditInManageTab = nil

        // 同步加载记录并立即打开编辑页，避免列表闪现
        if let record = SessionRecordManager.shared.loadSession(id: recordId) {
            self.sessionToEditRecord = record
            os.Logger.sessionRecord.info("制作完成，跳转到编辑页: sessionId=\(recordId)")
        } else {
            os.Logger.sessionRecord.warning("制作完成跳转编辑页失败: 未找到会话 \(recordId)")
        }
    }
    
    // 加载指定会话记录
    private func loadSession(_ id: String) {
        // 显示加载提示
        isLoadingSession = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let record = SessionRecordManager.shared.loadSession(id: id) {
                DispatchQueue.main.async {
                    // 延迟一下，让用户看到加载提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.isLoadingSession = false
                        onLoadSession(record)
                        if showTopNav {
                            dismiss()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingSession = false
                }
            }
        }
    }
    
    // 删除会话记录（乐观删除：先更新 UI，再后台删磁盘）
    private func deleteSession(_ id: String) {
        // 立即从本地数组移除，避免 loadPage() 的 isLoading 闪变
        withAnimation {
            if isGroupedMode {
                allMetadataList.removeAll { $0.id == id }
                totalCount = allMetadataList.count
                rebuildGroups()
            } else {
                pagedMetadataList.removeAll { $0.id == id }
                totalCount = max(0, totalCount - 1)
            }
            playStatsMap.removeValue(forKey: id)
        }
        sessionToDelete = nil

        // 后台执行磁盘删除
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = SessionRecordManager.shared.deleteSession(id: id)
            DispatchQueue.main.async {
                // 已加载列表为空但还有数据时，重新拉取首批
                if !self.isGroupedMode && self.pagedMetadataList.isEmpty && self.totalCount > 0 {
                    self.loadPage()
                }
            }
        }
    }
    
    // 查看会话记录详情
    private func viewSessionDetail(_ id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let record = SessionRecordManager.shared.loadSession(id: id) {
                DispatchQueue.main.async {
                    self.isEditingOrViewing = true
                    self.sessionToView = record
                    self.showSessionDetail = true
                }
            }
        }
    }

    // 编辑会话记录
    private func editSessionDetail(_ id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let record = SessionRecordManager.shared.loadSession(id: id) {
                DispatchQueue.main.async {
                    self.isEditingOrViewing = true
                    self.sessionToEditRecord = record
                }
            }
        }
    }
    
    // 导入会话记录：若选择导出包则全量导入，若选择单个会话目录则仅导入该条
    private func importSessions(from sourceURL: URL) {
        isImporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 在异步线程中获取访问权限
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 执行导入操作（自动识别导出包 / 单条会话目录）
            let result = SessionRecordManager.shared.importSessions(from: sourceURL)
            
            DispatchQueue.main.async {
                self.isImporting = false
                
                if result.success {
                    let imported = result.importedCount
                    let duplicate = result.duplicateCount
                    let skipped = result.skippedCount
                    let total = imported + duplicate + skipped
                    let formattedSize = self.formatStorageSize(result.totalSize)
                    
                    var msg = "共 \(total) 个，导入 \(imported) 个"
                    let skipSummaryLines = self.formatSkipReasonSummary(result.skipReasonCounts)
                    if !skipSummaryLines.isEmpty {
                        msg += "\n" + skipSummaryLines.joined(separator: "\n")
                    }
                    if imported > 0 {
                        msg += "\n总大小: \(formattedSize)"
                    }
                    
                    self.message = msg
                    self.needReloadAfterMessage = imported > 0
                    self.showMessage = true
                } else {
                    self.message = "导入失败: \(result.errorMessage ?? "未知错误")"
                    self.showMessage = true
                }
            }
        }
    }

    private func formatSkipReasonSummary(_ skipReasonCounts: [SessionImportSkipReason: Int]) -> [String] {
        SessionImportSkipReason.allCases.compactMap { reason in
            guard let count = skipReasonCounts[reason], count > 0 else { return nil }
            return "\(reason.displayName) \(count) 条"
        }
    }
    
    // 格式化存储大小
    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 更新会话记录
    private func updateSession(id: String, name: String? = nil, avatarImageIndex: Int? = nil, animationStyle: AnimationStyle? = nil, completion: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SessionRecordManager.shared.updateSession(id: id, name: name, avatarImageIndex: avatarImageIndex, animationStyle: animationStyle)
            DispatchQueue.main.async {
                if success {
                    if isGroupedMode {
                        loadAllMetadata()
                    } else {
                        // 静默刷新已加载批次：不显示加载指示器，保留列表滚动位置
                        refreshLoadedPages(showLoading: false)
                    }
                }
                completion()
            }
        }
    }

    // 导出单条会话记录到临时目录，然后通过分享面板分享
    private func exportOneSession(id: String, historyMode: ExportHistoryMode = .trimPlayEvents) {
        exportLoadingState = SessionExportLoadingState(
            title: "正在准备导出",
            completedCount: 0,
            totalCount: 1
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let tempBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoTTS_OneExport_\(UUID().uuidString.prefix(8))", isDirectory: true)
            let result = SessionRecordManager.shared.exportSession(
                id: id,
                to: tempBase,
                historyMode: historyMode
            ) { progress in
                self.applyExportProgress(progress, title: "正在准备导出")
            }
            DispatchQueue.main.async {
                if result.success {
                    self.prepareExportShareItem(from: tempBase)
                } else {
                    self.exportLoadingState = nil
                    self.message = "导出失败: \(result.errorMessage ?? "未知错误")"
                    self.showMessage = true
                    try? FileManager.default.removeItem(at: tempBase)
                }
            }
        }
    }

    // 清空所有会话记录
    private func clearAllSessions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SessionRecordManager.shared.clearAllSessions()
            DispatchQueue.main.async {
                if result.success {
                    self.message = "已清空 \(result.count) 个会话记录"
                } else {
                    self.message = result.errorMessage ?? "清空失败"
                }
                self.currentPage = 1
                self.needReloadAfterMessage = true
                self.showMessage = true
            }
        }
    }
    
    // 进入导出多选模式
    private func startExportSelectionMode(historyMode: ExportHistoryMode = .trimPlayEvents) {
        currentExportHistoryMode = historyMode
        isSelectionMode = true
        selectedIDs.removeAll()
        loadAllRecordIDs()
    }

    // 长按进入多选模式并选中指定记录
    private func enterSelectionModeAndSelect(id: String) {
        guard id != Constants.DefaultSession.id else { return }
        startExportSelectionMode()
        selectedIDs.insert(id)
    }
    
    // 加载所有记录 ID（用于全选功能）
    private func loadAllRecordIDs() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "多选导出")
            DispatchQueue.main.async {
                self.allRecordIDs = allMetadata.map { $0.id }
            }
        }
    }

    // 选中已加载记录：选中当前已懒加载出的所有非默认记录
    private func selectCurrentPage() {
        let currentLoadedIDs = pagedMetadataList
            .filter { $0.id != Constants.DefaultSession.id }
            .map { $0.id }
        selectedIDs.formUnion(currentLoadedIDs)
    }

    // 反选：切换已加载记录中所有非默认记录的选中状态
    private func toggleSelection() {
        let currentLoadedIDs = pagedMetadataList
            .filter { $0.id != Constants.DefaultSession.id }
            .map { $0.id }
        let currentLoadedSet = Set(currentLoadedIDs)

        // 已加载范围内已选中的记录
        let selectedInCurrentLoaded = selectedIDs.intersection(currentLoadedSet)
        // 已加载范围内未选中的记录
        let unselectedInCurrentLoaded = currentLoadedSet.subtracting(selectedInCurrentLoaded)

        // 移除已加载范围内已选中的，添加未选中的
        selectedIDs.subtract(selectedInCurrentLoaded)
        selectedIDs.formUnion(unselectedInCurrentLoaded)
    }
    
    // 导出选中的会话记录
    private func exportSelectedSessions() {
        guard !selectedIDs.isEmpty else {
            message = "请选择要导出的记录"
            showMessage = true
            return
        }
        
        exportLoadingState = SessionExportLoadingState(
            title: "正在准备导出",
            completedCount: 0,
            totalCount: max(selectedIDs.count, 1)
        )
        
        let selectedIDsCopy = selectedIDs
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 创建临时目录作为导出目标
            let tempBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoTTS_SessionExport_\(UUID().uuidString.prefix(8))", isDirectory: true)
            
            // 在后台线程获取权威总数，避免依赖可能未加载完成的 allRecordIDs
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "导出全选判断")
            let nonDefaultCount = allMetadata.filter { $0.id != Constants.DefaultSession.id }.count
            let isAllSelected = selectedIDsCopy.count >= nonDefaultCount && nonDefaultCount > 0
            
            // 执行导出操作
            let result = SessionRecordManager.shared.exportSelectedSessions(
                Array(selectedIDsCopy),
                to: tempBase,
                isAllSelected: isAllSelected,
                historyMode: currentExportHistoryMode
            ) { progress in
                self.applyExportProgress(progress, title: "正在准备导出")
            }
            
            DispatchQueue.main.async {
                self.isSelectionMode = false
                self.selectedIDs.removeAll()
                
                if result.success {
                    self.prepareExportShareItem(from: tempBase)
                } else {
                    self.exportLoadingState = nil
                    self.message = "导出失败：\(result.errorMessage ?? "未知错误")"
                    self.showMessage = true
                    // 清理临时目录
                    try? FileManager.default.removeItem(at: tempBase)
                }
            }
        }
    }

    private func applyExportProgress(_ progress: SessionExportProgress, title: String) {
        DispatchQueue.main.async {
            self.exportLoadingState = SessionExportLoadingState(
                title: title,
                completedCount: progress.completedCount,
                totalCount: progress.totalCount
            )
        }
    }

    private func prepareExportShareItem(from tempBase: URL) {
        exportLoadingState = SessionExportLoadingState(
            title: "正在准备导出",
            completedCount: 1,
            totalCount: 1
        )

        if let contents = try? FileManager.default.contentsOfDirectory(at: tempBase, includingPropertiesForKeys: nil),
           let exportDir = contents.first {
            exportItem = SessionExportableURL(url: exportDir, cleanupRootURL: tempBase)
        } else {
            exportItem = SessionExportableURL(url: tempBase, cleanupRootURL: tempBase)
        }
    }

    // 批量删除选中的会话记录
    private func deleteSelectedSessions() {
        guard !selectedIDs.isEmpty else {
            return
        }

        let idsToDelete = Array(selectedIDs)

        // 立即从本地数组移除，避免 loadPage() 的 isLoading 闪变
        withAnimation {
            if isGroupedMode {
                allMetadataList.removeAll { idsToDelete.contains($0.id) }
                totalCount = allMetadataList.count
                rebuildGroups()
            } else {
                pagedMetadataList.removeAll { idsToDelete.contains($0.id) }
                totalCount = max(0, totalCount - idsToDelete.count)
            }
            for id in idsToDelete {
                playStatsMap.removeValue(forKey: id)
            }
        }

        // 退出多选模式
        isSelectionMode = false
        selectedIDs.removeAll()

        // 后台执行磁盘删除
        DispatchQueue.global(qos: .userInitiated).async {
            for id in idsToDelete {
                _ = SessionRecordManager.shared.deleteSession(id: id)
            }
            DispatchQueue.main.async {
                // 已加载列表为空但还有数据时，重新拉取首批
                if !self.isGroupedMode && self.pagedMetadataList.isEmpty && self.totalCount > 0 {
                    self.loadPage()
                }
            }
        }
    }
}

// MARK: - 会话记录行视图
struct SessionRecordRow: View {
    let metadata: SessionRecordMetadata
    /// 后台制作实时进度（0.0~1.0），nil 表示无活跃任务或非制作中状态
    var makeProgress: Float? = nil
    var playCount: Int = 0
    let mode: SessionRecordListMode
    let onLoad: (() -> Void)?
    let onLoadToMake: (() -> Void)?
    let onView: (() -> Void)?
    let onEdit: (() -> Void)?
    let onExport: (() -> Void)?
    let onDeviceTransfer: (() -> Void)?
    let onDelete: (() -> Void)?
    
    // 多选模式参数
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil

    @State private var avatarImage: UIImage? = nil
    @State private var loadingId: String? = nil

    // 计算属性：是否展示播放按钮
    private var showPlayButton: Bool {
        mode == .embedded && onLoad != nil
    }


    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        HStack(spacing: scaled(12)) {
            // 多选模式下显示复选框
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Constants.Fonts.listAddIcon)
                    .foregroundColor(metadata.isDefault ? .gray.opacity(0.3) : (isSelected ? .blue : .gray))
            }
            
            // 图标
            Group {
                if let avatar = avatarImage {
                    Image(uiImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "doc.text.fill")
                        .font(Constants.Fonts.recordIcon)
                        .foregroundColor(.blue)
                }
            }
            .frame(width: scaled(40), height: scaled(40))
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: scaled(8)))
            .onAppear {
                loadAvatarImage()
            }
            
            // 信息
            VStack(alignment: .leading, spacing: scaled(2)) {
                Text(metadata.name)
                    .font(Constants.Fonts.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: scaled(8)) {
                    if metadata.isMaking {
                        if let progress = makeProgress {
                            Text("制作中 \(Int(progress * 100))%")
                                .font(Constants.Fonts.recordMeta)
                                .foregroundColor(.orange)
                                .monospacedDigit()
                        } else {
                            Text("制作中")
                                .font(Constants.Fonts.recordMeta)
                                .foregroundColor(.orange)
                        }
                    } else if metadata.isIncomplete {
                        Text("未完成")
                            .font(Constants.Fonts.recordMeta)
                            .foregroundColor(.orange)
                    } else {
                        Label("\(metadata.validImageCount)/\(metadata.totalImageCount) 张", systemImage: "photo")
                            .labelStyle(.titleOnly)
                            .font(Constants.Fonts.recordMeta)
                            .foregroundColor(.secondary)
                        
                        Label("\(formatDuration(metadata.audioDuration))", systemImage: "waveform")
                            .labelStyle(.titleOnly)
                            .font(Constants.Fonts.recordMeta)
                            .foregroundColor(.secondary)
                            
                        Label(formatStorageSize(metadata.storageSize), systemImage: "internaldrive")
                            .labelStyle(.titleOnly)
                            .font(Constants.Fonts.recordMeta)
                            .foregroundColor(.secondary)

                        if mode == .manage && playCount > 0 {
                            Label("\(playCount)次", systemImage: "play.circle")
                                .labelStyle(.titleOnly)
                                .font(Constants.Fonts.recordMeta)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()

            // 操作按钮（多选模式下隐藏）
            if !isSelectionMode {
                HStack(spacing: scaled(12)) {
                    // 播放按钮
                    if showPlayButton {
                        Button(action: onLoad!) {
                            Image(systemName: "play.circle")
                                .font(Constants.Fonts.recordActionIcon)
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }

                }
            }
        }
        .padding(.horizontal, scaled(0))
        .frame(minWidth: scaled(40), minHeight: scaled(40))
        // 点击行处理：多选模式切换选中；非 embedded 模式打开查看页
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                // 多选模式：切换选中状态
                guard !metadata.isDefault else { return }
                onToggleSelection?()
            } else if mode != .embedded {
                // 非 embedded 模式：单击打开查看页
                if let onView = onView {
                    onView()
                }
            }
        }
        .onLongPressGesture {
            guard let onLongPress = onLongPress else { return }
            onLongPress()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }
    
    /// 加载头像
    private func loadAvatarImage() {
        guard metadata.totalImageCount > 0 else { return }
        let sid = metadata.id
        let avatarIdx = min(max(0, metadata.avatarImageIndex), metadata.totalImageCount - 1)
        loadingId = sid
        DispatchQueue.global(qos: .utility).async {
            // 优先加载预生成的 avatar.jpg
            if let avatar = SessionRecordManager.shared.loadAvatar(sessionId: sid) {
                DispatchQueue.main.async {
                    if loadingId == sid { avatarImage = avatar }
                }
                return
            }
            // 回退：从原图按需生成，并写回 avatar.jpg 供下次直接命中
            let fallback = SessionRecordManager.shared.loadImage(sessionId: sid, index: avatarIdx, maxDimension: Constants.ImageDisplay.listRowAvatarMaxDimension)
                ?? SessionRecordManager.shared.loadImage(sessionId: sid, index: 0, maxDimension: Constants.ImageDisplay.listRowAvatarMaxDimension)
            if let img = fallback {
                SessionRecordManager.shared.saveAvatarIfMissing(sessionId: sid, image: img)
            }
            DispatchQueue.main.async {
                if loadingId == sid { avatarImage = fallback }
            }
        }
    }
    
    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 扩展：格式化时间
extension SessionRecordMetadata {
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
}

// MARK: - 数组安全访问扩展
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 导出文件包装（用于 .sheet(item:) 触发分享面板）
private struct SessionExportableURL: Identifiable {
    let id = UUID()
    let url: URL
    let cleanupRootURL: URL
}

private struct SessionExportLoadingState {
    let title: String
    let completedCount: Int
    let totalCount: Int

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    var progressText: String {
        "\(min(completedCount, max(totalCount, 1))) / \(max(totalCount, 1))"
    }
}

private struct ExportLoadingView: View {
    let state: SessionExportLoadingState

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        CustomZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: scaled(20)) {
                Spacer()

                ProgressView(value: state.fractionCompleted)
                    .progressViewStyle(.linear)
                    .frame(width: scaled(200))

                Text(state.title)
                    .font(Constants.Fonts.body)

                Text(state.progressText)
                    .font(Constants.Fonts.headline)
                    .foregroundColor(.blue)
                    .monospacedDigit()

                Spacer()
            }
        }
    }
}

private struct ExportShareSheet: View {
    let item: SessionExportableURL
    let onFinish: (Bool) -> Void

    var body: some View {
        ShareSheetView(activityItems: [item.url], onComplete: onFinish)
            .onDisappear {
                Self.scheduleExportCleanup(for: item.cleanupRootURL)
            }
    }

    private static func scheduleExportCleanup(for rootURL: URL) {
        let delay: TimeInterval = 600
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            guard FileManager.default.fileExists(atPath: rootURL.path) else {
                return
            }
            try? FileManager.default.removeItem(at: rootURL)
        }
    }
}

// MARK: - SessionRecord扩展
extension SessionRecord {
    var formattedUpdatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: updatedAt)
    }
}
