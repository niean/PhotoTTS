import Foundation
import os.log

// MARK: - 播放历史条目（用于 UI 展示，从会话级 history.json 聚合而来）
struct PlayHistoryEntry: Codable, Identifiable {
    var id: String { name + lastPlayedAt.timeIntervalSince1970.description }
    let name: String
    let lastPlayedAt: Date
    /// 该名称的累计播放次数
    let playCount: Int
    /// 发起者身份名称（旧数据可能为空）
    let identity: String?

    init(name: String, lastPlayedAt: Date, playCount: Int = 1, identity: String? = nil) {
        self.name = name
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
        self.identity = identity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        lastPlayedAt = try c.decode(Date.self, forKey: .lastPlayedAt)
        playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 1
        identity = try c.decodeIfPresent(String.self, forKey: .identity)
    }
}

// MARK: - 播放历史管理器（数据存储在会话目录 history.json 中，随会话导入导出）
class PlayHistoryManager {
    static let shared = PlayHistoryManager()

    private let logger = os.Logger.playHistory

    private init() {}

    /// 记录一次播放（写入对应会话的 history.json）
    func recordPlay(sessionId: String, name: String, playedAt: Date = Date()) {
        let identity = SettingsManager.shared.identityName
        SessionRecordManager.shared.addPlayEvent(sessionId: sessionId, timestamp: playedAt, identity: identity)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
        logger.info("记录播放：\(name) @ \(formatter.string(from: playedAt)), 身份：\(identity)")
        NotificationCenter.default.post(name: Constants.NotificationNames.playHistoryDidUpdate, object: nil)
    }

    /// 供展示用：按名称去重、计数，按最近一次播放时间倒序
    func loadEntries() -> [PlayHistoryEntry] {
        let allHistories = SessionRecordManager.shared.loadAllSessionHistories()
        var byName: [String: (count: Int, latest: Date, identity: String?)] = [:]
        for item in allHistories {
            let name = item.name
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("未命名"), !trimmed.contains("测试") else { continue }
            for event in item.history.playEvents {
                let eventIdentity: String? = event.identity.isEmpty ? nil : event.identity
                if let cur = byName[name] {
                    byName[name] = (cur.count + 1, max(cur.latest, event.timestamp), eventIdentity ?? cur.identity)
                } else {
                    byName[name] = (1, event.timestamp, eventIdentity)
                }
            }
        }
        return byName.map { PlayHistoryEntry(name: $0.key, lastPlayedAt: $0.value.latest, playCount: $0.value.count, identity: $0.value.identity) }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(Constants.maxPlayHistoryRecords)
            .map { $0 }
    }
}
