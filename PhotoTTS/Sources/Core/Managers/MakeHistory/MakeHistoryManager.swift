import Foundation
import os.log

// MARK: - 制作历史条目（用于 UI 展示，从会话级 history.json 聚合而来）
struct MakeHistoryEntry: Codable, Identifiable {
    var id: String { name + savedAt.timeIntervalSince1970.description }
    let name: String
    let savedAt: Date
    /// 发起者身份名称（旧数据可能为空）
    let identity: String?

    init(name: String, savedAt: Date, identity: String? = nil) {
        self.name = name
        self.savedAt = savedAt
        self.identity = identity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        identity = try c.decodeIfPresent(String.self, forKey: .identity)
    }
}

// MARK: - 制作历史管理器（数据存储在会话目录 history.json 中，随会话导入导出）
class MakeHistoryManager {
    static let shared = MakeHistoryManager()

    private let logger = os.Logger.makeHistory

    private init() {}

    /// 记录一次保存（写入对应会话的 history.json）
    func recordSave(sessionId: String, name: String, savedAt: Date = Date()) {
        guard !name.contains("未命名"), !name.contains("测试") else { return }
        let identity = SettingsManager.shared.identityName
        SessionRecordManager.shared.addMakeEvent(sessionId: sessionId, timestamp: savedAt, identity: identity)
        logger.info("记录保存: \(name) @ \(savedAt), 身份: \(identity)")
    }

    /// 加载全部制作历史条目（聚合所有会话，按名称去重保留最后一次）
    func loadEntries() -> [MakeHistoryEntry] {
        let allHistories = SessionRecordManager.shared.loadAllSessionHistories()
        var byName: [String: MakeHistoryEntry] = [:]
        for item in allHistories {
            let name = item.name
            guard !name.contains("未命名"), !name.contains("测试") else { continue }
            for event in item.history.makeEvents {
                if let existing = byName[name] {
                    if event.timestamp > existing.savedAt {
                        byName[name] = MakeHistoryEntry(name: name, savedAt: event.timestamp, identity: event.identity.isEmpty ? nil : event.identity)
                    }
                } else {
                    byName[name] = MakeHistoryEntry(name: name, savedAt: event.timestamp, identity: event.identity.isEmpty ? nil : event.identity)
                }
            }
        }
        return Array(byName.values).sorted { $0.savedAt > $1.savedAt }
            .prefix(Constants.maxMakeHistoryRecords)
            .map { $0 }
    }

    // MARK: - 一次性回溯任务

    /// 回溯补齐制作历史：为已完成但缺少 makeEvent 的会话补写制作事件（只执行一次）
    func backfillMakeEventsIfNeeded() {
        let key = "backfill_make_history_v1_done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "制作历史-回溯补齐")
        let identity = SettingsManager.shared.identityName
        var count = 0

        for meta in allMetadata {
            // 跳过未命名/测试会话
            guard !meta.name.contains("未命名"), !meta.name.contains("测试") else { continue }
            // 跳过制作中的会话
            if meta.makeStatus == .making { continue }
            // 跳过已有 makeEvent 的会话
            let history = SessionRecordManager.shared.loadSessionHistory(sessionId: meta.id)
            guard history.makeEvents.isEmpty else { continue }

            SessionRecordManager.shared.addMakeEvent(sessionId: meta.id, timestamp: meta.updatedAt, identity: identity)
            count += 1
        }

        UserDefaults.standard.set(true, forKey: key)
        logger.info("回溯补齐制作历史完成: 补齐 \(count) 条记录")
    }
}
