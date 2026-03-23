# Design: 导出 README 记录列表按名称倒序排列

## 背景

导出会话记录时，README.txt 中的会话列表当前按"展示顺序"排列，用户希望改为按名称倒序排列。

记录名称格式为 `yy.MM.dd 系列-名称`（如 `26.03.22 绘本-小熊的故事`），按名称倒序意味着日期新的记录排在前面。

## 设计

### 修改点

**文件**: `PhotoTTS/Sources/Core/Managers/Session/SessionRecordManager.swift`

**位置**: `exportSelectedSessions` 方法中 README 内容生成部分（约 1606-1612 行）

### 变更内容

将 `exportedSessions` 按名称倒序排序后再生成列表：

```swift
// 修改前
if !exportedSessions.isEmpty {
    sessionNameList = "\n\n会话列表（按展示顺序）：\n"
    for (index, session) in exportedSessions.enumerated() {
        sessionNameList += "\(index + 1). \(session.name)\n"
    }
}

// 修改后
if !exportedSessions.isEmpty {
    let sortedSessions = exportedSessions.sorted { $0.name > $1.name }
    sessionNameList = "\n\n会话列表（按名称倒序）：\n"
    for (index, session) in sortedSessions.enumerated() {
        sessionNameList += "\(index + 1). \(session.name)\n"
    }
}
```

### 影响范围

- 仅影响导出时生成的 README.txt 文件内容
- 不影响实际导出的会话数据或顺序
- 不影响导入功能

## 验收标准

- [ ] 导出 README.txt 中会话列表按名称倒序排列
- [ ] 列表标题从"按展示顺序"改为"按名称倒序"
- [ ] 构建零警告
