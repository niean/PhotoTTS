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
        near30DaysDuration: TimeInterval = 0,
        periodDays: Int? = nil,
        dailyDurations: [DailyDuration] = []
    ) -> ReadingReportStats {
        ReadingReportStats(
            period: period,
            periodDays: periodDays ?? period.days,
            totalDuration: totalDuration,
            bookCount: bookCount,
            topBooks: topBooks,
            listeningDays: listeningDays,
            near30DaysDuration: near30DaysDuration,
            recentListening: [],
            dailyBookCounts: [],
            dailyDurations: dailyDurations,
            hourlyBookCounts: []
        )
    }

    private let testCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    /// 上海时区固定日期构造（用于纯入口快照测试）
    private func shanghaiDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 固定快照 now：2026-01-02 12:00 上海时间
    private let pureNow = shanghaiDateStatic(2026, 1, 2, hour: 12)

    private static func shanghaiDateStatic(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 按定义构造注入 histories（仅播放事件）
    private func makeHistories(_ defs: [(id: String, name: String, events: [SessionHistoryEvent])])
        -> [(id: String, name: String, history: SessionHistory)] {
        defs.map { (id: $0.id, name: $0.name, history: SessionHistory(playEvents: $0.events)) }
    }

    private func event(on base: Date, hour: Int) -> SessionHistoryEvent {
        SessionHistoryEvent(timestamp: testCalendar.date(byAdding: .hour, value: hour, to: base)!, identity: "tester")
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

    func testWeeklyPeriodRangeIncludesSevenDaysAgoThroughToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 21, minute: 30))!

        let range = ReadingReportManager.periodRange(period: .weekly, now: now, calendar: calendar)

        XCTAssertEqual(range.start, calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 0, minute: 0))!)
        XCTAssertEqual(range.endExclusive, calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 0, minute: 0))!)
    }

    func testWeeklyDailyDatesIncludeToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 21, minute: 30))!

        let dates = ReadingReportManager.periodDayStarts(period: .weekly, now: now, calendar: calendar)

        XCTAssertEqual(dates.first, calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 0, minute: 0))!)
        XCTAssertEqual(dates.last, calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 0, minute: 0))!)
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

    // MARK: - All Period Tests

    func testReportPeriodAllCase() {
        XCTAssertEqual(ReportPeriod.all.displayName, "全部")
        XCTAssertTrue(ReportPeriod.all.isAll)
        XCTAssertFalse(ReportPeriod.weekly.isAll)
        XCTAssertEqual(ReportPeriod.allCases.last, .all)
    }

    func testAllPeriodRangeStartsAtDistantPast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 21, minute: 30))!

        let range = ReadingReportManager.periodRange(period: .all, now: now, calendar: calendar)

        XCTAssertEqual(range.start, .distantPast)
        XCTAssertEqual(range.endExclusive, calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 0, minute: 0))!)
    }

    func testRangeHintAll() {
        let stats = makeStats(period: .all, totalDuration: 0, periodDays: 42)
        XCTAssertEqual(stats.rangeHint, "全部42天")
    }

    func testRangeHintFixedPeriod() {
        let stats = makeStats(period: .monthly, totalDuration: 0)
        XCTAssertEqual(stats.rangeHint, "最近30天")
    }

    func testFormattedNearPeriodDurationAllHoursAndMinutes() {
        let stats = makeStats(period: .all, totalDuration: 0, near30DaysDuration: 19920, periodDays: 42)
        XCTAssertEqual(stats.formattedNearPeriodDuration, "全部42天累计 5小时32分")
    }

    func testFormattedNearPeriodDurationAllMinutesOnly() {
        let stats = makeStats(period: .all, totalDuration: 0, near30DaysDuration: 1800, periodDays: 42)
        XCTAssertEqual(stats.formattedNearPeriodDuration, "全部42天累计 30分钟")
    }

    func testCalculateDailyDurationsAccumulatesPerEvent() {
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let day1 = calendar.date(byAdding: .day, value: 1, to: day0)!
        let histories: [(id: String, name: String, history: SessionHistory)] = [
            (id: "a", name: "A", history: SessionHistory(playEvents: [
                event(on: day0, hour: 9), event(on: day0, hour: 20), event(on: day1, hour: 8)
            ])),
            (id: "b", name: "B", history: SessionHistory(playEvents: [event(on: day0, hour: 10)]))
        ]

        let result = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["a": 90, "b": 120],
            dayStarts: [day0, day1],
            calendar: calendar
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].date, day0)
        XCTAssertEqual(result[0].duration, 300, accuracy: 0.001) // 90x2 + 120
        XCTAssertEqual(result[1].date, day1)
        XCTAssertEqual(result[1].duration, 90, accuracy: 0.001)
    }

    func testCalculateDailyDurationsZeroFillsMissingDays() {
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let day2 = calendar.date(byAdding: .day, value: 2, to: day0)!
        let histories: [(id: String, name: String, history: SessionHistory)] = [
            (id: "a", name: "A", history: SessionHistory(playEvents: [event(on: day0, hour: 10)]))
        ]

        let result = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["a": 60],
            dayStarts: [day0, calendar.date(byAdding: .day, value: 1, to: day0)!, day2],
            calendar: calendar
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[1].duration, 0)
        XCTAssertEqual(result[2].duration, 0)
    }

    func testCalculateDailyDurationsIgnoresInvalidDurations() {
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let histories: [(id: String, name: String, history: SessionHistory)] = [
            (id: "missing", name: "M", history: SessionHistory(playEvents: [event(on: day0, hour: 9)])),
            (id: "zero", name: "Z", history: SessionHistory(playEvents: [event(on: day0, hour: 10)])),
            (id: "negative", name: "N", history: SessionHistory(playEvents: [event(on: day0, hour: 11)])),
            (id: "nan", name: "X", history: SessionHistory(playEvents: [event(on: day0, hour: 12)])),
            (id: "inf", name: "I", history: SessionHistory(playEvents: [event(on: day0, hour: 13)]))
        ]

        let result = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["zero": 0, "negative": -5, "nan": Double.nan, "inf": Double.infinity],
            dayStarts: [day0],
            calendar: calendar
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].duration, 0, accuracy: 0.001)
    }

    func testCalculateDailyDurationsEmptyInputs() {
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!

        let emptyBuckets = ReadingReportManager.calculateDailyDurations(
            allHistories: [],
            durationBySessionId: ["a": 60],
            dayStarts: [day0],
            calendar: calendar
        )
        XCTAssertEqual(emptyBuckets.count, 1)
        XCTAssertEqual(emptyBuckets[0].duration, 0)

        let emptyDays = ReadingReportManager.calculateDailyDurations(
            allHistories: [],
            durationBySessionId: [:],
            dayStarts: [],
            calendar: calendar
        )
        XCTAssertTrue(emptyDays.isEmpty)
    }

    func testCalculateDailyDurationsStableIdentity() {
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let result = ReadingReportManager.calculateDailyDurations(
            allHistories: [],
            durationBySessionId: [:],
            dayStarts: [day0],
            calendar: calendar
        )
        XCTAssertEqual(result[0].id, day0)
    }

    func testCalculateDailyDurationsFutureEventsOutsideBuckets() {
        // 未来日事件不落入任何日期桶，输出仍为补零结构，不崩溃（spec: 只有未来日事件）
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let day3 = calendar.date(byAdding: .day, value: 3, to: day0)!
        let histories: [(id: String, name: String, history: SessionHistory)] = [
            (id: "a", name: "A", history: SessionHistory(playEvents: [event(on: day3, hour: 9)]))
        ]

        let result = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["a": 60],
            dayStarts: [day0],
            calendar: calendar
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].duration, 0)
    }

    func testCalculateDailyDurationsIgnoresMakeEvents() {
        // 只有制作事件：纯函数仅遍历 playEvents，制作事件不贡献时长（spec 验收项）
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let histories: [(id: String, name: String, history: SessionHistory)] = [
            (id: "a", name: "A", history: SessionHistory(makeEvents: [event(on: day0, hour: 9)]))
        ]

        let result = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["a": 60],
            dayStarts: [day0],
            calendar: calendar
        )

        XCTAssertEqual(result[0].duration, 0)
    }

    // MARK: - calculateStats 纯入口 Tests（注入快照）

    /// 场景1：固定周期桶结构（8/31/181 桶、起止日、升序、两张天图日期相等、periodDays 与文案）
    func testPureStatsBucketStructureForFixedPeriods() {
        let cases: [(period: ReportPeriod, buckets: Int, days: Int, hint: String)] = [
            (period: .weekly, buckets: 8, days: 7, hint: "最近7天"),
            (period: .monthly, buckets: 31, days: 30, hint: "最近30天"),
            (period: .halfYear, buckets: 181, days: 180, hint: "最近180天")
        ]
        for item in cases {
            let stats = ReadingReportManager.calculateStats(
                period: item.period,
                allHistories: [],
                durationBySessionId: [:],
                now: pureNow,
                calendar: testCalendar
            )
            XCTAssertEqual(stats.dailyBookCounts.count, item.buckets, "\(item.period) 桶数")
            XCTAssertEqual(stats.dailyDurations.count, item.buckets, "\(item.period) 时长桶数")
            XCTAssertEqual(stats.periodDays, item.days, "\(item.period) periodDays")
            XCTAssertEqual(stats.rangeHint, item.hint, "\(item.period) 文案")
            // 起止日：start = 今天零点 - days，end = 今天零点
            let todayStart = testCalendar.startOfDay(for: pureNow)
            XCTAssertEqual(
                stats.dailyBookCounts.first?.date,
                testCalendar.date(byAdding: .day, value: -item.days, to: todayStart),
                "\(item.period) 起始日"
            )
            XCTAssertEqual(stats.dailyBookCounts.last?.date, todayStart, "\(item.period) 结束日")
            // 升序
            let dates = stats.dailyBookCounts.map { $0.date }
            XCTAssertEqual(dates, dates.sorted(), "\(item.period) 桶升序")
            // 两张天图逐日日期相等
            XCTAssertEqual(
                stats.dailyBookCounts.map { $0.date },
                stats.dailyDurations.map { $0.date },
                "\(item.period) 两张天图日期一致"
            )
        }
    }

    /// 场景2：边界事件只计 [start, endExclusive)，两个累计指标匹配桶总和（跨年、跨月）
    func testPureStatsBoundaryEventsCountOnlyInRange() {
        let range = ReadingReportManager.periodRange(period: .weekly, now: pureNow, calendar: testCalendar)
        // weekly: 2025-12-26 00:00 ~ 2026-01-03 00:00，跨 2025/2026 年与 12/1 月界
        let histories = makeHistories([
            (id: "s", name: "边界绘本", events: [
                SessionHistoryEvent(timestamp: range.start, identity: "tester"),
                SessionHistoryEvent(timestamp: range.start.addingTimeInterval(-1), identity: "tester"),
                SessionHistoryEvent(timestamp: range.endExclusive.addingTimeInterval(-1), identity: "tester"),
                SessionHistoryEvent(timestamp: range.endExclusive, identity: "tester")
            ])
        ])

        let stats = ReadingReportManager.calculateStats(
            period: .weekly,
            allHistories: histories,
            durationBySessionId: ["s": 60],
            now: pureNow,
            calendar: testCalendar
        )

        // 只计中间两个有效事件
        XCTAssertEqual(stats.totalDuration, 120, accuracy: 0.001)
        XCTAssertEqual(stats.near30DaysDuration, 120, accuracy: 0.001)
        XCTAssertEqual(stats.recentListening.count, 2)
        // 累计指标匹配桶总和
        let durationSum = stats.dailyDurations.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(durationSum, stats.totalDuration, accuracy: 0.001)
        XCTAssertEqual(stats.dailyDurations.filter { $0.duration > 0 }.count, 2)
        XCTAssertEqual(stats.dailyBookCounts.filter { $0.bookCount > 0 }.count, 2)
    }

    /// 场景3：全部周期（.all）无事件/仅制作事件/仅未来播放事件时，两个天图为空且 periodDays=0
    func testPureStatsAllPeriodEmptyInputsProduceEmptyCharts() {
        let tomorrow = testCalendar.date(byAdding: .day, value: 1, to: testCalendar.startOfDay(for: pureNow))!
        let cases: [(label: String, histories: [(id: String, name: String, history: SessionHistory)])] = [
            (label: "无事件", histories: []),
            (label: "仅制作事件", histories: [(id: "m", name: "M", history: SessionHistory(makeEvents: [SessionHistoryEvent(timestamp: pureNow, identity: "tester")]))]),
            (label: "仅未来播放事件", histories: [(id: "f", name: "F", history: SessionHistory(playEvents: [SessionHistoryEvent(timestamp: tomorrow, identity: "tester")]))])
        ]
        for item in cases {
            let stats = ReadingReportManager.calculateStats(
                period: .all,
                allHistories: item.histories,
                durationBySessionId: ["f": 60],
                now: pureNow,
                calendar: testCalendar
            )
            XCTAssertTrue(stats.dailyBookCounts.isEmpty, item.label)
            XCTAssertTrue(stats.dailyDurations.isEmpty, item.label)
            XCTAssertEqual(stats.periodDays, 0, item.label)
        }
    }

    /// 场景3补充：最早播放事件无有效时长时仍从该日开始补零；今天一事件时 periodDays=1
    func testPureStatsAllPeriodZeroFillAndSingleDay() {
        // 最早播放 2025-12-30，无有效时长映射：仍从该日补零到今天
        let earliestDay = shanghaiDate(2025, 12, 30, hour: 9)
        let noDurationStats = ReadingReportManager.calculateStats(
            period: .all,
            allHistories: [(id: "x", name: "X", history: SessionHistory(playEvents: [SessionHistoryEvent(timestamp: earliestDay, identity: "tester")]))],
            durationBySessionId: [:],
            now: pureNow,
            calendar: testCalendar
        )
        XCTAssertEqual(noDurationStats.periodDays, 4) // 12-30 ~ 01-02
        XCTAssertEqual(noDurationStats.dailyDurations.count, 4)
        XCTAssertEqual(noDurationStats.dailyDurations[0].date, testCalendar.startOfDay(for: earliestDay))
        XCTAssertEqual(noDurationStats.dailyDurations[0].duration, 0)
        XCTAssertEqual(noDurationStats.dailyDurations.last?.date, testCalendar.startOfDay(for: pureNow))

        // 今天一事件：periodDays=1
        let todayEvent = shanghaiDate(2026, 1, 2, hour: 8)
        let todayStats = ReadingReportManager.calculateStats(
            period: .all,
            allHistories: [(id: "y", name: "Y", history: SessionHistory(playEvents: [SessionHistoryEvent(timestamp: todayEvent, identity: "tester")]))],
            durationBySessionId: ["y": 30],
            now: pureNow,
            calendar: testCalendar
        )
        XCTAssertEqual(todayStats.periodDays, 1)
        XCTAssertEqual(todayStats.dailyDurations.count, 1)
        XCTAssertEqual(todayStats.dailyDurations[0].duration, 30, accuracy: 0.001)
    }

    /// 场景4：洛杉矶日历夏令时切换日（2026-03-08 为 23 小时、2026-11-01 为 25 小时），事件归入正确自然日
    func testPureStatsDaylightSavingTransitionBuckets() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // 春季：now = 2026-03-09 12:00（切换日次日），weekly 桶 03-02 ~ 03-09，末相邻桶（03-08 -> 03-09）跨度 23 小时
        let springNow = la.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let springStats = ReadingReportManager.calculateStats(
            period: .weekly, allHistories: [], durationBySessionId: [:], now: springNow, calendar: la
        )
        let springDates = springStats.dailyDurations.map { $0.date }
        XCTAssertEqual(springDates.count, 8)
        XCTAssertEqual(springDates[7].timeIntervalSince(springDates[6]), 23 * 3600, accuracy: 0.001)

        // 秋季：now = 2026-11-02 12:00（切换日次日），weekly 桶 10-26 ~ 11-02，末相邻桶（11-01 -> 11-02）跨度 25 小时
        let fallNow = la.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let fallStats = ReadingReportManager.calculateStats(
            period: .weekly, allHistories: [], durationBySessionId: [:], now: fallNow, calendar: la
        )
        let fallDates = fallStats.dailyDurations.map { $0.date }
        XCTAssertEqual(fallDates.count, 8)
        XCTAssertEqual(fallDates[7].timeIntervalSince(fallDates[6]), 25 * 3600, accuracy: 0.001)

        // 事件归入正确自然日：03-08 当地正午事件归 03-08 桶（切换日 23 小时日的自然日）
        let event = SessionHistoryEvent(
            timestamp: la.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!,
            identity: "tester"
        )
        let eventStats = ReadingReportManager.calculateStats(
            period: .weekly,
            allHistories: [(id: "d", name: "D", history: SessionHistory(playEvents: [event]))],
            durationBySessionId: ["d": 60],
            now: springNow,
            calendar: la
        )
        let eventDayStart = la.startOfDay(for: event.timestamp)
        let durationsByDate = Dictionary(uniqueKeysWithValues: eventStats.dailyDurations.map { ($0.date, $0.duration) })
        XCTAssertEqual(durationsByDate[eventDayStart] ?? -1, 60, accuracy: 0.001)
        let countsByDate = Dictionary(uniqueKeysWithValues: eventStats.dailyBookCounts.map { ($0.date, $0.bookCount) })
        XCTAssertEqual(countsByDate[eventDayStart] ?? -1, 1)
    }

    /// 场景5：同名 A/B 不同 identity 与 sessionId，天图/累计/本数/Top3/最近收听口径
    func testPureStatsSessionDedupAndNameAggregation() {
        let day0 = shanghaiDate(2026, 1, 1, hour: 9)
        let day0Second = shanghaiDate(2026, 1, 1, hour: 15)
        let day1 = shanghaiDate(2026, 1, 2, hour: 10)
        let histories = makeHistories([
            (id: "a1", name: "A", events: [
                SessionHistoryEvent(timestamp: day0, identity: "甲"),
                SessionHistoryEvent(timestamp: day0Second, identity: "甲")
            ]),
            (id: "a2", name: "A", events: [SessionHistoryEvent(timestamp: day1, identity: "乙")]),
            (id: "b1", name: "B", events: [SessionHistoryEvent(timestamp: shanghaiDate(2026, 1, 1, hour: 11), identity: "甲")])
        ])

        let stats = ReadingReportManager.calculateStats(
            period: .weekly,
            allHistories: histories,
            durationBySessionId: ["a1": 90, "a2": 90, "b1": 120],
            now: pureNow,
            calendar: testCalendar
        )

        // 时长：day0 = 90x2 + 120 = 300，day1 = 90；累计 390，近 N 天累计同为 390
        let durationsByDate = Dictionary(uniqueKeysWithValues: stats.dailyDurations.map { ($0.date, $0.duration) })
        XCTAssertEqual(durationsByDate[testCalendar.startOfDay(for: day0)] ?? -1, 300, accuracy: 0.001)
        XCTAssertEqual(durationsByDate[testCalendar.startOfDay(for: day1)] ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(stats.totalDuration, 390, accuracy: 0.001)
        XCTAssertEqual(stats.near30DaysDuration, 390, accuracy: 0.001)
        // 天级本数按 sessionId 去重：day0 = {a1, b1} = 2，day1 = {a2} = 1
        let countsByDate = Dictionary(uniqueKeysWithValues: stats.dailyBookCounts.map { ($0.date, $0.bookCount) })
        XCTAssertEqual(countsByDate[testCalendar.startOfDay(for: day0)] ?? -1, 2)
        XCTAssertEqual(countsByDate[testCalendar.startOfDay(for: day1)] ?? -1, 1)
        // 总本数按名称去重，Top3 按名称计数
        XCTAssertEqual(stats.bookCount, 2)
        XCTAssertEqual(stats.topBooks.count, 2)
        XCTAssertEqual(stats.topBooks.first?.name, "A")
        XCTAssertEqual(stats.topBooks.first?.playCount, 3)
        // 最近收听原口径：4 条事件按时间倒序
        XCTAssertEqual(stats.recentListening.count, 4)
        XCTAssertEqual(stats.recentListening.first?.sessionId, "a2")
        XCTAssertEqual(stats.recentListening.first?.timestamp, day1)
    }

    /// 场景6：注入映射含缺失/0/负/NaN/正负无穷及正常 30 秒，非法项不贡献、正常项保留
    func testPureStatsMixedValidityDurationMap() {
        let day0 = shanghaiDate(2026, 1, 1)
        func evt(_ hour: Int) -> SessionHistoryEvent {
            SessionHistoryEvent(timestamp: shanghaiDate(2026, 1, 1, hour: hour), identity: "tester")
        }
        let histories = makeHistories([
            (id: "missing", name: "M", events: [evt(1)]),
            (id: "zero", name: "Z", events: [evt(2)]),
            (id: "negative", name: "N", events: [evt(3)]),
            (id: "nan", name: "X", events: [evt(4)]),
            (id: "posinf", name: "P", events: [evt(5)]),
            (id: "neginf", name: "Q", events: [evt(6)]),
            (id: "ok", name: "O", events: [evt(7), evt(8)])
        ])

        let stats = ReadingReportManager.calculateStats(
            period: .weekly,
            allHistories: histories,
            durationBySessionId: [
                "zero": 0,
                "negative": -5,
                "nan": Double.nan,
                "posinf": Double.infinity,
                "neginf": -Double.infinity,
                "ok": 30
            ],
            now: pureNow,
            calendar: testCalendar
        )

        // 非法项不贡献，正常项 30 秒 x 2 保留
        XCTAssertEqual(stats.totalDuration, 60, accuracy: 0.001)
        XCTAssertEqual(stats.near30DaysDuration, 60, accuracy: 0.001)
        let durationsByDate = Dictionary(uniqueKeysWithValues: stats.dailyDurations.map { ($0.date, $0.duration) })
        XCTAssertEqual(durationsByDate[testCalendar.startOfDay(for: day0)] ?? -1, 60, accuracy: 0.001)
        // 本数不受时长映射影响：7 个会话各有播放且名称互异
        XCTAssertEqual(stats.bookCount, 7)
        let countsByDate = Dictionary(uniqueKeysWithValues: stats.dailyBookCounts.map { ($0.date, $0.bookCount) })
        XCTAssertEqual(countsByDate[testCalendar.startOfDay(for: day0)] ?? -1, 7)
    }

    /// 溢出场景：totalDuration 两个最大有限 Double 相加，结果仍有限且溢出贡献未加入
    func testPureStatsTotalDurationOverflowSkipsContribution() {
        let histories = makeHistories([
            (id: "big1", name: "B1", events: [SessionHistoryEvent(timestamp: shanghaiDate(2026, 1, 1, hour: 9), identity: "tester")]),
            (id: "big2", name: "B2", events: [SessionHistoryEvent(timestamp: shanghaiDate(2026, 1, 1, hour: 10), identity: "tester")])
        ])
        let maxFinite = Double.greatestFiniteMagnitude
        let stats = ReadingReportManager.calculateStats(
            period: .weekly,
            allHistories: histories,
            durationBySessionId: ["big1": maxFinite, "big2": maxFinite],
            now: pureNow,
            calendar: testCalendar
        )
        XCTAssertTrue(stats.totalDuration.isFinite)
        XCTAssertEqual(stats.totalDuration, maxFinite, accuracy: 0.001)
    }

    /// 溢出场景：near30DaysDuration 两个最大有限 Double 相加，结果仍有限且溢出贡献未加入
    func testPureStatsNearPeriodDurationOverflowSkipsContribution() {
        let histories = makeHistories([
            (id: "big1", name: "B1", events: [SessionHistoryEvent(timestamp: shanghaiDate(2026, 1, 1, hour: 9), identity: "tester")]),
            (id: "big2", name: "B2", events: [SessionHistoryEvent(timestamp: shanghaiDate(2026, 1, 1, hour: 10), identity: "tester")])
        ])
        let maxFinite = Double.greatestFiniteMagnitude
        let stats = ReadingReportManager.calculateStats(
            period: .weekly,
            allHistories: histories,
            durationBySessionId: ["big1": maxFinite, "big2": maxFinite],
            now: pureNow,
            calendar: testCalendar
        )
        XCTAssertTrue(stats.near30DaysDuration.isFinite)
        XCTAssertEqual(stats.near30DaysDuration, maxFinite, accuracy: 0.001)
    }

    // MARK: - 天级时长轴标签 Tests

    func testFormatAxisMinutes() {
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(0), "0")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(0.5), "0.5")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(23), "23")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(60), "60")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(90), "90")
    }

    func testFormatAxisMinutesRoundingBoundaries() {
        // 0.1 分钟档四舍五入
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(0.04), "0")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(0.55), "0.6")
        // 59.99 先按 0.1 分钟档舍入到 60.0，整分钟去尾零
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(59.99), "60")
        // 舍入后仍带小数时保留 1 位小数
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(59.94), "59.9")
    }

    func testFormatAxisMinutesLargeFiniteValue() {
        // 大数值有限分钟：不得 Int 强转有限 Double，保持分钟格式且不崩溃
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(1e9), "1000000000")
    }

    func testFormatAxisMinutesNonFiniteAndNegative() {
        // 防御非有限输入，不传给 Charts
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(Double.nan), "0")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(Double.infinity), "0")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(-Double.infinity), "0")
        XCTAssertEqual(ReadingReportView.formatAxisMinutes(-5), "0")
    }

    func testDailyDurationIdStableAcrossRecalculation() {
        // 同日期重新计算两次 id 相等（Hashable 语义）
        let calendar = testCalendar
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let dayStarts = [day0]
        let histories: [(id: String, name: String, history: SessionHistory)] = [
            (id: "a", name: "A", history: SessionHistory(playEvents: [event(on: day0, hour: 9)]))
        ]

        let first = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["a": 90],
            dayStarts: dayStarts,
            calendar: calendar
        )
        let second = ReadingReportManager.calculateDailyDurations(
            allHistories: histories,
            durationBySessionId: ["a": 90],
            dayStarts: dayStarts,
            calendar: calendar
        )

        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertEqual(first[0].id, day0)
    }

    // MARK: - ReadingReportManager Integration Tests

    func testCalculateStatsReturnsValidStructure() {
        let stats = ReadingReportManager.shared.calculateStats(period: .weekly)
        XCTAssertGreaterThanOrEqual(stats.totalDuration, 0)
        XCTAssertGreaterThanOrEqual(stats.bookCount, 0)
        XCTAssertGreaterThanOrEqual(stats.listeningDays, 0)
        XCTAssertLessThanOrEqual(stats.topBooks.count, 3)
    }

    func testCalculateStatsAllPeriodReturnsValidStructure() {
        let stats = ReadingReportManager.shared.calculateStats(period: .all)
        XCTAssertGreaterThanOrEqual(stats.periodDays, 0)
        XCTAssertGreaterThanOrEqual(stats.totalDuration, 0)
        XCTAssertLessThanOrEqual(stats.topBooks.count, 3)
    }
}
