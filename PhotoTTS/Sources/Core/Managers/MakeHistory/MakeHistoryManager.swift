import Foundation
import os.log

// MARK: - 制作历史条目（按名称去重，保留最后一次保存信息）
struct MakeHistoryEntry: Codable, Identifiable {
    var id: String { name + savedAt.timeIntervalSince1970.description }
    let name: String
    let savedAt: Date
}

// MARK: - 制作历史管理器（单一大 JSON 文件，支持导入导出，规则与播放历史对齐）
class MakeHistoryManager {
    static let shared = MakeHistoryManager()
    
    private let fileManager = FileManager.default
    private let logger = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "MakeHistoryManager")
    
    private let fileName = "make_history.json"
    
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
    
    /// 记录一次保存
    func recordSave(name: String, savedAt: Date = Date()) {
        guard !name.contains("未命名"), !name.contains("测试") else { return }
        var list = loadFromFile()
        list.removeAll { $0.name == name }
        list.append(MakeHistoryEntry(name: name, savedAt: savedAt))
        list.sort { $0.savedAt > $1.savedAt }
        saveToFile(list)
        logger.info("记录保存: \(name) @ \(savedAt)")
    }
    
    /// 加载全部条目
    func loadEntries() -> [MakeHistoryEntry] {
        loadFromFile()
    }
    
    private func loadFromFile() -> [MakeHistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([MakeHistoryEntry].self, from: data) else {
            return []
        }
        let valid = list.filter { !$0.name.contains("未命名") && !$0.name.contains("测试") }
        if valid.count < list.count {
            saveToFile(valid.sorted { $0.savedAt > $1.savedAt })
        }
        return valid.sorted { $0.savedAt > $1.savedAt }
    }
    
    private func saveToFile(_ list: [MakeHistoryEntry]) {
        do {
            let data = try encoder.encode(list)
            try data.write(to: fileURL)
        } catch {
            logger.error("保存制作历史失败: \(error.localizedDescription)")
        }
    }
    
    /// 导出为 JSON 文件，文件名形如 PhotoTTS_Makes_20260212.json
    func exportToTemporaryFile() -> URL? {
        let list = loadFromFile()
        let dateStr = dateStringForExportFileName()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("PhotoTTS_Makes_\(dateStr).json", isDirectory: false)
        do {
            let data = try encoder.encode(list)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            logger.error("导出制作历史失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 从 URL 导入并合并（同名称保留较新的时间）
    func importFromURL(_ url: URL) -> (success: Bool, message: String) {
        guard url.startAccessingSecurityScopedResource() else {
            return (false, "无法访问该文件")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let imported = try decoder.decode([MakeHistoryEntry].self, from: data)
            let current = loadFromFile()
            var byName: [String: MakeHistoryEntry] = [:]
            for e in current { byName[e.name] = e }
            for e in imported where !e.name.contains("未命名") && !e.name.contains("测试") {
                if let existing = byName[e.name] {
                    if e.savedAt > existing.savedAt { byName[e.name] = e }
                } else {
                    byName[e.name] = e
                }
            }
            let merged = Array(byName.values).sorted { $0.savedAt > $1.savedAt }
            saveToFile(merged)
            return (true, "成功导入并合并 \(imported.count) 条记录，当前共 \(merged.count) 条")
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
