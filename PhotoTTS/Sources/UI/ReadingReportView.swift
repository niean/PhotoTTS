import SwiftUI
import Charts

// MARK: - 阅读报告页面
struct ReadingReportView: View {
    let stats: ReadingReportStats
    @Binding var period: ReportPeriod
    @State private var recentListeningPage: Int = 1

    private var pageSize: Int { Constants.Pagination.pageSize }

    private var recentListeningTotalPages: Int {
        let count = stats.recentListening.count
        return count > 0 ? (count + pageSize - 1) / pageSize : 1
    }

    private var pagedRecentListening: [RecentListeningItem] {
        let start = (recentListeningPage - 1) * pageSize
        let end = min(start + pageSize, stats.recentListening.count)
        guard start < stats.recentListening.count else { return [] }
        return Array(stats.recentListening[start..<end])
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    periodPicker
                        .id("reportTop")
                    metricsCards
                    dailyChartSection
                    hourlyChartSection
                    topBooksSection
                    recentListeningSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .onChange(of: recentListeningPage) { _, _ in
                withAnimation {
                    proxy.scrollTo("reportTop", anchor: .top)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: period) { _, _ in recentListeningPage = 1 }
    }

    // MARK: - 周期切换
    private var periodPicker: some View {
        VStack(spacing: 8) {
            Picker("周期", selection: $period) {
                ForEach(ReportPeriod.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Text(period.rangeDescription)
                .font(Constants.Fonts.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 数据指标卡片
    private var metricsCards: some View {
        HStack(spacing: 0) {
            metricItem(title: "播放时长", value: stats.formattedDuration)

            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 40)

            metricItem(title: "听书本数", value: "\(stats.bookCount)本")

            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 40)

            metricItem(title: "听读天数", value: "\(stats.listeningDays)天")
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func metricItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Constants.Fonts.title2)
                .foregroundStyle(.primary)
            Text(title)
                .font(Constants.Fonts.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 天级听书本数直方图
    private var dailyChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("天级本数")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            Chart(stats.dailyBookCounts) { item in
                BarMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("绘本数量", item.bookCount)
                )
                .foregroundStyle(item.bookCount > 0 ? Color.accentColor : Color(.systemGray4))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - 小时时段听书本数直方图
    private var hourlyChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("小时本数")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            Chart(stats.hourlyBookCounts) { item in
                BarMark(
                    x: .value("小时", item.hour),
                    y: .value("绘本数量", item.bookCount)
                )
                .foregroundStyle(item.bookCount > 0 ? Color.accentColor : Color(.systemGray4))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    if let hour = value.as(Int.self) {
                        AxisValueLabel {
                            Text("\(hour)")
                                .font(Constants.Fonts.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                                .font(Constants.Fonts.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Top3 列表
    private var topBooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最爱重听 Top3")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            if stats.topBooks.isEmpty {
                Text("暂无数据")
                    .font(Constants.Fonts.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(stats.topBooks) { book in
                    topBookRow(book: book)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func topBookRow(book: TopBookItem) -> some View {
        HStack(spacing: 12) {
            Text("\(book.rank)")
                .font(Constants.Fonts.navAction)
                .foregroundStyle(.white)
                .frame(width: scaled(24), height: scaled(24))
                .background(rankColor(rank: book.rank))
                .clipShape(Circle())

            Text(book.name)
                .font(Constants.Fonts.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(book.playCount)次")
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func rankColor(rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(.systemGray)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .accentColor
        }
    }

    // MARK: - 最近收听列表
    private var recentListeningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近收听")
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)

            if stats.recentListening.isEmpty {
                Text("暂无数据")
                    .font(Constants.Fonts.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(pagedRecentListening) { item in
                    recentListeningRow(item: item)
                }

                if recentListeningTotalPages > 1 {
                    PaginationControl(
                        currentPage: recentListeningPage,
                        totalPages: recentListeningTotalPages,
                        onPrevious: { if recentListeningPage > 1 { recentListeningPage -= 1 } },
                        onNext: { if recentListeningPage < recentListeningTotalPages { recentListeningPage += 1 } }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func recentListeningRow(item: RecentListeningItem) -> some View {
        HStack {
            Text(item.name)
                .font(Constants.Fonts.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text(item.formattedDate)
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 带顶导的入口页面
struct ReadingReportViewWithBar: View {
    @Environment(\.dismiss) private var dismiss
    @State private var period: ReportPeriod = .weekly
    @State private var stats: ReadingReportStats?

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        CustomZStack(alignment: .top) {
            if let currentStats = stats {
                ReadingReportView(stats: currentStats, period: $period)
                    .padding(.top, Constants.Layout.topNavigationBarPadding)
            } else {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 手势识别
            TopAndLeftSideNavigationBar(title: "阅读报告", onSwipeBack: { dismiss() }, leading: {
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
        .onAppear { loadStats() }
        .onChange(of: period) { _, _ in loadStats() }
    }

    private func loadStats() {
        DispatchQueue.global(qos: .userInitiated).async {
            let calculated = ReadingReportManager.shared.calculateStats(period: period)
            DispatchQueue.main.async {
                stats = calculated
            }
        }
    }
}
