import SwiftUI

// MARK: - 阅读报告页面
struct ReadingReportView: View {
    let stats: ReadingReportStats
    @Binding var period: ReportPeriod

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                heroSection
                periodPicker
                metricsCards
                topBooksSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 英雄区
    private var heroSection: some View {
        VStack(spacing: 8) {
            Text("\(stats.continuousDays)天")
                .font(.system(size: scaled(48), weight: .bold))
                .foregroundStyle(.primary)
            Text("连续听读")
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.secondary)
            Text(stats.formattedNear30DaysDuration)
                .font(Constants.Fonts.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
