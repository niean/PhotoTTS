import Foundation
import os.log

// MARK: - 周期类型
enum ReportPeriod: String, CaseIterable {
    case weekly
    case monthly
    case halfYear

    var days: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        case .halfYear: return 180
        }
    }

    var displayName: String {
        switch self {
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .halfYear: return "半年"
        }
    }

    var rangeDescription: String {
        switch self {
        case .weekly: return "最近7天"
        case .monthly: return "最近30天"
        case .halfYear: return "最近180天"
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

// MARK: - 小时时段听书本数统计
struct HourlyBookCount: Identifiable, Hashable {
    let id = UUID()
    let hour: Int
    let bookCount: Int
}

// MARK: - 阅读报告统计数据
struct ReadingReportStats {
    let period: ReportPeriod
    let totalDuration: TimeInterval
    let bookCount: Int
    let topBooks: [TopBookItem]
    let listeningDays: Int
    let near30DaysDuration: TimeInterval
    let recentListening: [RecentListeningItem]
    let dailyBookCounts: [DailyBookCount]
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

    var formattedNearPeriodDuration: String {
        let days = period.days
        let hours = Int(near30DaysDuration) / 3600
        let minutes = (Int(near30DaysDuration) % 3600) / 60
        if hours > 0 {
            return "近\(days)天累计 \(hours)小时\(minutes)分"
        } else {
            return "近\(days)天累计 \(minutes)分钟"
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
        let start = calendar.date(byAdding: .day, value: -period.days, to: todayStart) ?? todayStart
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
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
        let range = Self.periodRange(period: period, now: now, calendar: calendar)

        let allHistories = SessionRecordManager.shared.loadAllSessionHistories()
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "阅读报告")

        // 构建 sessionId -> audioDuration 映射
        var durationBySessionId: [String: TimeInterval] = [:]
        for meta in allMetadata {
            if meta.audioDuration > 0 {
                durationBySessionId[meta.id] = meta.audioDuration
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

        // 计算总播放时长
        var totalDuration: TimeInterval = 0
        for event in playEventsInPeriod {
            if let duration = durationBySessionId[event.sessionId] {
                totalDuration += duration
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
        let listeningDays = calculateTotalListeningDays(allHistories: allHistories, durationBySessionId: durationBySessionId, period: period)

        // 计算近N天累计时长（Follow周期选项）
        let near30DaysDuration = calculateNearPeriodDuration(allHistories: allHistories, durationBySessionId: durationBySessionId, period: period)

        // 计算最近收听列表
        let recentListening = calculateRecentListening(allHistories: allHistories, period: period)

        // 计算天级听书本数
        let dailyBookCounts = calculateDailyBookCounts(allHistories: allHistories, period: period)

        // 计算小时时段听书本数
        let hourlyBookCounts = calculateHourlyBookCounts(allHistories: allHistories, period: period)

        return ReadingReportStats(
            period: period,
            totalDuration: totalDuration,
            bookCount: bookCount,
            topBooks: Array(topBooks),
            listeningDays: listeningDays,
            near30DaysDuration: near30DaysDuration,
            recentListening: recentListening,
            dailyBookCounts: dailyBookCounts,
            hourlyBookCounts: hourlyBookCounts
        )
    }

    private func calculateTotalListeningDays(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval],
        period: ReportPeriod
    ) -> Int {
        let now = Date()
        let calendar = Calendar.current
        let range = Self.periodRange(period: period, now: now, calendar: calendar)

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

    private func calculateNearPeriodDuration(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval],
        period: ReportPeriod
    ) -> TimeInterval {
        let now = Date()
        let calendar = Calendar.current
        let range = Self.periodRange(period: period, now: now, calendar: calendar)

        var totalDuration: TimeInterval = 0
        for item in allHistories {
            guard let duration = durationBySessionId[item.id] else { continue }
            for event in item.history.playEvents {
                if Self.contains(event.timestamp, in: range) {
                    totalDuration += duration
                }
            }
        }
        return totalDuration
    }

    private func calculateRecentListening(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        period: ReportPeriod
    ) -> [RecentListeningItem] {
        let now = Date()
        let calendar = Calendar.current
        let range = Self.periodRange(period: period, now: now, calendar: calendar)

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

    private func calculateDailyBookCounts(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        period: ReportPeriod
    ) -> [DailyBookCount] {
        let now = Date()
        let calendar = Calendar.current
        let dayStarts = Self.periodDayStarts(period: period, now: now, calendar: calendar)

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

    private func calculateHourlyBookCounts(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        period: ReportPeriod
    ) -> [HourlyBookCount] {
        let now = Date()
        let calendar = Calendar.current
        let range = Self.periodRange(period: period, now: now, calendar: calendar)

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
