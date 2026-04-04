import Foundation
import os.log

// MARK: - 周期类型
enum ReportPeriod: String, CaseIterable {
    case weekly
    case monthly

    var days: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        }
    }

    var displayName: String {
        switch self {
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    var rangeDescription: String {
        switch self {
        case .weekly: return "最近7天"
        case .monthly: return "最近30天"
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

// MARK: - 阅读报告统计数据
struct ReadingReportStats {
    let period: ReportPeriod
    let totalDuration: TimeInterval
    let bookCount: Int
    let topBooks: [TopBookItem]
    let continuousDays: Int
    let near30DaysDuration: TimeInterval
    let recentListening: [RecentListeningItem]

    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var formattedNear30DaysDuration: String {
        let hours = Int(near30DaysDuration) / 3600
        let minutes = (Int(near30DaysDuration) % 3600) / 60
        if hours > 0 {
            return "近30天累计 \(hours)小时\(minutes)分"
        } else {
            return "近30天累计 \(minutes)分钟"
        }
    }
}

// MARK: - 阅读报告管理器
class ReadingReportManager {
    static let shared = ReadingReportManager()
    private let logger = os.Logger(subsystem: "com.phototts.app", category: "ReadingReport")

    private init() {}

    func calculateStats(period: ReportPeriod) -> ReadingReportStats {
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -period.days, to: now) ?? now

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
                if event.timestamp >= startDate && event.timestamp <= now {
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

        // 计算连续听读天数
        let continuousDays = calculateContinuousDays(allHistories: allHistories, durationBySessionId: durationBySessionId)

        // 计算近30天累计时长
        let near30DaysDuration = calculateNear30DaysDuration(allHistories: allHistories, durationBySessionId: durationBySessionId)

        // 计算最近收听列表
        let recentListening = calculateRecentListening(allHistories: allHistories, period: period)

        return ReadingReportStats(
            period: period,
            totalDuration: totalDuration,
            bookCount: bookCount,
            topBooks: Array(topBooks),
            continuousDays: continuousDays,
            near30DaysDuration: near30DaysDuration,
            recentListening: recentListening
        )
    }

    private func calculateContinuousDays(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval]
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var playDates: Set<Date> = []
        for item in allHistories {
            for event in item.history.playEvents {
                if durationBySessionId[item.id] != nil {
                    let eventDay = calendar.startOfDay(for: event.timestamp)
                    playDates.insert(eventDay)
                }
            }
        }

        var continuousDays = 0
        var checkDate = today
        while playDates.contains(checkDate) {
            continuousDays += 1
            guard let prevDate = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prevDate
        }

        return continuousDays
    }

    private func calculateNear30DaysDuration(
        allHistories: [(id: String, name: String, history: SessionHistory)],
        durationBySessionId: [String: TimeInterval]
    ) -> TimeInterval {
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        var totalDuration: TimeInterval = 0
        for item in allHistories {
            guard let duration = durationBySessionId[item.id] else { continue }
            for event in item.history.playEvents {
                if event.timestamp >= startDate && event.timestamp <= now {
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
        let startDate = calendar.date(byAdding: .day, value: -period.days, to: now) ?? now

        var items: [RecentListeningItem] = []
        for item in allHistories {
            for event in item.history.playEvents {
                if event.timestamp >= startDate && event.timestamp <= now {
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
}
