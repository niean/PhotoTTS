import SwiftUI

struct RecordAnalysisSnapshot {
    struct SeriesItem: Identifiable {
        let id: String
        let name: String
        let totalCount: Int
        let readCount: Int

        var unreadCount: Int {
            max(0, totalCount - readCount)
        }

        func totalRatio(maxCount: Int) -> Double {
            guard maxCount > 0 else { return 0 }
            return Double(totalCount) / Double(maxCount)
        }

        var readRatio: Double {
            guard totalCount > 0 else { return 0 }
            return Double(readCount) / Double(totalCount)
        }
    }

    let totalCount: Int
    let readCount: Int
    let unreadCount: Int
    let completedCount: Int
    let makingCount: Int
    let incompleteCount: Int
    let totalStorageSize: Int64
    let seriesItems: [SeriesItem]

    static let empty = RecordAnalysisSnapshot(
        totalCount: 0,
        readCount: 0,
        unreadCount: 0,
        completedCount: 0,
        makingCount: 0,
        incompleteCount: 0,
        totalStorageSize: 0,
        seriesItems: []
    )

    var isEmpty: Bool { totalCount == 0 }

    var summaryText: String {
        "\(totalCount)本 · 已读\(readCount) · 未读\(unreadCount)"
    }

    var readProgress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(readCount) / Double(totalCount)
    }

    var readProgressText: String {
        let percent = Int((readProgress * 100).rounded())
        return "已读 \(readCount) / 未读 \(unreadCount)（\(percent)%）"
    }

    var formattedStorageSize: String {
        let gb: Double = 1024 * 1024 * 1024
        let mb: Double = 1024 * 1024
        let size = Double(totalStorageSize)
        if size >= gb {
            return String(format: "%.1f GB", size / gb)
        }
        return "\(max(0, Int((size / mb).rounded()))) MB"
    }

    static func load() -> RecordAnalysisSnapshot {
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "RecordAnalysisView")
        let metadataList = allMetadata.filter { !$0.isDefault }
        guard !metadataList.isEmpty else { return .empty }

        let statsMap = SessionRecordManager.shared.loadPlayStats(sessionIds: metadataList.map(\.id))
        let readCount = metadataList.reduce(into: 0) { count, metadata in
            if statsMap[metadata.id] != nil {
                count += 1
            }
        }

        let seriesItems = buildSeriesItems(metadataList: metadataList, statsMap: statsMap)
        let completedCount = metadataList.filter { $0.makeStatus == nil || $0.makeStatus == .completed }.count
        let makingCount = metadataList.filter { $0.makeStatus == .making }.count
        let incompleteCount = metadataList.count - completedCount - makingCount
        let totalStorageSize = metadataList.reduce(into: Int64(0)) { result, metadata in
            result += metadata.storageSize
        }

        return RecordAnalysisSnapshot(
            totalCount: metadataList.count,
            readCount: readCount,
            unreadCount: metadataList.count - readCount,
            completedCount: completedCount,
            makingCount: makingCount,
            incompleteCount: incompleteCount,
            totalStorageSize: totalStorageSize,
            seriesItems: seriesItems
        )
    }

    static func buildSeriesItems(
        metadataList: [SessionRecordMetadata],
        statsMap: [String: PlayStatInfo]
    ) -> [SeriesItem] {
        struct Bucket {
            var totalCount: Int = 0
            var readCount: Int = 0
        }

        var buckets: [String: Bucket] = [:]
        for metadata in metadataList {
            let seriesName = normalizedSeriesName(for: metadata)
            var bucket = buckets[seriesName, default: Bucket()]
            bucket.totalCount += 1
            if statsMap[metadata.id] != nil {
                bucket.readCount += 1
            }
            buckets[seriesName] = bucket
        }

        let otherName = "其它"
        var explicitOther = buckets.removeValue(forKey: otherName) ?? Bucket()

        // 系列分布规则：绘本数量 >= 阈值的系列单独展示，< 阈值的归并到"其它"
        let threshold = Constants.GroupDisplay.seriesMinCountForStandalone
        let sortedSeries = buckets
            .map { (name: $0.key, stats: $0.value) }
            .sorted { lhs, rhs in
                if lhs.stats.totalCount != rhs.stats.totalCount {
                    return lhs.stats.totalCount > rhs.stats.totalCount
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }

        var result: [SeriesItem] = []
        for series in sortedSeries {
            if series.stats.totalCount >= threshold {
                result.append(SeriesItem(
                    id: series.name,
                    name: series.name,
                    totalCount: series.stats.totalCount,
                    readCount: series.stats.readCount
                ))
            } else {
                explicitOther.totalCount += series.stats.totalCount
                explicitOther.readCount += series.stats.readCount
            }
        }

        if explicitOther.totalCount > 0 {
            result.append(SeriesItem(
                id: otherName,
                name: otherName,
                totalCount: explicitOther.totalCount,
                readCount: explicitOther.readCount
            ))
        }
        return result
    }

    private static func normalizedSeriesName(for metadata: SessionRecordMetadata) -> String {
        let seriesName = metadata.seriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        if seriesName.isEmpty || seriesName == Constants.GroupDisplay.uncategorizedLabel {
            return "其它"
        }
        return seriesName
    }
}

struct RecordAnalysisView: View {
    private let progressBarHeight: CGFloat = 10
    let snapshot: RecordAnalysisSnapshot

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if snapshot.isEmpty {
                    emptyState
                } else {
                    heroCard
                    seriesSection
                    makeStatusSection
                    storageSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(Constants.Fonts.title2)
                .foregroundStyle(.secondary)
            Text("暂无记录")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)
            Text("拍照制作后，这里会展示你的记录资产概览。")
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Text("\(snapshot.totalCount)")
                .font(Constants.Fonts.analysisHeroNumber)
                .foregroundStyle(.primary)

            readProgressBar

            Text(snapshot.readProgressText)
                .font(Constants.Fonts.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var readProgressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                Capsule()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * snapshot.readProgress)
            }
        }
        .frame(height: progressBarHeight)
        .clipShape(Capsule())
    }

    private var seriesSection: some View {
        let maxCount = snapshot.seriesItems.map(\.totalCount).max() ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("系列分布")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            ForEach(snapshot.seriesItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(item.name)
                            .font(Constants.Fonts.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(item.totalCount)本")
                            .font(Constants.Fonts.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        stackedSeriesBar(item: item, maxCount: maxCount)

                        Text("\(item.readCount)/\(item.unreadCount)")
                            .font(Constants.Fonts.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func stackedSeriesBar(item: RecordAnalysisSnapshot.SeriesItem, maxCount: Int) -> some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width)
            let totalWidth = availableWidth * item.totalRatio(maxCount: maxCount)
            let readWidth = totalWidth * item.readRatio
            let unreadWidth = max(0, totalWidth - readWidth)

            HStack(spacing: 0) {
                if readWidth > 0 {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: readWidth)
                }
                if unreadWidth > 0 {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: unreadWidth)
                }
            }
            .frame(width: totalWidth, height: progressBarHeight)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: progressBarHeight)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Constants.Fonts.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var makeStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("制作状态")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 0) {
                makeStatusItem(title: "已完成", value: "\(snapshot.completedCount)本")
                divider
                makeStatusItem(title: "制作中", value: "\(snapshot.makingCount)本")
                divider
                makeStatusItem(title: "未完成", value: "\(snapshot.incompleteCount)本")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("存储空间")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            Text("总占用：\(snapshot.formattedStorageSize)")
                .font(Constants.Fonts.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(width: 1, height: 40)
    }

    private func makeStatusItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Constants.Fonts.title3)
                .foregroundStyle(.primary)
            Text(title)
                .font(Constants.Fonts.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecordAnalysisViewWithBar: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: RecordAnalysisSnapshot = .empty
    @State private var isLoading = true

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        CustomZStack(alignment: .top) {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RecordAnalysisView(snapshot: snapshot)
                        .padding(.top, Constants.Layout.topNavigationBarPadding)
                }
            }

            TopAndLeftSideNavigationBar(title: "记录分析", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.navAction)
                        .frame(width: scaled(20), height: scaled(20))
                        .foregroundStyle(.primary)
                }
            }, trailing: {
                EmptyView()
            })
        }
        .navigationBarHidden(true)
        .onAppear { loadSnapshot() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.playHistoryDidUpdate)) { _ in
            loadSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.sessionsDidImport)) { _ in
            loadSnapshot()
        }
    }

    private func loadSnapshot() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = RecordAnalysisSnapshot.load()
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.isLoading = false
            }
        }
    }
}
