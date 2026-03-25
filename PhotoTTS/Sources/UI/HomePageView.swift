import SwiftUI
import os.log

/// 首页子页面播放用
private struct PlayFromHomeItem: Identifiable, Hashable {
    let id: String
    let queueRecordIds: [String]
}

// MARK: - 首页
struct HomePageView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var bgMakeManager = BackgroundMakeManager.shared

    @State private var sessionToPlayFromHome: PlayFromHomeItem? = nil
    @State private var pagedMetadataList: [SessionRecordMetadata] = []
    @State private var totalCount: Int = 0
    @State private var currentPage: Int = 1
    @State private var isLoading = true
    @State private var searchText: String = ""

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    /// iPhone 2 列, iPad 4 列
    private var columns: [GridItem] {
        let count = UIDevice.current.userInterfaceIdiom == .pad ? Constants.HomeCard.iPadColumns : Constants.HomeCard.iPhoneColumns
        return Array(repeating: GridItem(.flexible(), spacing: scaled(Constants.HomeCard.gridSpacing)), count: count)
    }

    private var totalPages: Int {
        let pageSize = Constants.Pagination.pageSize
        guard totalCount > 0 else { return 1 }
        return (totalCount + pageSize - 1) / pageSize
    }

    private var showPagination: Bool {
        totalCount > Constants.Pagination.pageSize
    }

    var body: some View {
        CustomZStack(alignment: .top) {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("加载中...")
                        .scaleEffect(scaled(1.0))
                    Spacer()
                } else if totalCount == 0 && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                                onTap: { loadAndPlay(metadata.id) }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, scaled(Constants.HomeCard.gridHorizontalPadding))
                                    .padding(.top, scaled(8))

                                    // 分页控件
                                    if showPagination {
                                        paginationControl
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
        .onAppear { loadPage() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.sessionsDidImport)) { _ in
            loadPage()
        }
        .onChange(of: searchText) {
            // 清空时自动刷新回原列表
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentPage = 1
                loadPage()
            }
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Constants.Fonts.searchIcon)
                .foregroundColor(.gray)
            TextField(Constants.UI.searchPlaceholder, text: $searchText)
                .font(Constants.Fonts.searchInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    currentPage = 1
                    loadPage()
                }
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Constants.Fonts.searchIcon)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Constants.SearchBar.innerHorizontalPadding)
        .padding(.vertical, Constants.SearchBar.innerVerticalPadding)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: Constants.SearchBar.cornerRadius))
    }

    private var paginationControl: some View {
        PaginationControl(
            currentPage: currentPage,
            totalPages: totalPages,
            onPrevious: { if currentPage > 1 { currentPage -= 1; loadPage() } },
            onNext: { if currentPage < totalPages { currentPage += 1; loadPage() } }
        )
    }

    // MARK: - Helpers

    private func makeProgress(for metadata: SessionRecordMetadata) -> Float? {
        guard metadata.isMaking,
              let task = bgMakeManager.currentTask,
              task.id == metadata.id,
              !task.isCompleted else { return nil }
        return task.progress
    }

    private func loadAndPlay(_ id: String) {
        guard !appState.isPlayViewActive else {
            os.Logger.audioPlayer.warning("播放互斥: 已有播放中，拒绝首页触发播放 sessionId=\(id)")
            return
        }
        appState.isPlayViewActive = true
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "HomePageView.连播队列")
        let queue = SessionRecordManager.buildSameDateQueue(from: id, in: allMetadata)
        sessionToPlayFromHome = PlayFromHomeItem(id: id, queueRecordIds: queue)
    }

    private func loadPage() {
        isLoading = true
        let page = currentPage
        let pageSize = Constants.Pagination.pageSize
        let keyword = searchText
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SessionRecordManager.shared.getSessionMetadataPage(
                page: page, pageSize: pageSize, searchKeyword: keyword, caller: "首页卡片"
            )
            DispatchQueue.main.async {
                self.pagedMetadataList = result.items
                self.totalCount = result.totalCount
                self.isLoading = false
                if result.items.isEmpty && result.totalCount > 0 && self.currentPage > 1 {
                    self.currentPage -= 1
                    self.loadPage()
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
}

// MARK: - 绘本卡片
private struct SessionRecordCard: View {
    let metadata: SessionRecordMetadata
    var makeProgress: Float? = nil
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

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 封面区域（固定高度 + 居中裁剪）
            ZStack {
                // 封面图
                if let avatar = avatarImage {
                    Image(uiImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: scaled(Constants.HomeCard.coverHeight))
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
            }
            .frame(height: scaled(Constants.HomeCard.coverHeight))
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
        }
        .background(Color(.white))
        .clipShape(RoundedRectangle(cornerRadius: scaled(Constants.HomeCard.cornerRadius)))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMaking else { return }
            onTap()
        }
        .onAppear { loadAvatarImage() }
    }

    private func loadAvatarImage() {
        guard metadata.totalImageCount > 0 else { return }
        let sid = metadata.id
        let avatarIdx = min(max(0, metadata.avatarImageIndex), metadata.totalImageCount - 1)
        loadingId = sid
        let maxDim = Constants.HomeCard.coverAvatarMaxDimension
        DispatchQueue.global(qos: .utility).async {
            // 缩略图：直接 loadImage 按需加载（300pt），比 avatar(96pt) 更清晰
            let image = SessionRecordManager.shared.loadImage(sessionId: sid, index: avatarIdx, maxDimension: maxDim)
                ?? SessionRecordManager.shared.loadImage(sessionId: sid, index: 0, maxDimension: maxDim)
            DispatchQueue.main.async {
                if loadingId == sid { avatarImage = image }
            }
        }
    }
}
