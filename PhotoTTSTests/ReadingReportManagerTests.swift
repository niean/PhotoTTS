import XCTest
@testable import PhotoTTS

final class ReadingReportManagerTests: XCTestCase {

    // MARK: - Helpers

    /// 构造测试用 ReadingReportStats，填充新增必填字段为默认空值
    /// 既存测试原以 `continuousDays` 签名构造；该字段已移除，现以 `listeningDays` 等价语义填充
    private func makeStats(
        period: ReportPeriod = .weekly,
        totalDuration: TimeInterval,
        bookCount: Int = 0,
        topBooks: [TopBookItem] = [],
        listeningDays: Int = 0,
        near30DaysDuration: TimeInterval = 0
    ) -> ReadingReportStats {
        ReadingReportStats(
            period: period,
            totalDuration: totalDuration,
            bookCount: bookCount,
            topBooks: topBooks,
            listeningDays: listeningDays,
            near30DaysDuration: near30DaysDuration,
            recentListening: [],
            dailyBookCounts: [],
            hourlyBookCounts: []
        )
    }

    // MARK: - ReportPeriod Tests

    func testReportPeriodDays() {
        XCTAssertEqual(ReportPeriod.weekly.days, 7)
        XCTAssertEqual(ReportPeriod.monthly.days, 30)
    }

    func testReportPeriodDisplayName() {
        XCTAssertEqual(ReportPeriod.weekly.displayName, "每周")
        XCTAssertEqual(ReportPeriod.monthly.displayName, "每月")
    }

    func testReportPeriodRangeDescription() {
        XCTAssertEqual(ReportPeriod.weekly.rangeDescription, "最近7天")
        XCTAssertEqual(ReportPeriod.monthly.rangeDescription, "最近30天")
    }

    // MARK: - TopBookItem Tests

    func testTopBookItemIdentifiable() {
        let item1 = TopBookItem(rank: 1, name: "小红帽", playCount: 5)
        let item2 = TopBookItem(rank: 2, name: "三只小猪", playCount: 3)
        XCTAssertNotEqual(item1.id, item2.id)
    }

    // MARK: - ReadingReportStats Tests

    func testFormattedDurationMinutesOnly() {
        let stats = makeStats(totalDuration: 1800, bookCount: 5, listeningDays: 3, near30DaysDuration: 3600)
        XCTAssertEqual(stats.formattedDuration, "30m")
    }

    func testFormattedDurationHoursAndMinutes() {
        let stats = makeStats(totalDuration: 5520, bookCount: 5, listeningDays: 3, near30DaysDuration: 3600)
        XCTAssertEqual(stats.formattedDuration, "1h 32m")
    }

    func testFormattedNearPeriodDurationHoursAndMinutes() {
        // weekly 周期对应 "近7天累计 ..."；字段重命名为 formattedNearPeriodDuration
        let stats = makeStats(period: .monthly, totalDuration: 1800, bookCount: 5, listeningDays: 3, near30DaysDuration: 19920)
        XCTAssertEqual(stats.formattedNearPeriodDuration, "近30天累计 5小时32分")
    }

    func testFormattedNearPeriodDurationMinutesOnly() {
        let stats = makeStats(period: .monthly, totalDuration: 1800, bookCount: 5, listeningDays: 3, near30DaysDuration: 1800)
        XCTAssertEqual(stats.formattedNearPeriodDuration, "近30天累计 30分钟")
    }

    // MARK: - ReadingReportManager Integration Tests

    func testCalculateStatsReturnsValidStructure() {
        let stats = ReadingReportManager.shared.calculateStats(period: .weekly)
        XCTAssertGreaterThanOrEqual(stats.totalDuration, 0)
        XCTAssertGreaterThanOrEqual(stats.bookCount, 0)
        XCTAssertGreaterThanOrEqual(stats.listeningDays, 0)
        XCTAssertLessThanOrEqual(stats.topBooks.count, 3)
    }
}
