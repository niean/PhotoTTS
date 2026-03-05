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

    private let exportEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let importDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    /// 记录一次播放（写入对应会话的 history.json）
    func recordPlay(sessionId: String, name: String, playedAt: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("未命名"), !trimmed.contains("测试") else { return }
        let identity = SettingsManager.shared.identityName
        SessionRecordManager.shared.addPlayEvent(sessionId: sessionId, timestamp: playedAt, identity: identity)
        logger.info("记录播放: \(trimmed) @ \(playedAt), 身份: \(identity)")
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

    /// 导出为 JSON 文件，返回可分享的 URL
    func exportToTemporaryFile() -> URL? {
        let list = loadEntries()
        let dateStr = dateStringForExportFileName()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTTS_Plays_\(dateStr).json", isDirectory: false)
        do {
            let data = try exportEncoder.encode(list)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            logger.error("导出播放历史失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 从 URL 导入并合并（按会话名称匹配写入对应 history.json）
    func importFromURL(_ url: URL) -> (success: Bool, message: String) {
        guard url.startAccessingSecurityScopedResource() else {
            return (false, "无法访问该文件")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let imported = try importDecoder.decode([PlayHistoryEntry].self, from: data)

            // 构建名称->会话ID的映射
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "播放历史-导入")
            var nameToId: [String: String] = [:]
            for m in allMetadata.sorted(by: { $0.createdAt < $1.createdAt }) {
                nameToId[m.name] = m.id
            }

            var matchedCount = 0
            var skippedCount = 0
            for entry in imported {
                let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.contains("未命名"), !trimmed.contains("测试") else { continue }
                guard let sessionId = nameToId[entry.name] else {
                    skippedCount += 1
                    continue
                }
                let identity = entry.identity ?? ""
                // 按 playCount 补入对应数量的事件
                let count = max(1, entry.playCount)
                for _ in 0..<count {
                    SessionRecordManager.shared.addPlayEvent(sessionId: sessionId, timestamp: entry.lastPlayedAt, identity: identity)
                }
                matchedCount += count
            }

            let msg: String
            if skippedCount > 0 {
                msg = "导入 \(matchedCount) 条记录（\(skippedCount) 个名称未匹配到会话，已跳过）"
            } else {
                msg = "成功导入 \(matchedCount) 条记录"
            }
            return (true, msg)
        } catch {
            return (false, "导入失败: \(error.localizedDescription)")
        }
    }

    private func dateStringForExportFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
