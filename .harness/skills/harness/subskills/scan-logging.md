---
name: scan-logging
description: Reviewer 或治理代码时扫描日志规范
---

# Subskill: 扫描日志规范

## 任务

扫描源代码检查日志规范，逐文件读取，输出违规清单。

## 输入

- {files}：文件路径列表（可选）。未提供时扫描默认范围。

## 默认扫描范围

PhotoTTS/Sources/ 下全部 .swift 文件。

## 检查规则

1. 禁止 print() -- 统一 `os.Logger`，分类定义在 PhotoTTSApp.swift `extension os.Logger`。
2. 日志禁止润色 -- 禁用 emoji/加粗/斜体。
3. 错误信息分两层 -- 用户提示：中文无技术细节；开发日志：os.Logger 含错误码。
4. 禁止输出敏感信息 -- 禁止日志输出完整密钥，仅末四位 `key=***abcd`。

## 已知例外（不视为违规）

- #if DEBUG 条件编译块内的 print() 用于开发调试
- 测试代码中的 print() 用于测试输出
- Xcode Preview 中的调试输出

## 输出格式

```
## 日志规范 扫描结果
违规数量：N
| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
未发现违规的检查项：...
```
