import Foundation
import os.log

// MARK: - 播放历史条目（单条：name + lastPlayedAt；展示时按名称聚合后 playCount 为次数）
struct PlayHistoryEntry: Codable, Identifiable {
    var id: String { name + lastPlayedAt.timeIntervalSince1970.description }
    let name: String
    let lastPlayedAt: Date
    /// 该名称的累计播放次数
    let playCount: Int

    init(name: String, lastPlayedAt: Date, playCount: Int = 1) {
        self.name = name
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        lastPlayedAt = try c.decode(Date.self, forKey: .lastPlayedAt)
        playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 1
    }
}

// MARK: - 播放历史管理器（单一大 JSON 文件，支持导入导出）
class PlayHistoryManager {
    static let shared = PlayHistoryManager()
    
    private let fileManager = FileManager.default
    private let logger = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "PlayHistoryManager")
    
    private let fileName = "play_history.json"
    
    private var fileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(fileName, isDirectory: false)
    }
    
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private init() {}
    
    /// 记录一次播放
    func recordPlay(name: String, playedAt: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("未命名"), !trimmed.contains("测试") else { return }
        var list = loadFromFile()
        list.append(PlayHistoryEntry(name: trimmed, lastPlayedAt: playedAt, playCount: 1))
        list.sort { $0.lastPlayedAt > $1.lastPlayedAt }
        saveToFile(list)
        logger.info("记录播放: \(trimmed) @ \(playedAt)")
    }

    /// 供展示用：按名称去重、计数，按最近一次播放时间倒序
    func loadEntries() -> [PlayHistoryEntry] {
        let raw = loadFromFile()
        var byName: [String: (count: Int, latest: Date)] = [:]
        for e in raw {
            if let cur = byName[e.name] {
                byName[e.name] = (cur.count + e.playCount, max(cur.latest, e.lastPlayedAt))
            } else {
                byName[e.name] = (e.playCount, e.lastPlayedAt)
            }
        }
        return byName.map { PlayHistoryEntry(name: $0.key, lastPlayedAt: $0.value.latest, playCount: $0.value.count) }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    /// 原始列表（每条播放一条记录，仅过滤无效名称）
    private func loadFromFile() -> [PlayHistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([PlayHistoryEntry].self, from: data) else {
            return []
        }
        let valid = list.filter { entry in
            let t = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !t.contains("未命名") && !t.contains("测试")
        }
        return valid.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }
    
    private func saveToFile(_ list: [PlayHistoryEntry]) {
        do {
            let data = try encoder.encode(list)
            try data.write(to: fileURL)
        } catch {
            logger.error("保存播放历史失败: \(error.localizedDescription)")
        }
    }
    
    /// 导出为 JSON 文件，返回可分享的 URL
    func exportToTemporaryFile() -> URL? {
        let list = loadFromFile()
        let dateStr = dateStringForExportFileName()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("PhotoTTS_Plays_\(dateStr).json", isDirectory: false)
        do {
            let data = try encoder.encode(list)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            logger.error("导出播放历史失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 从 URL 导入并合并（追加所有有效记录，不去重）
    func importFromURL(_ url: URL) -> (success: Bool, message: String) {
        guard url.startAccessingSecurityScopedResource() else {
            return (false, "无法访问该文件")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let imported = try decoder.decode([PlayHistoryEntry].self, from: data)
            let validImported = imported.filter { e in
                let t = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return !t.isEmpty && !t.contains("未命名") && !t.contains("测试")
            }
            var current = loadFromFile()
            current.append(contentsOf: validImported)
            current.sort { $0.lastPlayedAt > $1.lastPlayedAt }
            saveToFile(current)
            let displayCount = byNameCount(current)
            return (true, "成功导入 \(validImported.count) 条播放记录，当前共 \(displayCount) 个名称（\(current.count) 条记录）")
        } catch {
            return (false, "导入失败: \(error.localizedDescription)")
        }
    }

    private func byNameCount(_ list: [PlayHistoryEntry]) -> Int {
        Set(list.map(\.name)).count
    }
    
    private func dateStringForExportFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
