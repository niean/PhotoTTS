import XCTest
@testable import PhotoTTS

final class ReadingReportManagerTests: XCTestCase {

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
        let stats = ReadingReportStats(
            period: .weekly,
            totalDuration: 1800,
            bookCount: 5,
            topBooks: [],
            continuousDays: 3,
            near30DaysDuration: 3600
        )
        XCTAssertEqual(stats.formattedDuration, "30m")
    }

    func testFormattedDurationHoursAndMinutes() {
        let stats = ReadingReportStats(
            period: .weekly,
            totalDuration: 5520,
            bookCount: 5,
            topBooks: [],
            continuousDays: 3,
            near30DaysDuration: 3600
        )
        XCTAssertEqual(stats.formattedDuration, "1h 32m")
    }

    func testFormattedNear30DaysDuration() {
        let stats = ReadingReportStats(
            period: .weekly,
            totalDuration: 1800,
            bookCount: 5,
            topBooks: [],
            continuousDays: 3,
            near30DaysDuration: 19920
        )
        XCTAssertEqual(stats.formattedNear30DaysDuration, "近30天累计 5小时32分")
    }

    func testFormattedNear30DaysDurationMinutesOnly() {
        let stats = ReadingReportStats(
            period: .weekly,
            totalDuration: 1800,
            bookCount: 5,
            topBooks: [],
            continuousDays: 3,
            near30DaysDuration: 1800
        )
        XCTAssertEqual(stats.formattedNear30DaysDuration, "近30天累计 30分钟")
    }

    // MARK: - ReadingReportManager Integration Tests

    func testCalculateStatsReturnsValidStructure() {
        let stats = ReadingReportManager.shared.calculateStats(period: .weekly)
        XCTAssertGreaterThanOrEqual(stats.totalDuration, 0)
        XCTAssertGreaterThanOrEqual(stats.bookCount, 0)
        XCTAssertGreaterThanOrEqual(stats.continuousDays, 0)
        XCTAssertLessThanOrEqual(stats.topBooks.count, 3)
    }
}
