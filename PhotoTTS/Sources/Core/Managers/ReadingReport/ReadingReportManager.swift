import Foundation
import os.log

// MARK: - 周期类型
enum ReportPeriod: String, CaseIterable {
    case weekly
    case monthly
    case halfYear
    case all

    // all 为动态天数（第一个播放记录至今），不使用该固定值，返回 0 仅为编译完整
    var days: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        case .halfYear: return 180
        case .all: return 0
        }
    }

    var isAll: Bool { self == .all }

    var displayName: String {
        switch self {
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .halfYear: return "半年"
        case .all: return "全部"
        }
    }

    var rangeDescription: String {
        switch self {
        case .weekly: return "最近7天"
        case .monthly: return "最近30天"
        case .halfYear: return "最近180天"
        case .all: return "" // all 为动态文案，由 ReadingReportStats.rangeHint 生成
        }
    }
}

// MARK: - Top 绘本项
struct TopBookItem: Identifiable, Hashable {
    let id = UUID()
    let rank: Int
    let name: String
    let playCount: Int
}

// MARK: - 最近收听项
struct RecentListeningItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let timestamp: Date
    let sessionId: String

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - 天级听书本数统计
struct DailyBookCount: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let bookCount: Int
}

// MARK: - 天级时长统计
struct DailyDuration: Identifiable, Hashable {
    let date: Date
    let duration: TimeInterval
    var id: Date { date }
}

// MARK: - 小时时段听书本数统计
struct HourlyBookCount: Identifiable, Hashable {
    let id = UUID()
    let hour: Int
    let bookCount: Int
}

// MARK: - 阅读报告统计数据
struct ReadingReportStats {
    let period: ReportPeriod
    let periodDays: Int
    let totalDuration: TimeInterval
    let bookCount: Int
    let topBooks: [TopBookItem]
    let listeningDays: Int
    let near30DaysDuration: TimeInterval
    let recentListening: [RecentListeningItem]
    let dailyBookCounts: [DailyBookCount]
    let dailyDurations: [DailyDuration]
    let hourlyBookCounts: [HourlyBookCount]

    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var rangeHint: String {
        period.isAll ? "全部\(periodDays)天" : period.rangeDescription
    }

    var formattedNearPeriodDuration: String {
        let label = period.isAll ? "全部\(periodDays)天" : "近\(periodDays)天"
        let hours = Int(near30DaysDuration) / 3600
        let minutes = (Int(near30DaysDuration) % 3600) / 60
        if hours > 0 {
            return "\(label)累计 \(hours)小时\(minutes)分"
        } else {
            return "\(label)累计 \(minutes)分钟"
        }
    }
}

// MARK: - 阅读报告管理器
class ReadingReportManager {
    static let shared = ReadingReportManager()
    private let logger = os.Logger.readingReport

    private init() {}

    struct PeriodRange {
        let start: Date
        let endExclusive: Date
    }

    static func periodRange(period: ReportPeriod, now: Date = Date(), calendar: Calendar = .current) -> PeriodRange {
        let todayStart = calendar.startOfDay(for: now)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        if period.isAll {
            return PeriodRange(start: .distantPast, endExclusive: endExclusive)
        }
        let start = calendar.date(byAdding: .day, value: -period.days, to: todayStart) ?? todayStart
        return PeriodRange(start: start, endExclusive: endExclusive)
    }

    static func periodDayStarts(period: ReportPeriod, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let range = periodRange(period: period, now: now, calendar: calendar)
        return (0...period.days).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: range.start)
        }
    }

    private static func contains(_ timestamp: Date, in range: PeriodRange) -> Bool {
        timestamp >= range.start && timestamp < range.endExclusive
    }

    func calculateStats(period: ReportPeriod) -> ReadingReportStats {
        let now = Date()
        let calendar = Calendar.current

        let allHistories = SessionRecordManager.shared.loadAllSessionHistories()
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "阅读报告")

        // 构建 sessionId -> audioDuration 映射（非正数或非有限值不参与统计）
        var durationBySessionId: [String: TimeInterval] = [:]
        for meta in allMetadata {
            if meta.audioDuration > 0 && meta.audioDuration.isFinite {
                durationBySessionId[meta.id] = meta.audioDuration
            }
        }

        return Self.calculateStats(
            period: period,
            allHistories: allHistories,
            durationBySessionId: durationBySessionId,
            now: now,
            calendar: calendar
        )
    }

    /// 纯函数统计入口：注入 histories/duration 映射/now/calendar 快照，不依赖磁盘单例
    static func calculateStats(
        period: ReportPeriod,
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval],
        now: Date,
        calendar: Calendar
    ) -> ReadingReportStats {
        let range = Self.periodRange(period: period, now: now, calendar: calendar)

        // 校验注入映射：非正数或非有限值不参与统计
        var validDurationBySessionId: [String: TimeInterval] = [:]
        for (id, duration) in durationBySessionId where duration > 0 && duration.isFinite {
            validDurationBySessionId[id] = duration
        }

        // 全部时段：扫描最早播放日期，计算动态天数（第一个播放记录至今，首记录为今天则 N=1，无记录 N=0）
        var periodDays = period.days
        var allPeriodEarliestDayStart: Date? = nil
        if period.isAll {
            var earliest: Date? = nil
            for item in allHistories {
                for event in item.history.playEvents {
                    // 明日及以后的事件不参与起点扫描（spec: 避免未来事件导致负范围崩溃）
                    guard Self.contains(event.timestamp, in: range) else { continue }
                    if earliest == nil || event.timestamp < earliest! {
                        earliest = event.timestamp
                    }
                }
            }
            if let earliest {
                let dayStart = calendar.startOfDay(for: earliest)
                allPeriodEarliestDayStart = dayStart
                let diff = calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: now)).day ?? 0
                periodDays = diff + 1
            } else {
                periodDays = 0
            }
        }

        // 筛选周期内的播放事件
        var playEventsInPeriod: [(sessionId: String, name: String, timestamp: Date)] = []
        for item in allHistories {
            for event in item.history.playEvents {
                if Self.contains(event.timestamp, in: range) {
                    playEventsInPeriod.append((sessionId: item.id, name: item.name, timestamp: event.timestamp))
                }
            }
        }

        // 计算总播放时长（累加前检查溢出，失败跳过该贡献）
        var totalDuration: TimeInterval = 0
        for event in playEventsInPeriod {
            guard let duration = validDurationBySessionId[event.sessionId] else { continue }
            let candidate = totalDuration + duration
            if candidate.isFinite {
                totalDuration = candidate
            } else {
                os.Logger.readingReport.error("[TOTAL_DURATION_OVERFLOW] 总时长累加溢出，跳过贡献 sessionId=***\(String(event.sessionId.suffix(4)), privacy: .public)")
            }
        }

        // 计算听书本数（按名称去重）
        let uniqueBooks = Set(playEventsInPeriod.map { $0.name })
        let bookCount = uniqueBooks.count

        // 计算 Top3 绘本（按播放次数降序）
        var playCountByName: [String: Int] = [:]
        for event in playEventsInPeriod {
            playCountByName[event.name, default: 0] += 1
        }
        let sortedBooks = playCountByName.sorted { $0.value > $1.value }
        let topBooks = sortedBooks.prefix(3).enumerated().map { index, pair in
            TopBookItem(rank: index + 1, name: pair.key, playCount: pair.value)
        }

        // 计算听读天数（按周期过滤）
        let listeningDays = Self.calculateTotalListeningDays(allHistories: allHistories, durationBySessionId: validDurationBySessionId, range: range, calendar: calendar)

        // 计算近N天累计时长（Follow周期选项，累加前检查溢出）
        let near30DaysDuration = Self.calculateNearPeriodDuration(allHistories: allHistories, durationBySessionId: validDurationBySessionId, range: range)

        // 计算最近收听列表
        let recentListening = Self.calculateRecentListening(allHistories: allHistories, range: range)

        // 共享日期桶（天级本数/天级时长共用同一 now 快照）
        let dayStarts: [Date]
        if period.isAll {
            if let start = allPeriodEarliestDayStart {
                let todayStart = calendar.startOfDay(for: now)
                let dayCount = calendar.dateComponents([.day], from: start, to: todayStart).day ?? 0
                if dayCount >= 0 {
                    dayStarts = (0...dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                } else {
                    dayStarts = [] // 防御：起点晚于今天时不崩溃
                }
            } else {
                dayStarts = []
            }
        } else {
            dayStarts = Self.periodDayStarts(period: period, now: now, calendar: calendar)
        }

        // 计算天级听书本数
        let dailyBookCounts = Self.calculateDailyBookCounts(allHistories: allHistories, dayStarts: dayStarts, calendar: calendar)

        // 计算天级时长
        let dailyDurations = Self.calculateDailyDurations(allHistories: allHistories, durationBySessionId: validDurationBySessionId, dayStarts: dayStarts, calendar: calendar)

        // 计算小时时段听书本数
        let hourlyBookCounts = Self.calculateHourlyBookCounts(allHistories: allHistories, range: range, calendar: calendar)

        return ReadingReportStats(
            period: period,
            periodDays: periodDays,
            totalDuration: totalDuration,
            bookCount: bookCount,
            topBooks: Array(topBooks),
            listeningDays: listeningDays,
            near30DaysDuration: near30DaysDuration,
            recentListening: recentListening,
            dailyBookCounts: dailyBookCounts,
            dailyDurations: dailyDurations,
            hourlyBookCounts: hourlyBookCounts
        )
    }

    private static func calculateTotalListeningDays(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval],
        range: PeriodRange,
        calendar: Calendar
    ) -> Int {
        var playDates: Set<Date> = []
        for item in allHistories {
            for event in item.history.playEvents {
                if durationBySessionId[item.id] != nil && Self.contains(event.timestamp, in: range) {
                    let eventDay = calendar.startOfDay(for: event.timestamp)
                    playDates.insert(eventDay)
                }
            }
        }

        return playDates.count
    }

    private static func calculateNearPeriodDuration(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval],
        range: PeriodRange
    ) -> TimeInterval {
        var totalDuration: TimeInterval = 0
        for item in allHistories {
            guard let duration = durationBySessionId[item.id] else { continue }
            for event in item.history.playEvents {
                if Self.contains(event.timestamp, in: range) {
                    let candidate = totalDuration + duration
                    if candidate.isFinite {
                        totalDuration = candidate
                    } else {
                        // 累加溢出，跳过该次贡献
                        os.Logger.readingReport.error("[NEAR_PERIOD_DURATION_OVERFLOW] 近N天时长累加溢出，跳过贡献 sessionId=***\(String(item.id.suffix(4)), privacy: .public)")
                    }
                }
            }
        }
        return totalDuration
    }

    private static func calculateRecentListening(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        range: PeriodRange
    ) -> [RecentListeningItem] {
        var items: [RecentListeningItem] = []
        for item in allHistories {
            for event in item.history.playEvents {
                if Self.contains(event.timestamp, in: range) {
                    items.append(RecentListeningItem(
                        name: item.name,
                        timestamp: event.timestamp,
                        sessionId: item.id
                    ))
                }
            }
        }

        // 按时间倒序排序
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private static func calculateDailyBookCounts(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        dayStarts: [Date],
        calendar: Calendar
    ) -> [DailyBookCount] {
        var result: [DailyBookCount] = []

        for dayStart in dayStarts {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            var sessionIdsOnDay: Set<String> = []
            for item in allHistories {
                for event in item.history.playEvents {
                    if event.timestamp >= dayStart && event.timestamp < dayEnd {
                        sessionIdsOnDay.insert(item.id)
                    }
                }
            }

            result.append(DailyBookCount(date: dayStart, bookCount: sessionIdsOnDay.count))
        }

        return result
    }

    /// 天级时长统计：单次播放事件贡献所属记录当前 audioDuration（估算法），按事件次数累加、不去重
    static func calculateDailyDurations(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval],
        dayStarts: [Date],
        calendar: Calendar
    ) -> [DailyDuration] {
        guard !dayStarts.isEmpty else { return [] }

        let allowedDays = Set(dayStarts)
        var durationByDay: [Date: TimeInterval] = [:]
        for item in allHistories {
            guard let duration = durationBySessionId[item.id], duration > 0, duration.isFinite else { continue }
            for event in item.history.playEvents {
                let dayStart = calendar.startOfDay(for: event.timestamp)
                guard allowedDays.contains(dayStart) else { continue }
                let updated = (durationByDay[dayStart] ?? 0) + duration
                if updated.isFinite {
                    durationByDay[dayStart] = updated
                } else {
                    // 累加溢出，跳过该次贡献
                    os.Logger.readingReport.error("[DURATION_SUM_OVERFLOW] 天级时长累加溢出，跳过贡献 sessionId=***\(String(item.id.suffix(4)), privacy: .public)")
                }
            }
        }

        return dayStarts.map { start in
            DailyDuration(date: start, duration: durationByDay[start] ?? 0)
        }
    }

    private static func calculateHourlyBookCounts(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        range: PeriodRange,
        calendar: Calendar
    ) -> [HourlyBookCount] {
        // 收集周期内所有播放事件，按小时聚合
        var sessionsByHour: [Int: Set<String>] = [:]

        for hour in 0..<24 {
            sessionsByHour[hour] = []
        }

        for item in allHistories {
            for event in item.history.playEvents {
                if Self.contains(event.timestamp, in: range) {
                    let hour = calendar.component(.hour, from: event.timestamp)
                    sessionsByHour[hour, default: []].insert(item.id)
                }
            }
        }

        // 构建结果数组，确保 0-23 小时都有数据
        var result: [HourlyBookCount] = []
        for hour in 0..<24 {
            let bookCount = sessionsByHour[hour]?.count ?? 0
            result.append(HourlyBookCount(hour: hour, bookCount: bookCount))
        }

        return result
    }
}
