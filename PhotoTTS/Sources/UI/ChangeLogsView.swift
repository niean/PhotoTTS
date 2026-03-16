import SwiftUI

/// 更新记录页，内容来自 Bundle 内 changelogs.md，以 Markdown 简洁渲染后展示
struct ChangeLogsView: View {
    @State private var content: String = ""
    @State private var isLoading = true
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        CustomZStack {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else {
                    ScrollView {
                        renderedBody
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .padding(.top, 45)
            
            TopAndLeftSideNavigationBar(title: "更新记录", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.fixedNavAction)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.primary)
                }
            })
        }
        .navigationBarHidden(true)
        .onAppear {
            loadChangelog()
        }
    }
    
    @ViewBuilder
    private var renderedBody: some View {
        if content.isEmpty || content == "暂无更新记录。" {
            Text(content.isEmpty ? "暂无更新记录。" : content)
                .font(Constants.Fonts.body)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
    }
    
    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .title(let text):
            Text(text)
                .font(Constants.Fonts.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        case .heading(let text):
            Text(text)
                .font(Constants.Fonts.headline)
                .foregroundStyle(.primary)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(Constants.Fonts.subheadline)
                    .foregroundStyle(.primary)
            }
        case .paragraph(let text):
            Text(text)
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.primary)
        case .table(header: let header, rows: let rows):
            tableView(header: header, rows: rows)
        case .separator:
            Divider()
                .padding(.vertical, 4)
        }
    }
    
    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !blocks.isEmpty, !isSeparator(blocks.last) {
                    blocks.append(.separator)
                }
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(.title(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.heading(String(trimmed.dropFirst(3))))
                i += 1
                continue
            }
            if trimmed == "---" {
                blocks.append(.separator)
                i += 1
                continue
            }
            if trimmed.hasPrefix("- ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                if let parsed = parseTable(lines: tableLines) {
                    blocks.append(.table(header: parsed.header, rows: parsed.rows))
                }
                continue
            }
            blocks.append(.paragraph(trimmed))
            i += 1
        }
        return blocks
    }
    
    @ViewBuilder
    private func tableView(header: [String], rows: [[String]]) -> some View {
        let columnCount = max(header.count, rows.first?.count ?? 0)
        if columnCount > 0 {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(header.prefix(columnCount).enumerated()), id: \.offset) { i, cell in
                    Text(cell.trimmingCharacters(in: .whitespaces))
                        .font(Constants.Fonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: i == columnCount - 1 ? .leading : .leading)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Divider()
                .padding(.vertical, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(row.prefix(columnCount).enumerated()), id: \.offset) { i, cell in
                        Text(cell.trimmingCharacters(in: .whitespaces))
                            .font(Constants.Fonts.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        }
    }
    
    /// 解析 Markdown 表格：首行为表头，第二行若为分隔行则跳过，其余为数据行
    private func parseTable(lines: [String]) -> (header: [String], rows: [[String]])? {
        guard !lines.isEmpty else { return nil }
        func cells(from line: String) -> [String] {
            line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let header = cells(from: lines[0])
        guard !header.isEmpty else { return nil }
        var rows: [[String]] = []
        for idx in 1..<lines.count {
            let row = cells(from: lines[idx])
            if row.isEmpty { continue }
            if row.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == " " }) }) { continue }
            rows.append(row)
        }
        return (header: header, rows: rows)
    }
    
    private func isSeparator(_ block: MarkdownBlock?) -> Bool {
        if case .separator = block { return true }
        return false
    }
    
    private func loadChangelog() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            if let url = Bundle.main.url(forResource: "changelogs", withExtension: "md"),
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8), !text.isEmpty {
                result = text
            } else {
                result = "暂无更新记录。"
            }
            DispatchQueue.main.async {
                content = result
                isLoading = false
            }
        }
    }
}

private enum MarkdownBlock {
    case title(String)
    case heading(String)
    case bullet(String)
    case paragraph(String)
    case table(header: [String], rows: [[String]])
    case separator
}
