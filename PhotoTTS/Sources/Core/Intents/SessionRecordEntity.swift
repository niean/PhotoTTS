import AppIntents
import Foundation

// MARK: - 绘本实体（供 Siri 识别用）
struct SessionRecordEntity: AppEntity {
    let id: String
    let name: String

    static var defaultQuery = SessionRecordEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "绘本")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - 绘本实体查询
struct SessionRecordEntityQuery: EntityQuery {
    // 根据 id 列表加载实体（Siri 内部使用）
    func entities(for identifiers: [String]) async throws -> [SessionRecordEntity] {
        let all = SessionRecordManager.shared.getAllSessionMetadata()
        return all
            .filter { identifiers.contains($0.id) }
            .map { SessionRecordEntity(id: $0.id, name: $0.name) }
    }

    // 候选列表：Siri 提示时展示全部已保存绘本
    func suggestedEntities() async throws -> [SessionRecordEntity] {
        return SessionRecordManager.shared.getAllSessionMetadata()
            .map { SessionRecordEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - 字符串搜索（模糊匹配）
extension SessionRecordEntityQuery: EntityStringQuery {
    // 模糊匹配规则（满足其一即可）：
    //   1. 全名包含 query（兜底）
    //   2. 全名第一个空格之后的部分（跳过日期前缀）包含 query
    //      例：name = "26.02.26 贝贝熊-作业的烦恼"，afterSpace = "贝贝熊-作业的烦恼"
    //   3. afterSpace 按 "-" 分段后逐段匹配（剔除减号）
    //      例：afterSpace = "贝贝熊-作业的烦恼" -> ["贝贝熊", "作业的烦恼"]
    //          query = "作业的烦恼" -> 命中第二段
    func entities(matching string: String) async throws -> [SessionRecordEntity] {
        let all = SessionRecordManager.shared.getAllSessionMetadata()
        return all
            .filter { matches(name: $0.name, query: string) }
            .map { SessionRecordEntity(id: $0.id, name: $0.name) }
    }

    private func matches(name: String, query: String) -> Bool {
        // 1. 全名包含 query
        if name.localizedCaseInsensitiveContains(query) { return true }

        // 确定搜索基准：有日期前缀（空格分隔）则取空格后的内容部分
        let searchBase: String = {
            if let spaceIdx = name.firstIndex(of: " ") {
                return String(name[name.index(after: spaceIdx)...])
            }
            return name
        }()

        // 2. 内容部分包含 query
        if searchBase.localizedCaseInsensitiveContains(query) { return true }

        // 3. 按减号分段后逐段匹配（如 "贝贝熊-作业的烦恼" -> ["贝贝熊", "作业的烦恼"]）
        let segments = searchBase.components(separatedBy: "-")
        for segment in segments {
            let s = segment.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty && s.localizedCaseInsensitiveContains(query) { return true }
        }

        // 4. 剔除减号后全文匹配（"贝贝熊作业的烦恼" 匹配 "贝贝熊-作业的烦恼"）
        let baseNoDash = searchBase.replacingOccurrences(of: "-", with: "")
        let queryNoDash = query.replacingOccurrences(of: "-", with: "")
        if baseNoDash.localizedCaseInsensitiveContains(queryNoDash) { return true }

        return false
    }
}
