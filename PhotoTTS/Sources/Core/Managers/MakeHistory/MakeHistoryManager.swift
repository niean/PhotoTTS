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

    private let logger = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "MakeHistoryManager")

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
    }

    /// 导出为 JSON 文件，文件名形如 PhotoTTS_Makes_20260212.json
    func exportToTemporaryFile() -> URL? {
        let list = loadEntries()
        let dateStr = dateStringForExportFileName()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTTS_Makes_\(dateStr).json", isDirectory: false)
        do {
            let data = try exportEncoder.encode(list)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            logger.error("导出制作历史失败: \(error.localizedDescription)")
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
            let imported = try importDecoder.decode([MakeHistoryEntry].self, from: data)

            // 构建名称->会话ID的映射
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "制作历史-导入")
            var nameToId: [String: String] = [:]
            for m in allMetadata.sorted(by: { $0.createdAt < $1.createdAt }) {
                nameToId[m.name] = m.id
            }

            var matchedCount = 0
            var skippedCount = 0
            for entry in imported where !entry.name.contains("未命名") && !entry.name.contains("测试") {
                guard let sessionId = nameToId[entry.name] else {
                    skippedCount += 1
                    continue
                }
                let identity = entry.identity ?? ""
                SessionRecordManager.shared.addMakeEvent(sessionId: sessionId, timestamp: entry.savedAt, identity: identity)
                matchedCount += 1
            }

            let msg: String
            if skippedCount > 0 {
                msg = "导入 \(matchedCount) 条记录（\(skippedCount) 条未匹配到会话，已跳过）"
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
